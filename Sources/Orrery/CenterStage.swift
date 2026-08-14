import SwiftUI

struct CenterStage: View {
    @EnvironmentObject private var audio: AudioSpectrum
    let cpu: Double
    let memory: Double
    @State private var started = Date()

    var body: some View {
        ZStack {
            // 絵の更新はこのサブツリーだけで完結させる（画面全体の再レイアウトを避ける）
            HostedAnimation {
                DialTimeline(audio: audio, cpu: cpu, memory: memory, started: started)
            }
            CodexReadout(isLive: audio.isLive,
                         source: audio.sourceLabel,
                         isTargeted: audio.isTargeted)
        }
        .overlay(alignment: .bottom) { CodexButton() }
    }
}

private struct CodexReadout: View {
    let isLive: Bool
    let source: String
    let isTargeted: Bool

    private static let tracking: CGFloat = 14

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(HUD.mono(9, .bold))
                .tracking(1.2)
                .foregroundStyle(HUD.warn)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(HUD.warn.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("ORRERY")
                .font(.system(size: 64, weight: .black, design: .default))
                .tracking(Self.tracking)
                // trackingは最後の文字の後ろにも隙間を作るので、その半分だけ右に寄せて中心を合わせる
                .padding(.leading, Self.tracking)
                .foregroundStyle(.white)
                .shadow(color: HUD.cyan.opacity(isLive ? 0.9 : 0.45), radius: 18)

            HStack(spacing: 7) {
                Circle()
                    .fill(isLive ? HUD.up : HUD.cyan.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .shadow(color: HUD.up.opacity(isLive ? 0.9 : 0), radius: 5)
                Text(isLive ? "SPEAKING" : "STANDBY")
                    .font(HUD.mono(10, .bold))
                    .tracking(2.2)
                    .foregroundStyle(isLive ? .white : HUD.cyan.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(HUD.cyan.opacity(isLive ? 0.14 : 0.04)))
            .overlay(Capsule().stroke(HUD.cyan.opacity(isLive ? 0.5 : 0.15), lineWidth: 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isLive)

            Text("SOURCE ▸ \(source)")
                .font(HUD.mono(9, .semibold))
                .tracking(1.4)
                .foregroundStyle((isTargeted ? HUD.cyan : HUD.warn).opacity(0.6))
                .lineLimit(1)

            if source == "NO ACCESS" {
                HStack(spacing: 8) {
                    smallButton("設定を開く") { PrivacySettings.open(.screenCapture) }
                    smallButton("許可したら再起動") { PrivacySettings.relaunch() }
                }
            }
        }
    }
}

/// 押すとCodexアプリの音声ライブが立ち上がり、話している間はHUDが最前面に出る。
private struct CodexButton: View {
    @EnvironmentObject private var windowState: HUDWindowState
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 9) {
            Button(action: toggle) {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                    Text(title)
                        .font(HUD.mono(12, .bold))
                        .tracking(2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: windowState.sessionActive
                            ? [HUD.up.opacity(0.34), HUD.cyan.opacity(0.34)]
                            : [HUD.cyan.opacity(0.34), HUD.violet.opacity(0.34)],
                        startPoint: .leading, endPoint: .trailing))
                )
                .overlay(Capsule().stroke(HUD.cyan.opacity(hovering ? 0.9 : 0.45), lineWidth: 1))
                .shadow(color: HUD.cyan.opacity(hovering ? 0.55 : 0.25), radius: hovering ? 16 : 8)
                .scaleEffect(hovering ? 1.04 : 1)
            }
            .buttonStyle(.plain)
            .disabled(windowState.starting)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)

            if let notice = windowState.notice {
                VStack(spacing: 6) {
                    Text(notice)
                        .font(HUD.mono(10))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(HUD.warn.opacity(0.85))
                        .frame(maxWidth: 460)
                    HStack(spacing: 8) {
                        noticeButton("アクセシビリティ設定を開く") {
                            PrivacySettings.open(.accessibility)
                        }
                        noticeButton("許可したら再起動") { PrivacySettings.relaunch() }
                    }
                }
            }
        }
    }

    private func noticeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(HUD.mono(9, .bold))
                .tracking(1.2)
                .foregroundStyle(HUD.warn)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(HUD.warn.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if windowState.sessionActive { return "セッション終了" }
        return windowState.starting ? "起動中…" : "CODEX と話す"
    }

    private var icon: String {
        windowState.sessionActive ? "stop.circle.fill" : "waveform.circle.fill"
    }

    private func toggle() {
        if windowState.sessionActive {
            windowState.endVoiceSession()
        } else {
            windowState.requestVoiceSession()
        }
    }
}

/// 中央の絵の更新だけを回す。
private struct DialTimeline: View {
    let audio: AudioSpectrum
    let cpu: Double
    let memory: Double
    let started: Date

    var body: some View {
        if HUDConfig.isStatic {
            OrreryDial(snapshot: audio.current, cpu: cpu, memory: memory)
        } else {
            TimelineView(.periodic(from: started,
                                   by: HUDConfig.frameInterval(isLive: audio.isLive))) { _ in
                OrreryDial(snapshot: audio.current, cpu: cpu, memory: memory)
            }
        }
    }
}
