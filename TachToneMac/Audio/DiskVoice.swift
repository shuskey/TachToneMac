import Foundation

struct DiskVoice {
    static let sampleRate:       Float = 44100
    static let beatSamples:        Int = 33075
    static let sixteenthSamples:   Int = beatSamples / 4  // 8268
    static let sweepDuration:      Int = Int(0.025 * 44100)  // 1102 samples = 25ms
    static let tomFreqs:         [Float] = [80, 100, 120, 140, 165, 190, 215, 250]
    static let decayFactor:       Float = 0.999676  // exp(-1 / (0.070 * 44100))

    var sixteenthCounter: Int = 0
    var phase:         Float = 0
    var amp:           Float = 0
    var targetFreq:    Float = 80
    var sweepStartFreq: Float = 80
    var currentFreq:   Float = 80
    var sweepSample:     Int = 0

    // MARK: - Static helpers (testable)

    static func pitchBand(diskRate: Float) -> Int {
        return min(Int(diskRate / 10_000_000 * 8), 7)
    }

    // MARK: - Render

    mutating func render(into buffer: inout [Float], frameCount: Int, snapshot: SharedState.Values) {
        let twoPi = Float.pi * 2

        for i in 0..<frameCount {
            sixteenthCounter += 1
            if sixteenthCounter >= DiskVoice.sixteenthSamples {
                sixteenthCounter = 0
                if snapshot.diskRate > 100_000 {
                    let band = DiskVoice.pitchBand(diskRate: snapshot.diskRate)
                    targetFreq    = DiskVoice.tomFreqs[band]
                    sweepStartFreq = targetFreq + 25
                    currentFreq   = sweepStartFreq
                    amp           = 1.0
                    sweepSample   = 0
                }
            }

            // Pitch sweep: glide from sweepStartFreq to targetFreq over sweepDuration
            if sweepSample < DiskVoice.sweepDuration {
                let t = Float(sweepSample) / Float(DiskVoice.sweepDuration)
                currentFreq = sweepStartFreq + t * (targetFreq - sweepStartFreq)
                sweepSample += 1
            }

            var sample: Float = 0
            if amp > 0.0001 {
                // Phase accumulation accounts for time-varying frequency
                phase = (phase + twoPi * currentFreq / DiskVoice.sampleRate)
                    .truncatingRemainder(dividingBy: twoPi)
                sample = sin(phase) * amp
                amp *= DiskVoice.decayFactor
            }
            buffer[i] = sample
        }
    }
}
