import Foundation

struct Ticker: Identifiable, Hashable {
    let symbol: String
    let label: String
    var id: String { symbol }
}

/// 表示内容の設定。環境変数で上書きできるので、起動スクリプト側から変えられる。
enum HUDConfig {
    /// 天気を出す地点（既定は東京）
    static var cityName: String { value(for: "HUD_CITY") ?? "TOKYO" }
    static var latitude: Double { value(for: "HUD_LAT").flatMap(Double.init) ?? 35.6812 }
    static var longitude: Double { value(for: "HUD_LON").flatMap(Double.init) ?? 139.7671 }

    /// 株価・為替の銘柄（Yahoo Financeのシンボル）
    static let tickers: [Ticker] = [
        Ticker(symbol: "^N225", label: "NIKKEI 225"),
        Ticker(symbol: "USDJPY=X", label: "USD / JPY"),
        Ticker(symbol: "^GSPC", label: "S&P 500"),
        Ticker(symbol: "NVDA", label: "NVIDIA"),
        Ticker(symbol: "AAPL", label: "APPLE"),
        Ticker(symbol: "BTC-USD", label: "BITCOIN")
    ]

    /// 音を拾う対象アプリ。アプリ名かバンドルIDに含まれる文字列で指定する。
    /// 例: HUD_AUDIO_APPS="codex,chatgpt,terminal"
    static var audioAppKeywords: [String] {
        (value(for: "HUD_AUDIO_APPS") ?? "codex")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// 音声で起動するときの合図。認識のゆらぎを拾うため語幹で持つ。
    /// 変更するには次のどちらか:
    ///   defaults write app.orrery.hud wakePhrases "オレリ,コーデック"
    ///   HUD_WAKE_PHRASES="オレリ,コーデック" で起動
    static var wakePhrases: [String] {
        let raw = UserDefaults.standard.string(forKey: "wakePhrases")
            ?? value(for: "HUD_WAKE_PHRASES")
            ?? "オレリ,オーレリ,コーデック,コデック,orrery,codex"
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 一致しても起動せずログだけ出す（合図の調整用）
    static var wakeDryRun: Bool { UserDefaults.standard.bool(forKey: "wakeDryRun") }

    static var wakePhraseLocale: String { value(for: "HUD_WAKE_LOCALE") ?? "ja-JP" }

    /// 粒子の数。負荷が高いときに減らせる（0で粒子を描かない）
    static var grainCount: Int { value(for: "HUD_GRAINS").flatMap(Int.init) ?? 1100 }

    /// 画面の更新頻度。全画面を描き直すので、待機中は落として負荷を下げる。
    static var activeFrameRate: Double { value(for: "HUD_FPS").flatMap(Double.init) ?? 30 }
    static var idleFrameRate: Double { value(for: "HUD_IDLE_FPS").flatMap(Double.init) ?? 12 }

    /// 切り分け用: 1にすると動く描画を止める
    static var isStatic: Bool { value(for: "HUD_STATIC") == "1" }

    static func frameInterval(isLive: Bool) -> Double {
        1 / max(1, isLive ? activeFrameRate : idleFrameRate)
    }

    /// 待機中に何回に1回描くか
    static func frameDivisor(isLive: Bool) -> Int {
        isLive ? 1 : max(1, Int((activeFrameRate / max(1, idleFrameRate)).rounded()))
    }

    static let systemInterval: TimeInterval = 1
    static let weatherInterval: TimeInterval = 600
    static let marketInterval: TimeInterval = 60
    static let usageInterval: TimeInterval = 300
    /// 対象アプリが起動・終了していないか見張る間隔
    static let audioSourceInterval: TimeInterval = 6

    private static func value(for key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        return raw
    }
}
