import SwiftUI

// MARK: - システム

struct SystemPanel: View {
    @ObservedObject var system: SystemMonitor

    private var memoryRatio: Double { system.memoryTotal > 0 ? system.memoryUsed / system.memoryTotal : 0 }
    private var diskRatio: Double { system.diskTotal > 0 ? system.diskUsed / system.diskTotal : 0 }

    var body: some View {
        HUDPanel(title: "SYSTEM", trailing: "\(system.processorCount) CORES") {
            HStack(spacing: 10) {
                ArcGauge(value: system.cpu, label: "CPU", tint: HUD.cyan, size: 72)
                ArcGauge(value: memoryRatio, label: "MEM", tint: HUD.violet, size: 72)
                ArcGauge(value: diskRatio, label: "SSD", tint: HUD.magenta, size: 72)
            }
            .frame(maxWidth: .infinity)

            Sparkline(points: system.cpuHistory, tint: HUD.cyan)
                .frame(height: 34)

            VStack(spacing: 5) {
                HUDRow(label: "MEMORY",
                       value: "\(Format.bytes(system.memoryUsed)) / \(Format.bytes(system.memoryTotal))")
                HUDRow(label: "STORAGE",
                       value: "\(Format.bytes(system.diskUsed)) / \(Format.bytes(system.diskTotal))")
                HUDRow(label: "POWER", value: powerText, tint: powerTint)
                HUDRow(label: "UPTIME", value: Format.duration(system.uptime))
            }
        }
    }

    private var powerText: String {
        guard let level = system.batteryLevel else { return "AC POWER" }
        return "\(Int(level * 100))%" + (system.isCharging ? " ⚡︎" : "")
    }

    private var powerTint: Color {
        guard let level = system.batteryLevel else { return .white }
        if system.isCharging { return HUD.up }
        return level < 0.2 ? HUD.down : .white
    }
}

// MARK: - ネットワーク

struct NetworkPanel: View {
    @ObservedObject var system: SystemMonitor

    var body: some View {
        HUDPanel(title: "NETWORK", trailing: system.ipAddress) {
            HStack(spacing: 12) {
                trafficColumn(title: "DOWN", value: system.download,
                              history: system.downloadHistory, tint: HUD.cyan)
                trafficColumn(title: "UP", value: system.upload,
                              history: system.uploadHistory, tint: HUD.up)
            }
            HUDRow(label: "HOST", value: system.hostName)
        }
    }

