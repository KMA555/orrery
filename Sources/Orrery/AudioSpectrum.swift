import AVFoundation
import Combine
import QuartzCore
import ScreenCaptureKit
import SwiftUI

/// 見た目と反応の調整値。数字を変えるだけで挙動を追い込める。
enum Tuning {
    static let bandCount = 40
    static let fftSize = 2048
    /// 窓を重ねて、表示の追従を速くする
    static let fftHop = 512
    static let sampleRate = 48_000

    /// バンドをdBから0〜1へ写すときの範囲。小さい音まで拾いたければfloorを下げる。
    static let bandFloorDecibels: Float = -72
    static let bandCeilingDecibels: Float = -22
    /// 高域の持ち上げ量（1桁ぶんの周波数あたりのdB）
    static let tiltDecibels: Float = 9

    static let levelFloorDecibels: Float = -56
    static let levelCeilingDecibels: Float = -14

    /// 画面の更新間隔。60fpsだとレイアウト計算が重いので30fpsで回す。
    static let frameRate: CGFloat = 30

    /// バーの立ち上がり（0〜1、大きいほど機敏）と落ち方（1フレームあたり）
    static let bandAttack: CGFloat = 0.55
    static let bandDecay: CGFloat = 0.11

    /// 「音が出ている」と判定するレベルと、無音後に待機へ戻るまでの秒数
    static let liveThreshold: CGFloat = 0.12
    static let liveHold: CFTimeInterval = 0.45

    /// 待機↔出力中の切り替わりの速さ
    static let activationAttack: CGFloat = 0.28
    static let activationRelease: CGFloat = 0.08
}

/// 1フレーム分の描画データ。まとめて publish して再描画を1回にする。
struct SpectrumSnapshot: Equatable {
    var bands: [CGFloat]
    var level: CGFloat
    /// 0＝待機、1＝出力中。切り替えを滑らかに見せるための連続値。
    var activation: CGFloat
    var isLive: Bool
    var time: CGFloat

    static let idle = SpectrumSnapshot(bands: Array(repeating: 0, count: Tuning.bandCount),
                                       level: 0,
                                       activation: 0,
                                       isLive: false,
                                       time: 0)
}

/// オーディオスレッドと画面更新のあいだの受け渡し。
final class SpectrumStore: @unchecked Sendable {
    private let lock = NSLock()
    private var bands: [Float]
    private var level: Float = 0
    private var updatedAt: CFTimeInterval = 0

    init(bandCount: Int) {
        bands = Array(repeating: 0, count: bandCount)
    }

    func write(bands newBands: [Float], level newLevel: Float) {
        lock.lock()
        bands = newBands
        level = newLevel
        updatedAt = CACurrentMediaTime()
        lock.unlock()
    }

    /// しばらくデータが来なければ無音として返す（ストリームが止まっても固まらない）
    func read() -> (bands: [Float], level: Float) {
        lock.lock()
        defer { lock.unlock() }
        guard CACurrentMediaTime() - updatedAt < 0.3 else {
            return (Array(repeating: 0, count: bands.count), 0)
        }
        return (bands, level)
    }
}

/// ScreenCaptureKitからの音声を受け取る側。専用のシリアルキューでのみ呼ばれる。
final class AudioTap: NSObject, SCStreamOutput {
    private let store: SpectrumStore
    private let analyzer: SpectrumAnalyzer

    init(store: SpectrumStore, analyzer: SpectrumAnalyzer) {
        self.store = store
        self.analyzer = analyzer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              let samples = Self.monoSamples(from: sampleBuffer),
              let frame = analyzer.push(samples) else { return }
        store.write(bands: frame.bands, level: frame.level)
    }

    private static func monoSamples(from buffer: CMSampleBuffer) -> [Float]? {
        guard let description = CMSampleBufferGetFormatDescription(buffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return nil }

        var result: [Float]?
        try? buffer.withAudioBufferList { list, _ in
            guard let first = list.first, let data = first.mData else { return }
            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return }
            let pointer = data.bindMemory(to: Float.self, capacity: count)
            let channels = Int(first.mNumberChannels)
            if channels <= 1 {
                result = Array(UnsafeBufferPointer(start: pointer, count: count))
            } else {
                // インターリーブされている場合は先頭チャンネルだけ取り出す
                var mono = [Float](repeating: 0, count: count / channels)
                for index in mono.indices { mono[index] = pointer[index * channels] }
                result = mono
            }
        }
        return result
    }
}

/// 音源の選択。変更はまれなので、毎フレーム更新される AudioSpectrum とは別にしてある。
@MainActor
final class AudioSettings: ObservableObject {
    /// Codexだけを見るか、システム全体の音を見るか
    @Published var codexOnly: Bool = UserDefaults.standard.object(forKey: "codexOnly") as? Bool ?? true {
        didSet { UserDefaults.standard.set(codexOnly, forKey: "codexOnly") }
    }
    /// 自分の声（マイク）も見るか
    @Published var microphone: Bool = UserDefaults.standard.bool(forKey: "microphoneEnabled") {
        didSet { UserDefaults.standard.set(microphone, forKey: "microphoneEnabled") }
    }
}

