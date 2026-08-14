import SwiftUI

/// データ取得役をまとめて持つ。@StateObject で持つと更新のたびに画面全体が作り直されるので、
/// 監視は各パネル側（@ObservedObject）に閉じ込める。
@MainActor
final class Services {
    let system = SystemMonitor()
    let weather = WeatherService()
    let market = MarketService()
    let usage = UsageService()
    let wake = WakeWordListener()
}

struct HUDView: View {
    @EnvironmentObject private var windowState: HUDWindowState
    @ObservedObject private var settings = HUDSettings.shared
    @State private var services = Services()

    var body: some View {
        GeometryReader { proxy in
            let leftWidth = min(380, max(270, proxy.size.width * 0.185))
            let rightWidth = min(430, max(310, proxy.size.width * 0.215))

            ZStack {
                AudioBackdrop()
                VStack(spacing: 14) {
                    TopBar(system: services.system,
                           windowState: windowState,
                           wake: services.wake) {
                        Task {
                            await services.weather.refresh()
                            await services.market.refresh()
                            await services.usage.refresh()
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        if settings.showSystem || settings.showNetwork || settings.showUsage {
                            VStack(spacing: 14) {
                                if settings.showSystem { SystemPanel(system: services.system) }
                                if settings.showNetwork { NetworkPanel(system: services.system) }
                                if settings.showUsage { UsagePanel(usage: services.usage) }
                                Spacer(minLength: 0)
                            }
                            .frame(width: leftWidth)
                        }

                        CenterColumn(system: services.system)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if settings.showWeather || settings.showMarket {
                            VStack(spacing: 14) {
                                if settings.showWeather { WeatherPanel(weather: services.weather) }
                                if settings.showMarket { MarketPanel(market: services.market) }
                                Spacer(minLength: 0)
                            }
                            .frame(width: rightWidth)
                        }
                    }

                    if settings.showSand {
                        SandStream()
                            .frame(height: 116)
                            .clipShape(CutCorner())
                            .background(CutCorner().fill(Color.white.opacity(0.02)))
                            .overlay(CutCorner().stroke(HUD.cyan.opacity(0.18), lineWidth: 1))
                    }
                }
                .padding(18)
            }
            // テーマやFPSが変わったら描画ツリーを作り直して、全体に行き渡らせる
            .id(settings.rebuildFingerprint)
        }
        .task {
            services.system.start()
            services.weather.start()
            services.market.start()
            services.usage.start()
            // 音声コマンドとボタンは同じ入口を通す
            services.wake.onTrigger = { windowState.requestVoiceSession() }
            services.wake.isSuppressed = { windowState.sessionActive || windowState.starting }
        }
        // 設定画面で地点や銘柄が変わったら取り直す
        .onReceive(settings.dataRefresh) { _ in
            Task {
                await services.weather.refresh()
                await services.market.refresh()
            }
        }
    }
}

/// 音のレベルで背景が色づく部分だけを切り出して、毎フレームの再描画を局所化する。
private struct AudioBackdrop: View {
    @EnvironmentObject private var audio: AudioSpectrum

    var body: some View {
        HUDBackdrop(activation: audio.isLive ? 1 : 0)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: audio.isLive)
    }
}

private struct TopBar: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var windowState: HUDWindowState
    @ObservedObject var wake: WakeWordListener
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 11) {
                Rectangle().fill(HUD.cyan).frame(width: 4, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(Self.time.string(from: system.now))
                            .font(HUD.mono(30, .bold))
                            .foregroundStyle(.white)
                        Text(Self.seconds.string(from: system.now))
                            .font(HUD.mono(14, .medium))
                            .foregroundStyle(HUD.cyan.opacity(0.75))
                    }
                    .monospacedDigit()
                    Text(Self.date.string(from: system.now).uppercased())
                        .font(HUD.mono(9, .medium))
                        .tracking(2.6)
                        .foregroundStyle(HUD.cyan.opacity(0.6))
                }
            }

            chip(label: "HOST", value: system.hostName)
            chip(label: "IP", value: system.ipAddress)
            chip(label: "CORES", value: "\(system.processorCount)")
            chip(label: "UPTIME", value: Format.duration(system.uptime))

            Spacer(minLength: 8)

            if let message = wake.message {
                Text(message)
                    .font(HUD.mono(9))
                    .foregroundStyle(HUD.warn.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: 300, alignment: .trailing)
            } else if wake.isListening, !wake.heard.isEmpty {
                Text("“\(wake.heard)”")
                    .font(HUD.mono(9))
                    .foregroundStyle(HUD.cyan.opacity(0.40))
                    .lineLimit(1)
                    .frame(maxWidth: 240, alignment: .trailing)
            }

            AudioControls()
            HUDPill(icon: wake.enabled ? "waveform.badge.mic" : "mic.slash",
                    title: wake.enabled ? "音声起動" : "音声OFF",
                    tint: wake.isListening ? HUD.up : HUD.cyan) {
                wake.enabled.toggle()
            }
            HUDPill(icon: "arrow.clockwise", title: "更新", action: refresh)
            HUDPill(icon: windowState.mode.icon, title: windowState.mode.label) {
                windowState.mode = windowState.mode.next
            }
            SettingsPill()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CutCorner(cut: 12).fill(Color.white.opacity(0.025)))
        .overlay(CutCorner(cut: 12).stroke(HUD.cyan.opacity(0.20), lineWidth: 1))
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let seconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ss"
        return formatter
    }()

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE  yyyy.MM.dd"
        return formatter
    }()

    private func chip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(HUD.mono(8, .bold))
                .tracking(1.6)
                .foregroundStyle(HUD.cyan.opacity(0.5))
            Text(value)
                .font(HUD.mono(11, .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(minWidth: 74, alignment: .leading)
    }

}

/// 設定画面（⌘,）を開く。SettingsLinkはボタンではないので、HUDPillと同じ見た目を重ねる。
private struct SettingsPill: View {
    var body: some View {
        SettingsLink {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.fill").font(.system(size: 10, weight: .bold))
                Text("設定").font(HUD.mono(10, .bold)).tracking(1.2)
            }
            .foregroundStyle(HUD.cyan)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(HUD.cyan.opacity(0.08)))
            .overlay(Capsule().stroke(HUD.cyan.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 音源の切り替え。毎フレーム更新される AudioSpectrum ではなく設定だけを見るので、再描画されない。
private struct AudioControls: View {
    @EnvironmentObject private var settings: AudioSettings

    var body: some View {
        HStack(spacing: 8) {
            HUDPill(icon: "waveform",
                    title: settings.codexOnly ? "CODEXのみ" : "全体の音",
                    tint: settings.codexOnly ? HUD.cyan : HUD.violet) {
                settings.codexOnly.toggle()
            }
            HUDPill(icon: settings.microphone ? "mic.fill" : "mic.slash",
                    title: "自分の声",
                    tint: settings.microphone ? HUD.up : HUD.cyan.opacity(0.55)) {
                settings.microphone.toggle()
            }
        }
    }
}

/// CPUとメモリの監視をここで受け止め、中央だけを更新する。
private struct CenterColumn: View {
    @ObservedObject var system: SystemMonitor

    var body: some View {
        CenterStage(cpu: system.cpu,
                    memory: system.memoryTotal > 0 ? system.memoryUsed / system.memoryTotal : 0)
    }
}
