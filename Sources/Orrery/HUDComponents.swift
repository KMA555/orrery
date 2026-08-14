import SwiftUI

// MARK: - 配色と書体

enum HUD {
    /// 現在のテーマ。HUDSettingsが起動時と変更時に差し替える。
    /// メインスレッドからのみ触る。
    static var palette = HUDTheme.arc.palette(customAccent: .white)

    // 役割名は初代テーマの色名のまま（呼び出し側を変えないため）。
    // 実際の色はテーマで変わる。
    static var cyan: Color { palette.accent }
    static var violet: Color { palette.secondary }
    static var magenta: Color { palette.tertiary }

    // 上げ下げと警告は意味を持つ色なので、テーマに関わらず固定
    static let up = Color(red: 0.36, green: 1.0, blue: 0.68)
    static let down = Color(red: 1.0, green: 0.40, blue: 0.52)
    static let warn = Color(red: 1.0, green: 0.74, blue: 0.30)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - 枠まわり

/// 角を斜めに落とした、HUDらしい枠。
struct CutCorner: Shape {
    var cut: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

struct HUDPanel<Content: View>: View {
    let title: String
    var trailing: String?
    var glow: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Rectangle().fill(HUD.cyan).frame(width: 3, height: 11)
                Text(title)
                    .font(HUD.mono(10, .bold))
                    .tracking(2.4)
                    .foregroundStyle(HUD.cyan)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(HUD.mono(9))
                        .foregroundStyle(HUD.cyan.opacity(0.45))
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCorner().fill(Color.white.opacity(0.025)))
        .overlay(CutCorner().stroke(HUD.cyan.opacity(0.20 + 0.25 * glow), lineWidth: 1))
    }
}

/// 背景の格子とにじみ。音が出ている間だけ色が乗る。
struct HUDBackdrop: View {
    var activation: CGFloat = 0

    var body: some View {
        ZStack {
            HUD.palette.background
            Canvas { context, size in
                let spacing: CGFloat = 48
                var grid = Path()
                var x: CGFloat = 0
                while x < size.width {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y < size.height {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                context.stroke(grid, with: .color(HUD.cyan.opacity(0.035)), lineWidth: 0.5)
            }
            RadialGradient(colors: [HUD.cyan.opacity(0.10 + 0.16 * activation), .clear],
                           center: .center, startRadius: 40, endRadius: 900)
            RadialGradient(colors: [HUD.magenta.opacity(0.10 * activation), .clear],
                           center: .bottom, startRadius: 20, endRadius: 700)
        }
    }
}

struct HUDPill: View {
    let icon: String
    let title: String
    var tint: Color = HUD.cyan
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(HUD.mono(10, .bold)).tracking(1.2)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.08)))
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 計器

struct ArcGauge: View {
    let value: Double
    let label: String
    var detail: String?
    var tint: Color = HUD.cyan
    var size: CGFloat = 74

    var body: some View {
        ZStack {
            Group {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(tint.opacity(0.14), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle()
                    .trim(from: 0, to: 0.75 * min(1, max(0, value)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .shadow(color: tint.opacity(0.7), radius: 6)
            }
            .rotationEffect(.degrees(135))
            VStack(spacing: 0) {
                Text("\(Int((value * 100).rounded()))")
                    .font(HUD.mono(size * 0.26, .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(HUD.mono(size * 0.12, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(tint.opacity(0.75))
                if let detail {
                    Text(detail)
                        .font(HUD.mono(size * 0.11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct BarMeter: View {
    let value: Double
    var tint: Color = HUD.cyan
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

struct Sparkline: View {
    let points: [Double]
    var tint: Color = HUD.cyan
    var filled = true

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let highest = points.max() ?? 1
            let lowest = points.min() ?? 0
            let span = max(highest - lowest, 0.000_1)

            var line = Path()
            for (index, value) in points.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let y = size.height * (1 - CGFloat((value - lowest) / span)) * 0.9 + size.height * 0.05
                if index == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }

            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.30), tint.opacity(0.01)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
    }
}

/// 見出しと値を1行で並べる。
struct HUDRow: View {
    let label: String
    let value: String
    var tint: Color = .white
    var size: CGFloat = 11

    var body: some View {
        HStack {
            Text(label)
                .font(HUD.mono(size, .medium))
                .foregroundStyle(HUD.cyan.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(HUD.mono(size, .semibold))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - 表示の整形

enum Format {
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = value
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return String(format: index >= 3 ? "%.1f %@" : "%.0f %@", amount, units[index])
    }

    static func speed(_ value: Double) -> String {
        bytes(value) + "/s"
    }

    static func price(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = value >= 1000 ? 0 : 2
        formatter.maximumFractionDigits = value >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }

    /// 1.4B のように短く書く
    static func compact(_ value: Double) -> String {
        let units: [(Double, String)] = [(1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")]
        for (scale, suffix) in units where value >= scale {
            return String(format: "%.1f%@", value / scale, suffix)
        }
        return String(format: "%.0f", value)
    }

    static func signedPercent(_ value: Double) -> String {
        String(format: "%@%.2f%%", value >= 0 ? "+" : "", value * 100)
    }

    static func duration(_ value: TimeInterval) -> String {
        let total = Int(value)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        return days > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(hours)h \(minutes)m"
    }
}