    private func trafficColumn(title: String, value: Double, history: [Double], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(HUD.mono(9, .bold))
                .tracking(1.6)
                .foregroundStyle(tint.opacity(0.7))
            Text(Format.speed(value))
                .font(HUD.mono(15, .bold))
                .foregroundStyle(.white)
            Sparkline(points: history, tint: tint)
                .frame(height: 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 天気

struct WeatherPanel: View {
    @ObservedObject var weather: WeatherService

    var body: some View {
        HUDPanel(title: "WEATHER", trailing: HUDConfig.cityName) {
            if let snapshot = weather.snapshot {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1f°", snapshot.temperature))
                            .font(HUD.mono(42, .bold))
                            .foregroundStyle(.white)
                        Text(WeatherCode.text(snapshot.code))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HUD.cyan)
                    }
                    Spacer()
                    Image(systemName: WeatherCode.symbol(snapshot.code))
                        .font(.system(size: 40))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(HUD.cyan)
                        .shadow(color: HUD.cyan.opacity(0.5), radius: 12)
                }

                VStack(spacing: 5) {
                    HUDRow(label: "体感", value: String(format: "%.1f°", snapshot.apparent))
                    HUDRow(label: "湿度", value: "\(snapshot.humidity)%")
                    HUDRow(label: "風速", value: String(format: "%.1f km/h", snapshot.wind))
                    HUDRow(label: "日の出 / 日の入", value: "\(snapshot.sunrise) / \(snapshot.sunset)")
                }

                Rectangle().fill(HUD.cyan.opacity(0.15)).frame(height: 1)

                HStack(spacing: 0) {
                    ForEach(snapshot.days.prefix(4)) { day in
                        VStack(spacing: 5) {
                            Text(Self.weekday.string(from: day.date).uppercased())
                                .font(HUD.mono(9, .bold))
                                .foregroundStyle(HUD.cyan.opacity(0.6))
                            Image(systemName: WeatherCode.symbol(day.code))
                                .font(.system(size: 17))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(HUD.cyan.opacity(0.9))
                            Text(String(format: "%.0f°", day.high))
                                .font(HUD.mono(11, .semibold))
                                .foregroundStyle(.white)
                            Text(String(format: "%.0f°", day.low))
                                .font(HUD.mono(10))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text(weather.failed ? "天気を取得できませんでした" : "取得中…")
                    .font(HUD.mono(11))
                    .foregroundStyle(HUD.cyan.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

// MARK: - マーケット

struct MarketPanel: View {
    @ObservedObject var market: MarketService

    var body: some View {
        HUDPanel(title: "MARKETS", trailing: updatedText) {
            if market.quotes.isEmpty {
                Text(market.failed ? "株価を取得できませんでした" : "取得中…")
                    .font(HUD.mono(11))
                    .foregroundStyle(HUD.cyan.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                VStack(spacing: 9) {
                    ForEach(market.quotes) { quote in
                        row(for: quote)
                    }
                }
            }
        }
    }

    private func row(for quote: Quote) -> some View {
        let tint = quote.isUp ? HUD.up : HUD.down
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.label)
                    .font(HUD.mono(10, .bold))
                    .foregroundStyle(.white)
                Text(quote.symbol)
                    .font(HUD.mono(8))
                    .foregroundStyle(HUD.cyan.opacity(0.4))
            }
            Spacer(minLength: 4)
            Sparkline(points: quote.points, tint: tint, filled: false)
                .frame(width: 62, height: 24)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.price(quote.price))
                    .font(HUD.mono(12, .semibold))
                    .foregroundStyle(.white)
                Text(Format.signedPercent(quote.ratio))
                    .font(HUD.mono(9, .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 74, alignment: .trailing)
        }
    }

    private var updatedText: String {
        guard let updated = market.updated else { return "—" }
        return Self.time.string(from: updated)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - Claudeの使用量

struct UsagePanel: View {
    @ObservedObject var usage: UsageService

    var body: some View {
        HUDPanel(title: "CLAUDE USAGE", trailing: usage.scanning ? "集計中…" : "概算") {
            if usage.report.available {
                HStack(alignment: .top, spacing: 12) {
                    metric(title: "今日", totals: usage.report.today, tint: HUD.cyan)
                    metric(title: "過去30日", totals: usage.report.month, tint: HUD.violet)
                }
                UsageBars(days: usage.report.days)
                    .frame(height: 42)
                HUDRow(label: "最多モデル", value: usage.report.topModel ?? "—", size: 10)
            } else {
                Text(usage.scanning ? "集計中…" : "ログが見つかりませんでした")
                    .font(HUD.mono(11))
                    .foregroundStyle(HUD.cyan.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 70)
            }
        }
    }

    private func metric(title: String, totals: UsageTotals, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(HUD.mono(9, .bold))
                .tracking(1.6)
                .foregroundStyle(tint.opacity(0.75))
            Text(Format.money(totals.cost))
                .font(HUD.mono(19, .bold))
                .foregroundStyle(.white)
            Text("\(Format.compact(totals.tokens)) tokens")
                .font(HUD.mono(9))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 直近2週間の日次コスト。いちばん右が今日。
private struct UsageBars: View {
    let days: [UsageDay]

    var body: some View {
        Canvas { context, size in
            guard !days.isEmpty else { return }
            let peak = max(days.map(\.cost).max() ?? 0, 0.000_1)
            let slot = size.width / CGFloat(days.count)
            let width = min(slot * 0.62, 14)

            for (index, day) in days.enumerated() {
                let height = max(1, size.height * CGFloat(day.cost / peak))
                let x = slot * (CGFloat(index) + 0.5) - width / 2
                let rect = CGRect(x: x, y: size.height - height, width: width, height: height)
                let isToday = index == days.count - 1
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(isToday ? HUD.cyan : HUD.cyan.opacity(0.35)))
            }
        }
    }
}
