import AppKit
import SwiftUI

/// HUD全体の配色一式。テーマ切替はこのパレットを差し替えることで行う。
/// 上げ下げ（up/down）と警告色は意味を持つ色なので、テーマに関わらず固定。
struct HUDPalette: Equatable {
    var accent: Color      // 主色。既定テーマではシアン
    var secondary: Color   // 副色。既定テーマではバイオレット
    var tertiary: Color    // 強調色。既定テーマではマゼンタ
    var bgR: Double
    var bgG: Double
    var bgB: Double
    /// 粒子の色相。baseから帯域に応じてspanぶんずれる（1.0を超えると一周して戻る）
    var grainHueBase: Double
    var grainHueSpan: Double
    var grainSaturation: Double

    var background: Color { Color(red: bgR, green: bgG, blue: bgB) }
    var backgroundNS: NSColor { NSColor(calibratedRed: bgR, green: bgG, blue: bgB, alpha: 1) }
}

enum HUDTheme: String, CaseIterable, Identifiable {
    case arc
    case ember
    case matrix
    case crimson
    case mono
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .arc: return "ARC（シアン）"
        case .ember: return "EMBER（オレンジ）"
        case .matrix: return "MATRIX（グリーン）"
        case .crimson: return "CRIMSON（レッド）"
        case .mono: return "MONO（モノクロ）"
        case .custom: return "カスタム"
        }
    }

    func palette(customAccent: Color) -> HUDPalette {
        switch self {
        case .arc:
            return HUDPalette(accent: Color(red: 0.36, green: 0.86, blue: 1.0),
                              secondary: Color(red: 0.62, green: 0.52, blue: 1.0),
                              tertiary: Color(red: 1.0, green: 0.36, blue: 0.78),
                              bgR: 0.015, bgG: 0.025, bgB: 0.04,
                              grainHueBase: 0.53, grainHueSpan: 0.36, grainSaturation: 1)
        case .ember:
            return HUDPalette(accent: Color(red: 1.0, green: 0.64, blue: 0.26),
                              secondary: Color(red: 1.0, green: 0.45, blue: 0.35),
                              tertiary: Color(red: 1.0, green: 0.85, blue: 0.35),
                              bgR: 0.035, bgG: 0.020, bgB: 0.010,
                              grainHueBase: 0.99, grainHueSpan: 0.13, grainSaturation: 1)
        case .matrix:
            return HUDPalette(accent: Color(red: 0.40, green: 1.0, blue: 0.60),
                              secondary: Color(red: 0.75, green: 1.0, blue: 0.45),
                              tertiary: Color(red: 0.25, green: 0.95, blue: 0.80),
                              bgR: 0.008, bgG: 0.030, bgB: 0.015,
                              grainHueBase: 0.28, grainHueSpan: 0.16, grainSaturation: 1)
        case .crimson:
            return HUDPalette(accent: Color(red: 1.0, green: 0.36, blue: 0.44),
                              secondary: Color(red: 1.0, green: 0.55, blue: 0.75),
                              tertiary: Color(red: 0.80, green: 0.40, blue: 1.0),
                              bgR: 0.040, bgG: 0.012, bgB: 0.020,
                              grainHueBase: 0.90, grainHueSpan: 0.14, grainSaturation: 1)
        case .mono:
            return HUDPalette(accent: Color(red: 0.92, green: 0.95, blue: 1.0),
                              secondary: Color(red: 0.75, green: 0.78, blue: 0.85),
                              tertiary: Color(red: 0.55, green: 0.58, blue: 0.65),
                              bgR: 0.02, bgG: 0.02, bgB: 0.025,
                              grainHueBase: 0.60, grainHueSpan: 0.05, grainSaturation: 0.08)
        case .custom:
            return Self.derived(from: customAccent)
        }
    }

    /// カスタムカラー1色から、色相をずらして残りの色を組み立てる
    private static func derived(from accent: Color) -> HUDPalette {
        let ns = NSColor(accent).usingColorSpace(.deviceRGB)
            ?? NSColor(calibratedRed: 0.36, green: 0.86, blue: 1.0, alpha: 1)
        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        ns.getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)

        func wrap(_ value: Double) -> Double {
            let r = value.truncatingRemainder(dividingBy: 1)
            return r < 0 ? r + 1 : r
        }
        func shifted(_ dh: Double, sat scale: Double) -> Color {
            Color(hue: wrap(Double(hue) + dh),
                  saturation: min(1, Double(sat) * scale),
                  brightness: min(1, Double(bri)))
        }

        let bg = NSColor(calibratedHue: hue, saturation: min(1, sat * 0.6),
                         brightness: 0.035, alpha: 1)
            .usingColorSpace(.deviceRGB) ?? .black

        return HUDPalette(accent: accent,
                          secondary: shifted(0.10, sat: 0.85),
                          tertiary: shifted(-0.13, sat: 1.0),
                          bgR: Double(bg.redComponent),
                          bgG: Double(bg.greenComponent),
                          bgB: Double(bg.blueComponent),
                          grainHueBase: wrap(Double(hue) - 0.08),
                          grainHueSpan: 0.22,
                          grainSaturation: Double(sat))
    }
}

// MARK: - 色 ↔ 16進文字列

extension Color {
    init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}
