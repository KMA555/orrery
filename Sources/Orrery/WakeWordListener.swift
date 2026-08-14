import AVFoundation
import Speech
import SwiftUI

/// 決めた言葉を聞き取ったらセッションを開く。認識は端末内だけで行い、音声は保存も送信もしない。
@MainActor
final class WakeWordListener: ObservableObject {
    @Published private(set) var isListening = false
    /// 直近に聞き取れた文（うまく反応しないときの手がかり用）
    @Published private(set) var heard = ""
    @Published private(set) var message: String?
    @Published var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
            enabled ? start() : stop()
        }
    }

    /// 呼び出し側でセッション開始につなぐ
    var onTrigger: (() -> Void)?
    /// セッション中は反応させない（Codexの声で自分が誤爆しないように）
    var isSuppressed: () -> Bool = { false }

    private static let preferenceKey = "wakeWordEnabled"
    private static let cooldown: TimeInterval = 6

    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private let recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var lastTrigger = Date.distantPast
    /// キャンセルした古いタスクのコールバックを無視するための世代番号
    private var generation = 0
    private var tapInstalled = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: HUDConfig.wakePhraseLocale))
        enabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)
        if enabled { start() }
    }

    // MARK: - 開始と停止

    private func start() {
        // 素の実行ファイルだと用途説明を読めず、許可を求めた瞬間にOSがプロセスを落とす
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            message = "音声起動は Orrery.app から起動したときだけ使えます（ORRERYを起動.command を実行してください）"
            enabled = false
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            message = "この端末では音声認識が使えません"
            enabled = false
            return
        }

        // 許可のコールバックは任意のスレッドで来るので、必ずメインへ渡す
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.message = "音声認識が許可されていません（システム設定 › プライバシーとセキュリティ › 音声認識）"
                    self.enabled = false
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        guard granted else {
                            self.message = "マイクが許可されていません（システム設定 › プライバシーとセキュリティ › マイク）"
                            self.enabled = false
                            return
                        }
                        self.beginListening()
                    }
                }
            }
        }
    }

    private func beginListening() {
        guard !isListening else { return }
        do {
            if !tapInstalled {
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0 else {
                    message = "マイクが見つかりません"
                    enabled = false
                    return
                }
                AudioSpectrum.log("wake: input format \(format.sampleRate)Hz \(format.channelCount)ch")
                box.prepare(from: format)
                input.installTap(onBus: 0, bufferSize: 2048, format: format) { [box] buffer, _ in
                    box.append(buffer)
                }
                tapInstalled = true
            }
            engine.prepare()
            try engine.start()
        } catch {
            message = "マイクを開けませんでした"
            enabled = false
            return
        }

        isListening = true
        message = nil
        AudioSpectrum.log("wake: engine started, onDevice=\(recognizer?.supportsOnDeviceRecognition ?? false)")
        restartTask()

        // 認識タスクには時間の上限があるので、定期的に貼り替える
        let timer = Timer(timeInterval: 50, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartTask() }
        }
        RunLoop.main.add(timer, forMode: .common)
        restartTimer = timer
    }

    private func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        box.finish()
        if engine.isRunning { engine.stop() }
        isListening = false
        heard = ""
    }

    // MARK: - 認識

    private func restartTask() {
        guard isListening, let recognizer else { return }
        generation += 1
        let current = generation
        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        box.set(request)

        task = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor [weak self] in
                // 古い世代のタスクからの通知は捨てる（これが無いと再起動が連鎖して暴走する）
                guard let self, current == self.generation else { return }
                if let result {
                    // 聞き取った内容はログに残さない（画面に一時表示するだけ）
                    self.consider(result.bestTranscription.formattedString)
                    if result.isFinal { self.restartTask() }
                } else if error != nil {
                    // 無音が続くと終了するので、間を置いてから貼り替える
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard current == self.generation else { return }
                    self.restartTask()
                }
            }
        }
    }

    private func consider(_ transcript: String) {
        heard = String(transcript.suffix(40))
        guard !isSuppressed(),
              Date().timeIntervalSince(lastTrigger) > Self.cooldown else { return }

        let flattened = Self.flatten(transcript)
        guard HUDConfig.wakePhrases.contains(where: { flattened.contains(Self.flatten($0)) }) else { return }

        AudioSpectrum.log("wake: 合図に一致しました")
        lastTrigger = Date()
        heard = ""
        restartTask()
        guard !HUDConfig.wakeDryRun else { return }
        onTrigger?()
    }

    /// 空白・記号・全角半角・ひらがなカタカナの違いを吸収して比べる
    private static func flatten(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                                  locale: Locale(identifier: "ja_JP"))
        let kana = folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
        return kana.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.append(Character($1)) }
    }
}

/// オーディオスレッドと認識リクエストの受け渡し。
/// 認識器は16kHzモノラルを期待するので、入力形式が違えばここで変換する。
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var converter: AVAudioConverter?
    private var appended = 0

    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 16_000, channels: 1, interleaved: false)!

    func prepare(from format: AVAudioFormat) {
        lock.lock()
        converter = format == target ? nil : AVAudioConverter(from: format, to: target)
        lock.unlock()
        AudioSpectrum.log("wake: converter=\(format == target ? "不要" : "作成")")
    }

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request?.endAudio()
        request = newRequest
        converter?.reset()
        lock.unlock()
    }

    func finish() {
        set(nil)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        let converter = self.converter
        appended += 1
        let count = appended
        lock.unlock()

        guard let current else { return }
        _ = count

        guard let converter else {
            current.append(buffer)
            return
        }
        guard let converted = Self.convert(buffer, with: converter, to: target) else { return }
        current.append(converted)
    }

    private static func convert(_ buffer: AVAudioPCMBuffer,
                                with converter: AVAudioConverter,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