/// マイクの生バッファを解析する。オーディオスレッドからのみ触る。
final class MicTap: @unchecked Sendable {
    private let store: SpectrumStore
    private let analyzer: SpectrumAnalyzer

    init(store: SpectrumStore, analyzer: SpectrumAnalyzer) {
        self.store = store
        self.analyzer = analyzer
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        guard let frame = analyzer.push(samples) else { return }
        store.write(bands: frame.bands, level: frame.level)
    }
}

@MainActor
final class AudioSpectrum: ObservableObject {
    /// 毎フレーム更新される値。@Published にすると画面全体のレイアウトが走るので通知しない。
    /// 描画側は TimelineView から取りに来る。
    private(set) var current = SpectrumSnapshot.idle
    /// 表示の切り替えに関わる、めったに変わらない値だけ通知する
    @Published private(set) var isLive = false
    @Published private(set) var message: String?
    /// いま音を拾っている対象（Codexが見つからなければシステム全体）
    @Published private(set) var sourceLabel = "SEARCHING…"
    @Published private(set) var isTargeted = false
    /// 音源の設定。毎フレーム更新される snapshot と混ぜると画面全体が再計算されるので分けてある。
    let settings = AudioSettings()
    private var cancellables: Set<AnyCancellable> = []

    private let store = SpectrumStore(bandCount: Tuning.bandCount)
    private let queue = DispatchQueue(label: "app.orrery.audio", qos: .userInteractive)
    private lazy var tap = AudioTap(store: store,
                                    analyzer: SpectrumAnalyzer(size: Tuning.fftSize,
                                                               hop: Tuning.fftHop,
                                                               bandCount: Tuning.bandCount,
                                                               sampleRate: Float(Tuning.sampleRate)))
    private var stream: SCStream?
    private var ticker: Timer?
    private var sourceTicker: Timer?
    private var lastLoud: CFTimeInterval = 0
    private var matchedBundles: Set<String> = []

    private let micStore = SpectrumStore(bandCount: Tuning.bandCount)
    private let micEngine = AVAudioEngine()
    private lazy var micTap = MicTap(store: micStore,
                                     analyzer: SpectrumAnalyzer(size: Tuning.fftSize,
                                                                hop: Tuning.fftHop,
                                                                bandCount: Tuning.bandCount,
                                                                sampleRate: Float(Tuning.sampleRate)))
    private var micTapInstalled = false

    private enum CaptureError: Error { case noDisplay }

    init() {
        settings.$codexOnly.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.matchedBundles = ["__force__"]
            Task { await self.refreshSource() }
        }.store(in: &cancellables)

