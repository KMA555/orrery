import Foundation
import SwiftUI

struct UsageTotals: Equatable {
    var cost: Double = 0
    var tokens: Double = 0
}

struct UsageDay: Identifiable, Equatable {
    let date: Date
    let cost: Double
    let tokens: Double
    var id: Date { date }
}

struct UsageReport: Equatable {
    var today = UsageTotals()
    var month = UsageTotals()
    var days: [UsageDay] = []
    var topModel: String?
    var available = false
}

/// ~/.claude/projects のログから、トークン量と概算コストを集計する。
/// 会話の本文は読まず、usage・timestamp・model・requestId だけを見る。
@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var report = UsageReport()
    @Published private(set) var scanning = false

    private var ticker: Timer?

    func start() {
        guard ticker == nil else { return }
        Task { await refresh() }
        let timer = Timer(timeInterval: HUDConfig.usageInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        report = await Task.detached(priority: .utility) { UsageScanner.shared.scan() }.value
        scanning = false
    }
}

final class UsageScanner: @unchecked Sendable {
    static let shared = UsageScanner()

    /// APIの1リクエスト分。同じ内容が複数のファイルに現れるのでkeyで重複を落とす。
    private struct Record {
        let key: String
        let day: Date
        let model: String
        let input: Double
        let output: Double
        let write: Double
        let read: Double
    }

    private struct Entry {
        let modified: Date
        let records: [Record]
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]

    /// 100万トークンあたりのドル。fableは公開単価が確認できないため推定値。
    private static func rate(for model: String) -> (input: Double, output: Double, write: Double, read: Double) {
        let name = model.lowercased()
        if name.contains("opus") { return (15, 75, 18.75, 1.50) }
        if name.contains("fable") { return (6, 30, 7.50, 0.60) }
        if name.contains("haiku") { return (1, 5, 1.25, 0.10) }
        return (3, 15, 3.75, 0.30)
    }

    func scan() -> UsageReport {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path),
              let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return UsageReport()
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -29, to: today) else { return UsageReport() }

        var totals: [Date: UsageTotals] = [:]
        var models: [String: Double] = [:]
        // セッションを再開すると過去のやり取りが新しいファイルに丸ごと写るので、
        // ファイルをまたいで同じリクエストを二重に数えないようにする
        var seen = Set<String>()

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified >= cutoff else { continue }

            let entry = cached(url, modified: modified) ?? parse(url, modified: modified)
            for record in entry.records where record.day >= cutoff {
                guard seen.insert(record.key).inserted else { continue }
                let rate = Self.rate(for: record.model)
                var dollars: Double = record.input * rate.input
                dollars += record.output * rate.output
                dollars += record.write * rate.write
                dollars += record.read * rate.read
                let tokens: Double = record.input + record.output + record.write + record.read

                totals[record.day, default: UsageTotals()].cost += dollars / 1_000_000
                totals[record.day, default: UsageTotals()].tokens += tokens
                models[record.model, default: 0] += tokens
            }
        }

        var report = UsageReport()
        report.available = true
        report.today = totals[today] ?? UsageTotals()
        for value in totals.values {
            report.month.cost += value.cost
            report.month.tokens += value.tokens
        }
        report.topModel = models.max { $0.value < $1.value }?.key
        report.days = (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let value = totals[date] ?? UsageTotals()
            return UsageDay(date: date, cost: value.cost, tokens: value.tokens)
        }
        return report
    }

    private func cached(_ url: URL, modified: Date) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[url.path], entry.modified == modified else { return nil }
        return entry
    }

    private func parse(_ url: URL, modified: Date) -> Entry {
        var records: [Record] = []
        let calendar = Calendar.current
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            text.enumerateLines { line, _ in
                // 使用量の記録された行だけを開く
                guard line.contains("\"usage\"") else { return }
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let stamp = object["timestamp"] as? String,
                      let date = fractional.date(from: stamp) ?? plain.date(from: stamp) else { return }

                let input = Self.number(usage["input_tokens"])
                let output = Self.number(usage["output_tokens"])
                let write = Self.number(usage["cache_creation_input_tokens"])
                let read = Self.number(usage["cache_read_input_tokens"])
                guard input + output + write + read > 0 else { return }

                let key = (object["requestId"] as? String)
                    ?? (message["id"] as? String)
                    ?? (object["uuid"] as? String)
                    ?? stamp
                records.append(Record(key: key,
                                      day: calendar.startOfDay(for: date),
                                      model: (message["model"] as? String) ?? "unknown",
                                      input: input, output: output, write: write, read: read))
            }
        }

        let entry = Entry(modified: modified, records: records)
        lock.lock()
        cache[url.path] = entry
        lock.unlock()
        return entry
    }

    private static func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }
}
