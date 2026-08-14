import SwiftUI

/// 中央のリング一式。太いリングを密に重ね、内側に砂の粒子を閉じ込める。
struct OrreryDial: View {
    let snapshot: SpectrumSnapshot
    let cpu: Double
    let memory: Double

    private var grainCount: Int { HUDConfig.grainCount }
    private let bucketCount = 14

    /// 半径はすべて min(幅, 高さ) に対する比率。外側から内側へ。
    private enum R {
        static let gauges: CGFloat = 0.500
        static let outerBand: CGFloat = 0.462
        static let comb: CGFloat = 0.430
        static let index: CGFloat = 0.398
        static let accent: CGFloat = 0.372
        static let heavy: CGFloat = 0.344
        static let bright: CGFloat = 0.316
        static let hairline: CGFloat = 0.292
        static let grainOuter: CGFloat = 0.268
        static let grainInner: CGFloat = 0.172
    }

    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.20)

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let unit = min(size.width, size.height)
            guard unit > 0, snapshot.bands.count > 1 else { return }

            corners(context, size: size)
            sweep(context, center: center, unit: unit)
            rings(context, center: center, unit: unit)
            grains(context, center: center, unit: unit)
            // 中央の文字を読みやすくするため、真ん中だけ暗く落とす
            let hole = unit * 0.255
            let holeRect = CGRect(x: center.x - hole, y: center.y - hole,
                                  width: hole * 2, height: hole * 2)
            context.fill(Path(ellipseIn: holeRect),
                         with: .radialGradient(
                            Gradient(stops: [.init(color: .black.opacity(0.80), location: 0),
                                             .init(color: .black.opacity(0.62), location: 0.62),
                                             .init(color: .clear, location: 1)]),
                            center: center, startRadius: 0, endRadius: hole))
            gauges(context, center: center, unit: unit)
        }
    }

    // MARK: - リング一式

    private func rings(_ context: GraphicsContext, center: CGPoint, unit: CGFloat, glowPass: Bool = false) {
        let activation = snapshot.activation
        let time = snapshot.time
        let level = snapshot.level
        // 発光用の重ね描きは、太くして薄くする
        let spread: CGFloat = glowPass ? 3.2 : 1
        let glow = (0.82 + 0.18 * activation) * (glowPass ? 0.13 : 1)

        // いちばん外の太い破断リング
        band(context, center: center, radius: unit * R.outerBand, width: 7 * spread,
             color: HUD.cyan.opacity(0.52 * glow),
             segments: [(150 + time * 3, 158), (330 + time * 3, 148)])

        // 内向きの櫛
        comb(context, center: center, radius: unit * R.comb, count: 108,
             length: -unit * 0.030, width: 2 * spread, rotation: -time * 1.6,
             color: HUD.cyan.opacity(0.60 * glow), gap: (118, 44))

        // 目盛りリング
        band(context, center: center, radius: unit * R.index, width: 1 * spread,
             color: HUD.cyan.opacity(0.42 * glow), segments: [(0, 360)])
        comb(context, center: center, radius: unit * R.index, count: 48,
             length: unit * 0.014, width: 1.5 * spread, rotation: time * 2.4,
             color: HUD.cyan.opacity(0.40 * glow), gap: nil)

        // 琥珀色のアクセント
        band(context, center: center, radius: unit * R.accent, width: 3.5 * spread,
             color: Self.amber.opacity(0.75 * glow),
             segments: [(196 - time * 4, 62)])
        comb(context, center: center, radius: unit * R.accent, count: 40,
             length: -unit * 0.012, width: 1.5 * spread, rotation: -time * 4,
             color: Self.amber.opacity(0.55 * glow), gap: (62, 300))

        // ぶ厚い中間リング
        band(context, center: center, radius: unit * R.heavy, width: 11 * spread,
             color: HUD.cyan.opacity(0.40 * glow),
             segments: [(24 + time * 2, 128), (176 + time * 2, 160)])

        // いちばん明るい内側のリング。音に合わせて光る。
        band(context, center: center, radius: unit * R.bright, width: 15 * spread,
             color: HUD.cyan.opacity(min(1, (0.80 + 0.20 * level) * glow)),
             segments: [(-72 + time * 1.2, 130), (76 + time * 1.2, 122), (212 + time * 1.2, 66)])

        band(context, center: center, radius: unit * R.hairline, width: 1 * spread,
             color: HUD.cyan.opacity(0.48 * glow), segments: [(0, 360)])

        // 上部の小さな印
        comb(context, center: center, radius: unit * R.bright, count: 60,
             length: unit * 0.010, width: 2.5 * spread, rotation: time * 0.8,
             color: Self.amber.opacity(0.8 * glow), gap: (274, 348))
    }

    /// 画面四隅のL字ブラケット
    private func corners(_ context: GraphicsContext, size: CGSize) {
        let arm: CGFloat = 26
        let inset: CGFloat = 6
        var path = Path()
        let points = [
            (CGPoint(x: inset, y: inset), CGFloat(1), CGFloat(1)),
            (CGPoint(x: size.width - inset, y: inset), CGFloat(-1), CGFloat(1)),
            (CGPoint(x: inset, y: size.height - inset), CGFloat(1), CGFloat(-1)),
            (CGPoint(x: size.width - inset, y: size.height - inset), CGFloat(-1), CGFloat(-1))
        ]
        for (origin, dx, dy) in points {
            path.move(to: CGPoint(x: origin.x + arm * dx, y: origin.y))
            path.addLine(to: origin)
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + arm * dy))
        }
        context.stroke(path,
                       with: .color(HUD.cyan.opacity(0.20 + 0.25 * snapshot.activation)),
                       lineWidth: 1.5)
    }

    /// リングの帯をゆっくり撫でる走査線
    private func sweep(_ context: GraphicsContext, center: CGPoint, unit: CGFloat) {
        let activation = snapshot.activation
        let head = snapshot.time * 0.7
        let inner = unit * R.hairline
        let outer = unit * R.comb

        for step in 0..<40 {
            let angle = head - CGFloat(step) * 0.026
            let fade = 1 - CGFloat(step) / 18
            var path = Path()
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.stroke(path,
                           with: .color(HUD.cyan.opacity(Double(fade * (0.05 + 0.10 * activation)))),
                           lineWidth: 2)
        }
    }

    // MARK: - ゲージ

    private func gauges(_ context: GraphicsContext, center: CGPoint, unit: CGFloat) {
        let radius = unit * R.gauges
        segmented(context, center: center, radius: radius, from: 132, sweep: 96,
                  value: cpu, color: HUD.cyan)
        segmented(context, center: center, radius: radius, from: 48, sweep: -96,
                  value: memory, color: HUD.violet)

        context.draw(Text("CPU \(Int(cpu * 100))%")
            .font(HUD.mono(11, .bold))
            .foregroundColor(HUD.cyan.opacity(0.85)),
            at: CGPoint(x: center.x - radius - 14, y: center.y), anchor: .trailing)
        context.draw(Text("MEM \(Int(memory * 100))%")
            .font(HUD.mono(11, .bold))
            .foregroundColor(HUD.violet.opacity(0.9)),
            at: CGPoint(x: center.x + radius + 14, y: center.y), anchor: .leading)
    }

    private func segmented(_ context: GraphicsContext, center: CGPoint, radius: CGFloat,
                           from degrees: CGFloat, sweep: CGFloat, value: Double, color: Color) {
        let segments = 28
        var lit = Path()
        var dark = Path()
        for index in 0..<segments {
            let fraction = CGFloat(index) / CGFloat(segments - 1)
            let angle = (degrees + sweep * fraction) * .pi / 180
            let isLit = Double(fraction) <= value
            let length: CGFloat = isLit ? -16 : -8
            let start = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let end = CGPoint(x: center.x + cos(angle) * (radius + length),
                              y: center.y + sin(angle) * (radius + length))
            if isLit {
                lit.move(to: start); lit.addLine(to: end)
            } else {
                dark.move(to: start); dark.addLine(to: end)
            }
        }
        context.stroke(dark, with: .color(color.opacity(0.16)), lineWidth: 2.5)
        context.stroke(lit, with: .color(color.opacity(0.9)), lineWidth: 2.5)
    }

    // MARK: - 砂

    private func grains(_ context: GraphicsContext, center: CGPoint, unit: CGFloat) {
        let bands = snapshot.bands
        let activation = snapshot.activation
        let time = snapshot.time
        let inner = unit * R.grainInner
        let outer = unit * (R.grainOuter + 0.020 * activation)
        let spanSquared = outer * outer - inner * inner

        var grains = [Path](repeating: Path(), count: bucketCount)

        for index in 0..<grainCount {
            let seed = CGFloat(index)
            let u = frac(seed * seedA)
            let v = frac(seed * seedB)

            let scatter = sin(v * 43.7 + u * 17.3)
            let angle = u * 2 * .pi
                + scatter * 0.45
                + time * (0.05 + 0.17 * (1 - v)) * (0.55 + 1.10 * activation)

            let phase = frac((angle + .pi / 2) / (2 * .pi))
            let folded = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let band = min(bands.count - 1, Int(folded * CGFloat(bands.count)))
            let value = bands[band]

            let wobble = sin(angle * 3 + time * 0.9 + v * 6.283) * 0.6
                       + cos(angle * 6 - time * 0.55 + v * 12.566) * 0.4
            let drift = cos(u * 31.1 + v * 12.9 + time * 0.42)

            let radius = sqrt(inner * inner + v * spanSquared)
                + wobble * unit * (0.010 + 0.020 * activation)
                + drift * unit * 0.012
                + value * unit * (0.012 + 0.055 * activation) * (0.35 + 0.65 * v)

            let point = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius)
            let dot = 1.25 + 1.7 * value * activation + 0.5 * u
            let bucket = min(bucketCount - 1, Int(folded * CGFloat(bucketCount)))

            grains[bucket].addRect(CGRect(x: point.x - dot / 2, y: point.y - dot / 2,
                                          width: dot, height: dot))
        }

        let values = GrainPalette.bucketValues(bands, buckets: bucketCount)
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for bucket in 0..<bucketCount {
                let ratio = CGFloat(bucket) / CGFloat(bucketCount - 1)
                layer.fill(grains[bucket],
                           with: .color(GrainPalette.color(ratio: ratio,
                                                           activation: activation,
                                                           value: values[bucket])))
            }
        }
    }

    // MARK: - 補助

    /// 弧をいくつかに切って描く。segmentsは(開始角, 掃引角)の並び。
    private func band(_ context: GraphicsContext, center: CGPoint, radius: CGFloat,
                      width: CGFloat, color: Color, segments: [(CGFloat, CGFloat)]) {
        for (start, sweep) in segments {
            var path = Path()
            path.addArc(center: center, radius: radius,
                        startAngle: .degrees(start), endAngle: .degrees(start + sweep),
                        clockwise: false)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
        }
    }

    /// 放射状の目盛り。lengthを負にすると内側へ伸びる。gapは(開始角, 幅)で抜く。
    private func comb(_ context: GraphicsContext, center: CGPoint, radius: CGFloat,
                      count: Int, length: CGFloat, width: CGFloat, rotation: CGFloat,
                      color: Color, gap: (CGFloat, CGFloat)?) {
        var path = Path()
        for index in 0..<count {
            let degrees = rotation + CGFloat(index) / CGFloat(count) * 360
            if let gap {
                var offset = (degrees - gap.0).truncatingRemainder(dividingBy: 360)
                if offset < 0 { offset += 360 }
                if offset < gap.1 { continue }
            }
            let angle = degrees * .pi / 180
            path.move(to: CGPoint(x: center.x + cos(angle) * radius,
                                  y: center.y + sin(angle) * radius))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * (radius + length),
                                     y: center.y + sin(angle) * (radius + length)))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }
}
