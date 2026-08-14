import AppKit
import ApplicationServices

/// Codexアプリを開き、音声ライブ（composer.startVoiceMode）を立ち上げる。
/// アプリ内ショートカットが ⌃⇧V なので、アプリを前面にしてからキーを送る。
enum CodexLauncher {
    static let bundleIdentifier = "com.openai.codex"
    private nonisolated(unsafe) static var didPromptAccessibility = false

    /// Vキーの仮想キーコード（⌃⇧V = composer.startVoiceMode）
    private static let voiceKeyCode: CGKeyCode = 9
    /// Nキーの仮想キーコード（⌘N = newTask）
    private static let newChatKeyCode: CGKeyCode = 45

    enum Outcome {
        /// アプリを開いて音声モードのキーも送れた
        case started
        /// アプリは開いたが、アクセシビリティ未許可でキーを送れなかった
        case needsAccessibility
        /// Codexアプリが見つからない
        case notInstalled
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static func startVoiceSession(completion: @escaping (Outcome) -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            completion(.notInstalled)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            // 許可ダイアログは1回の起動につき1度だけ。毎回出すと押すたびに出てしまう。
            let trusted = AXIsProcessTrusted()
            if !trusted, !didPromptAccessibility {
                didPromptAccessibility = true
                _ = AXIsProcessTrustedWithOptions(
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            }

            DispatchQueue.main.async {
                guard trusted else {
                    completion(.needsAccessibility)
                    return
                }
                // ショートカットはアプリ内スコープなので、前面に出るまで待つ
                waitUntilFrontmost(remaining: 16) { isFront in
                    guard isFront else {
                        completion(.needsAccessibility)
                        return
                    }
                    // 毎回まっさらなチャットから話し始める
                    send(key: newChatKeyCode, flags: .maskCommand)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        send(key: voiceKeyCode, flags: [.maskControl, .maskShift])
                        completion(.started)
                    }
                }
            }
        }
    }

    /// Codexアプリを前面に戻すだけ
    static func activate() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    private static func waitUntilFrontmost(remaining: Int, completion: @escaping (Bool) -> Void) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
            // 前面になった直後はキーを取りこぼすので少しだけ置く
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completion(true) }
            return
        }
        guard remaining > 0 else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            waitUntilFrontmost(remaining: remaining - 1, completion: completion)
        }
    }

    private static func send(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
