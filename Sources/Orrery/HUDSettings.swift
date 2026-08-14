import Combine
import SwiftUI

/// 設定画面（⌘,）で変えられる項目。UserDefaultsに保存する。
/// 同名の環境変数（HUD_CITY など）が指定されているときはそちらが優先される（HUDConfig側で解決）。
@MainActor
final class HUDSettings: ObservableObject {
    static let shared = HUDSettings()

    private let store = UserDefaults.standard

    // MARK: 一般

    /// 空文字は「既定のまま」の意味
    @Published var cityName: String { didSet { store.set(cityName, forKey: "cityName"); bumpData() } }
    @Published var latitude: Double { didSet { store.set(latitude, forKey: "latitude"); bumpData() } }
    @Published var longitude: Double { didSet { store.set(longitude, forKey: "longitude"); bumpData() } }
    /// 1行に「シンボル:表示名」。空なら既定の銘柄
    @Published var tickersText: String { didSet { store.set(tickersText, forKey: "tickers"); bumpData() } }
    /// カンマ区切り。キーはHUDConfigが昔から読んでいる "wakePhrases" を使い続ける
    @Published var wakePhrasesText: String { didSet { store.set(wakePhrasesText, forKey: "wakePhrases") } }

    // MARK: テーマ

    @Published var theme: HUDTheme { didSet { store.set(theme.rawValue, forKey: "theme"); applyPalette() } }
    @Published var customAccentHex: String { didSet { store.set(customAccentHex, forKey: "customAccent"); applyPalette() } }

    // MARK: パネルの表示

    @Published var showSystem: Bool { didSet { store.set(showSystem, forKey: "showSystem") } }
    @Published var showNetwork: Bool { didSet { store.set(showNetwork, forKey: "showNetwork") } }
    @Published var showUsage: Bool { didSet { store.set(showUsage, forKey: "showUsage") } }
    @Published var showWeather: Bool { didSet { store.set(showWeather, forKey: "showWeather") } }
    @Published var showMarket: Bool { didSet { store.set(showMarket, forKey: "showMarket") } }
    @Published var showSand: Bool { didSet { store.set(showSand, forKey: "showSand") } }

    // MARK: 負荷

    @Published var grainCount: Double { didSet { store.set(Int(grainCount), forKey: "grainCount") } }
    @Published var activeFPS: Double { didSet { store.set(activeFPS, forKey: "activeFPS") } }
    @Published var idleFPS: Double { didSet { store.set(idleFPS, forKey: "idleFPS") } }

    /// 天気・株価の再取得が必要な変更があったことを知らせる印
    @Published private(set) var dataStamp = UUID()

    /// テキスト入力のたびにAPIを叩かないよう、少し待ってから再取得する
    var dataRefresh: AnyPublisher<UUID, Never> {
        $dataStamp
            .dropFirst()
            .debounce(for: .seconds(1.2), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }

    /// テーマやFPSなど、描画ツリーを作り直して反映する設定の指紋
    var rebuildFingerprint: String {
        "\(theme.rawValue)|\(customAccentHex)|\(activeFPS)|\(idleFPS)"
    }

    var customAccent: Color {
        get { Color(hexString: customAccentHex) ?? Color(red: 0.36, green: 0.86, blue: 1.0) }
        set { customAccentHex = newValue.hexString }
    }

    private init() {
        cityName = store.string(forKey: "cityName") ?? ""
        latitude = store.object(forKey: "latitude") as? Double ?? 35.6812
        longitude = store.object(forKey: "longitude") as? Double ?? 139.7671
        tickersText = store.string(forKey: "tickers") ?? ""
        wakePhrasesText = store.string(forKey: "wakePhrases") ?? ""
        theme = HUDTheme(rawValue: store.string(forKey: "theme") ?? "") ?? .arc
        customAccentHex = store.string(forKey: "customAccent") ?? "#5CDBFF"
        showSystem = store.object(forKey: "showSystem") as? Bool ?? true
        showNetwork = store.object(forKey: "showNetwork") as? Bool ?? true
        showUsage = store.object(forKey: "showUsage") as? Bool ?? true
        showWeather = store.object(forKey: "showWeather") as? Bool ?? true
        showMarket = store.object(forKey: "showMarket") as? Bool ?? true
        showSand = store.object(forKey: "showSand") as? Bool ?? true
        grainCount = Double(store.object(forKey: "grainCount") as? Int ?? 1100)
        activeFPS = store.object(forKey: "activeFPS") as? Double ?? 30
        idleFPS = store.object(forKey: "idleFPS") as? Double ?? 12
        applyPalette()
    }

    func applyPalette() {
        HUD.palette = theme.palette(customAccent: customAccent)
    }

    func resetAll() {
        cityName = ""
        latitude = 35.6812
        longitude = 139.7671
        tickersText = ""
        wakePhrasesText = ""
        theme = .arc
        customAccentHex = "#5CDBFF"
        showSystem = true
        showNetwork = true
        showUsage = true
        showWeather = true
        showMarket = true
        showSand = true
        grainCount = 1100
        activeFPS = 30
        idleFPS = 12
    }

    private func bumpData() {
        dataStamp = UUID()
    }
}
