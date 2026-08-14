import SwiftUI

@inline(__always)
func frac(_ value: CGFloat) -> CGFloat { value - floor(value) }

/// 粒子を等間隔に散らすための無理数（低ディスクレパンシー列）
let seedA: CGFloat = 0.754_877_666_2
let seedB: CGFloat = 0.569_840_290_9

enum GrainPalette {
    /// 待機中は彩度が抜けて砂色、音が出ると低音→高音でテーマの色相に色づく
    static func color(ratio: CGFloat, activation: CGFloat, value: CGFloat) -> Color {
        let palette = HUD.palette
        let hue = (palette.grainHueBase + palette.grainHueSpan * Double(ratio))
            .truncatingRemainder(dividingBy: 1)
        return Color(hue: hue < 0 ? hue + 1 : hue,
              saturation: Double(0.18 + 0.72 * activation) * palette.grainSaturation,
              brightness: Double(min(1, 0.64 + 0.20 * value + 0.16 * activation)),
              opacity: Double(min(1, 0.44 + 0.28 * activation + 0.28 * value)))
    }

    /// バンドをいくつかの色の束にまとめて、描画回数を減らす
    static func bucketValues(_ bands: [CGFloat], buckets: Int) -> [CGFloat] {
        var sums = [CGFloat](repeating: 0, count: buckets)
        var counts = [CGFloat](repeating: 0, count: buckets)
        for (index, value) in bands.enumerated() {
            let ratio = CGFloat(index) / CGFloat(max(1, bands.count - 1))
            let bucket = min(buckets - 1, Int(ratio * CGFloat(buckets)))
            sums[bucket] += value
            counts[bucket] += 1
        }
        return zip(sums, counts).map { $1 > 0 ? $0 / $1 : 0 }
    }
}

// MARK: - 画面下を流れる砂

struct SandStream: View {
    @EnvironmentObject private var audio: AudioSpectrum

    private var grainCount: Int { Int(Double(HUDConfig.grainCount) * 0.7) }
    @State private var started = Date()
    private let bucketCount = 12

    var body: some View {
        ZStack(alignment: .leading) {
            HostedAnimation {
                StreamTimeline(audio: audio, started: started, grainCount: grainCount, bucketCount: bucketCount)
            }
            StreamLabels(level: 0, isLive: audio.isLive)
        }
    }

    fileprivate static func canvas(snapshot: SpectrumSnapshot, grainCount: Int, bucketCount: Int) -> some View {
        Canvas { context, size in
                let bands = snapshot.bands
                guard bands.count > 1, size.width > 0 else { return }
                let activation = snapshot.activation
                let time = snapshot.time
                let middle = size.height / 2

                var grains = [Path](repeating: Path(), count: bucketCount)

                for index in 0..<grainCount {
                    let seed = CGFloat(index)
                    let u = frac(seed * seedA)
                    let v = frac(seed * seedB)

                    // 右へゆっくり流れ続ける
                    let speed = 0.008 + 0.020 * v + 0.030 * activation
                    let x = frac(u + time * speed) * size.width

                    // 中央が低音、両端が高音
                    let position = x / size.width
                    let folded = position < 0.5 ? 1 - position * 2 : (position - 0.5) * 2
                    let band = min(bands.count - 1, Int(folded * CGFloat(bands.count)))
                    let value = bands[band]

                    let spread = size.height * (0.150 + 0.330 * value * (0.15 + 0.85 * activation))
                    let wobble = sin(x * 0.017 + time * 1.15 + v * 6.283) * 0.55
                               + cos(x * 0.033 - time * 0.70 + u * 6.283) * 0.45
                    let y = middle + (v * 2 - 1) * spread + wobble * size.height * 0.11

                    let dot = 1.20 + 1.5 * value * activation + 0.4 * u
                    let bucket = min(bucketCount - 1, Int(folded * CGFloat(bucketCount)))
                    grains[bucket].addRect(CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
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

    }
}

private struct StreamLabels: View {
    let level: Int
    let isLive: Bool

    var body: some View {
        HStack {
            Text("CODEX AUDIO FLOW")
            Spacer()
            Text(String(format: "LEVEL %03d", level))
        }
        .font(HUD.mono(10, .bold))
        .tracking(2.4)
        .foregroundStyle(HUD.cyan.opacity(isLive ? 0.75 : 0.35))
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }
}

/// 下部の帯の更新だけを回す。
private struct StreamTimeline: View {
    let audio: AudioSpectrum
    let started: Date
    let grainCount: Int
    let bucketCount: Int

    var body: some View {
        if HUDConfig.isStatic {
            SandStream.canvas(snapshot: audio.current, grainCount: grainCount, bucketCount: bucketCount)
        } else {
            TimelineView(.periodic(from: started,
                                   by: HUDConfig.frameInterval(isLive: audio.isLive))) { _ in
                SandStream.canvas(snapshot: audio.current, grainCount: grainCount, bucketCount: bucketCount)
            }
        }
    }
}