        settings.$microphone.dropFirst().sink { [weak self] isOn in
            guard let self else { return }
            isOn ? self.startMicrophone() : self.stopMicrophone()
        }.store(in: &cancellables)
    }

    private static var didRequestScreenAccess = false

    /// 診断ログを ~/Library/Logs/Orrery.log に残す（どのスレッドからでも呼べる）
    nonisolated static func log(_ text: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/Orrery.log")
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }

    /// Codex本体はアプリ名が"ChatGPT"なので、バンドルIDから分かりやすい名前に直す
    private static let friendlyNames = [
        "com.openai.codex": "CODEX",
        "com.steipete.codexbar": "CODEXBAR"
    ]

    private static func displayName(_ application: SCRunningApplication) -> String {
        friendlyNames[application.bundleIdentifier.lowercased()]
            ?? application.applicationName.uppercased()
    }

    func start() async {
        Self.log("設定: grains=\(HUDConfig.grainCount) fps=\(HUDConfig.activeFrameRate)/\(HUDConfig.idleFrameRate) static=\(HUDConfig.isStatic)")
        startTicker()
        if settings.microphone { startMicrophone() }
        guard stream == nil else { return }
        await attach()
    }

    /// 画面収録の許可があとから通ることもあるので、失敗したら数秒おきに繰り返す
    private func attach() async {
        // 許可ダイアログは1回の起動につき1度だけ。繰り返すと出続けてしまう。
        if !CGPreflightScreenCaptureAccess(), !Self.didRequestScreenAccess {
            Self.didRequestScreenAccess = true
            _ = CGRequestScreenCaptureAccess()
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { throw CaptureError.noDisplay }

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = Tuning.sampleRate
            configuration.channelCount = 2
            // 映像は使わないので最小構成にして負荷を落とす
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let stream = SCStream(filter: makeFilter(display: display, content: content),
                                  configuration: configuration,
                                  delegate: nil)
            try stream.addStreamOutput(tap, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            message = nil
            Self.log("capture started: source=\(sourceLabel)")
            startSourceWatcher()
        } catch {
            message = "画面収録を許可すると音声に反応します"
            sourceLabel = "NO ACCESS"
            Self.log("CAPTURE FAILED: \((error as NSError).domain) code=\((error as NSError).code)")
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await attach()
        }
    }

    /// 対象アプリだけを含むフィルタを作る。見つからないときはシステム全体にする。
    private func makeFilter(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        guard settings.codexOnly else {
            matchedBundles = []
            isTargeted = false
            sourceLabel = "SYSTEM"
            return SCContentFilter(display: display, excludingWindows: [])
        }

        let keywords = HUDConfig.audioAppKeywords
        let ownProcess = ProcessInfo.processInfo.processIdentifier

        if ProcessInfo.processInfo.environment["HUD_DEBUG_APPS"] != nil {
            let listing = content.applications
                .map { "\($0.applicationName) [\($0.bundleIdentifier)] pid=\($0.processID)" }
                .sorted()
                .joined(separator: "\n")
            FileHandle.standardError.write("--- SHAREABLE APPS ---\n\(listing)\n--- END ---\n".data(using: .utf8)!)
        }
        let matches = content.applications.filter { application in
            // 自分自身とmacOSの補助プロセスは対象外
            guard application.processID != ownProcess else { return false }
            let bundle = application.bundleIdentifier.lowercased()
            guard !bundle.hasPrefix("com.apple.") else { return false }
            let name = application.applicationName.lowercased()
            return keywords.contains { name.contains($0) || bundle.contains($0) }
        }

        matchedBundles = Set(matches.map(\.bundleIdentifier))
        guard !matches.isEmpty else {
            isTargeted = false
            sourceLabel = "SYSTEM (対象なし)"
            return SCContentFilter(display: display, excludingWindows: [])
        }

        isTargeted = true
        let names = Set(matches.map(Self.displayName)).sorted()
        sourceLabel = names.count > 2
            ? names.prefix(2).joined(separator: " + ") + " +\(names.count - 2)"
            : names.joined(separator: " + ")
        return SCContentFilter(display: display, including: matches, exceptingWindows: [])
    }

    /// 対象アプリが起動・終了したらフィルタを貼り替える。
    private func startSourceWatcher() {
        guard sourceTicker == nil else { return }
        let timer = Timer(timeInterval: HUDConfig.audioSourceInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshSource() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sourceTicker = timer
    }

    private func refreshSource() async {
        guard let stream else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first else { return }

        let previous = matchedBundles
        let filter = makeFilter(display: display, content: content)
        guard previous != matchedBundles else { return }
        try? await stream.updateContentFilter(filter)
    }

    private func startMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard granted else {
                    self.settings.microphone = false
                    self.message = "マイクが許可されていません（システム設定 › プライバシーとセキュリティ › マイク）"
                    return
                }
                do {
                    if !self.micTapInstalled {
                        let input = self.micEngine.inputNode
                        let format = input.outputFormat(forBus: 0)
                        guard format.sampleRate > 0 else {
                            self.settings.microphone = false
                            self.message = "マイクが見つかりません"
                            return
                        }
                        let tap = self.micTap
                        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                            tap.handle(buffer)
                        }
                        self.micTapInstalled = true
                    }
                    self.micEngine.prepare()
                    try self.micEngine.start()
                    self.message = nil
                } catch {
                    self.settings.microphone = false
                    self.message = "マイクを開けませんでした"
                }
            }
        }
    }

    private func stopMicrophone() {
        if micEngine.isRunning { micEngine.stop() }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0 / Double(Tuning.frameRate), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // ウィンドウをドラッグ中も止まらないように common モードで回す
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        let snapshot = current
        let output = store.read()
        // マイクとシステム音のうち、大きいほうで動かす
        let reading: (bands: [Float], level: Float)
        if settings.microphone {
            let mic = micStore.read()
            reading = (zip(output.bands, mic.bands).map { max($0, $1) },
                       max(output.level, mic.level))
        } else {
            reading = output
        }

        var next = snapshot
        next.time += 1 / Tuning.frameRate

        for index in next.bands.indices {
            let target = CGFloat(reading.bands[index])
            next.bands[index] = target > next.bands[index]
                ? next.bands[index] + (target - next.bands[index]) * Tuning.bandAttack
                : max(target, next.bands[index] - Tuning.bandDecay)
        }

        let targetLevel = CGFloat(reading.level)
        next.level = targetLevel > next.level
            ? next.level + (targetLevel - next.level) * 0.6
            : max(targetLevel, next.level - 0.08)

        let now = CACurrentMediaTime()
        if targetLevel > Tuning.liveThreshold { lastLoud = now }
        next.isLive = now - lastLoud < Tuning.liveHold

        let goal: CGFloat = next.isLive ? 1 : 0
        let rate = next.isLive ? Tuning.activationAttack : Tuning.activationRelease
        next.activation += (goal - next.activation) * min(1, rate * 2)

        current = next
        if next.isLive != isLive { isLive = next.isLive }
    }
}
