import Foundation
import SwiftUI

struct Quote: Identifiable, Equatable {
    let symbol: String
    let label: String
    let price: Double
    let previousClose: Double
    let currency: String
    let points: [Double]

    var id: String { symbol }
    var change: Double { price - previousClose }
    var ratio: Double { previousClose > 0 ? change / previousClose : 0 }
    var isUp: Bool { change >= 0 }
}

/// Yahoo Financeのチャートエンドポイントから株価・指数・為替を取る（APIキー不要）。
@MainActor
final class MarketService: ObservableObject {
    @Published private(set) var quotes: [Quote] = []
    @Published private(set) var updated: Date?
    @Published private(set) var failed = false

    private var ticker: Timer?

    func start() {
        guard ticker == nil else { return }
        Task { await refresh() }
        let timer = Timer(timeInterval: HUDConfig.marketInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func refresh() async {
        let tickers = HUDConfig.tickers
        let fetched = await withTaskGroup(of: (Int, Quote?).self) { group in
            for (index, ticker) in tickers.enumerated() {
                group.addTask { (index, await Self.quote(for: ticker)) }
            }
            var result = [Quote?](repeating: nil, count: tickers.count)
            for await (index, quote) in group { result[index] = quote }
            return result
        }

        let resolved = fetched.compactMap { $0 }
        if resolved.isEmpty {
            failed = quotes.isEmpty
        } else {
            // 取れなかった銘柄は前回の値を残す
            quotes = tickers.compactMap { ticker in
                resolved.first { $0.symbol == ticker.symbol } ?? quotes.first { $0.symbol == ticker.symbol }
            }
            updated = Date()
            failed = false
        }
    }

    private static func quote(for ticker: Ticker) async -> Quote? {
        let encoded = ticker.symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ticker.symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=15m") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ChartResponse.self, from: data)
            guard let result = response.chart.result?.first,
                  let price = result.meta.regularMarketPrice else { return nil }
            let previous = result.meta.chartPreviousClose ?? result.meta.previousClose ?? price
            let points = result.indicators?.quote?.first?.close?.compactMap { $0 } ?? []
            return Quote(symbol: ticker.symbol,
                         label: ticker.label,
                         price: price,
                         previousClose: previous,
                         currency: result.meta.currency ?? "",
                         points: points)
        } catch {
            return nil
        }
    }

    private struct ChartResponse: Decodable {
        struct Chart: Decodable { let result: [Result]? }
        struct Result: Decodable {
            struct Meta: Decodable {
                let currency: String?
                let regularMarketPrice: Double?
                let chartPreviousClose: Double?
                let previousClose: Double?
            }
            struct Indicators: Decodable {
                struct Quote: Decodable { let close: [Double?]? }
                let quote: [Quote]?
            }
            let meta: Meta
            let indicators: Indicators?
        }
        let chart: Chart
    }
}
