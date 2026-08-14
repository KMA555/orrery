import Accelerate

/// 音声フレームをFFTにかけて、対数間隔のバンド（低音→高音）に変換する。
/// オーディオ用のシリアルキューからのみ触ること。
final class SpectrumAnalyzer {
    struct Frame {
        let bands: [Float]
        let level: Float
    }

    private let size: Int
    private let half: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private let bins: [(lower: Int, upper: Int)]
    private let gains: [Float]
    /// 何サンプルごとに1フレーム出すか（size未満にすると窓を重ねられる）
    private let hop: Int
    private var ring: [Float]
    private var sinceLastFrame = 0

    init(size: Int, hop: Int, bandCount: Int, sampleRate: Float) {
        self.size = size
        self.half = size / 2
        self.hop = min(hop, size)
        self.ring = [Float](repeating: 0, count: size)
        self.log2n = vDSP_Length(log2(Double(size)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("FFTの初期化に失敗しました")
        }
        self.setup = setup
        self.window = vDSP.window(ofType: Float.self,
                                  usingSequence: .hanningDenormalized,
                                  count: size,
                                  isHalfWindow: false)

        // 45Hz〜14kHzを対数等分してバンドに割り当てる
        let lowest: Float = 45
        let highest: Float = 14_000
        let hzPerBin = sampleRate / Float(size)
        var bins: [(lower: Int, upper: Int)] = []
        var gains: [Float] = []
        for index in 0..<bandCount {
            let low = lowest * pow(highest / lowest, Float(index) / Float(bandCount))
            let high = lowest * pow(highest / lowest, Float(index + 1) / Float(bandCount))
            let lower = max(1, min(half - 1, Int(low / hzPerBin)))
            let upper = max(lower + 1, min(half, Int(high / hzPerBin)))
            bins.append((lower, upper))
            // 高域はエネルギーが小さいので持ち上げて、見た目のバランスを取る
            gains.append(Tuning.tiltDecibels * log10(sqrt(low * high) / 200))
        }
        self.bins = bins
        self.gains = gains
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// サンプルを受け取り、hopぶんたまったら直近1フレームの解析結果を返す。
    func push(_ samples: [Float]) -> Frame? {
        guard !samples.isEmpty else { return nil }
        if samples.count >= size {
            ring = Array(samples.suffix(size))
        } else {
            ring.removeFirst(samples.count)
            ring.append(contentsOf: samples)
        }
        sinceLastFrame += samples.count
        guard sinceLastFrame >= hop else { return nil }
        sinceLastFrame = 0
        return analyze(ring)
    }

    private func analyze(_ frame: [Float]) -> Frame {
        var windowed = [Float](repeating: 0, count: size)
        vDSP.multiply(frame, window, result: &windowed)

        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { output in
                    vDSP_zvabs(&split, 1, output.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }

        let scale = 2 / Float(size)
        var bands = [Float](repeating: 0, count: bins.count)
        for (index, range) in bins.enumerated() {
            var peak: Float = 0
            for bin in range.lower..<range.upper {
                peak = max(peak, magnitudes[bin])
            }
            let decibels = 20 * log10(peak * scale + 1e-9) + gains[index]
            bands[index] = Self.normalized(decibels, floor: Tuning.bandFloorDecibels, ceiling: Tuning.bandCeilingDecibels)
        }

        let rms = vDSP.rootMeanSquare(frame)
        let level = Self.normalized(20 * log10(rms + 1e-9),
                                    floor: Tuning.levelFloorDecibels,
                                    ceiling: Tuning.levelCeilingDecibels)
        return Frame(bands: bands, level: level)
    }

    private static func normalized(_ decibels: Float, floor: Float, ceiling: Float) -> Float {
        min(1, max(0, (decibels - floor) / (ceiling - floor)))
    }
}
