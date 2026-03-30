import Foundation

struct GpuVoice {
    static let sampleRate: Float = 44100
    static let beatSamples: Int = 33075
    static let organDecay: Float = 0.9999874  // exp(-1 / (1.8 * 44100))
    static let harmonicWeights: [Float] = [1.0, 0.7, 0.5, 0.3]
    static let harmonicWeightSum: Float = 2.5

    static let chordFreqs: [[Float]] = [
        [261.63, 349.23, 466.16],
        [293.66, 392.00, 523.25],
        [329.63, 440.00, 587.33],
        [349.23, 466.16, 622.25],
        [392.00, 523.25, 698.46],
        [440.00, 587.33, 783.99],
        [493.88, 659.25, 880.00],
        [523.25, 698.46, 932.33]
    ]
    // 4 voicings: all three, root+4th, 4th+top, root+top
    static let voicings: [[Int]] = [[0, 1, 2], [0, 1], [1, 2], [0, 2]]

    var currentBand:  Int = 0
    var beatCounter:  Int = 0
    var stableBeats:  Int = 0

    // Per-note state
    var notePhases: [Float] = [0, 0, 0]
    var noteAmps:   [Float] = [0, 0, 0]

    var vibratoPhase: Float = 0
    var tremoloPhase: Float = 0

    // MARK: - Static helpers (testable)

    static func targetBand(gpuPercent: Float) -> Int {
        return min(Int(gpuPercent / 12.5), 7)
    }

    // MARK: - Render

    mutating func render(into buffer: inout [Float], frameCount: Int, snapshot: SharedState.Values) {
        guard snapshot.gpu3dPercent >= 5.0 else {
            for i in 0..<frameCount { buffer[i] = 0 }
            return
        }

        let twoPi = Float.pi * 2
        let vibratoInc = twoPi * 4.5 / GpuVoice.sampleRate
        let tremoloInc = twoPi * 3.1 / GpuVoice.sampleRate
        let target = GpuVoice.targetBand(gpuPercent: snapshot.gpu3dPercent)

        for i in 0..<frameCount {
            beatCounter += 1
            if beatCounter >= GpuVoice.beatSamples {
                beatCounter = 0

                // Step one band toward target
                let prevBand = currentBand
                if currentBand < target      { currentBand += 1 }
                else if currentBand > target { currentBand -= 1 }
                stableBeats = (currentBand == prevBand) ? min(stableBeats + 1, 4) : 0

                // Choose voicing and reset those note amplitudes
                let voicing = GpuVoice.voicings[Int.random(in: 0..<GpuVoice.voicings.count)]
                for ni in voicing { noteAmps[ni] = 1.0 }
            }

            // Wobble ramp: 0.0 → 1.0 over 4 stable beats
            let wobble = Float(stableBeats) / 4.0

            let freqs = GpuVoice.chordFreqs[currentBand]
            var sample: Float = 0

            for ni in 0..<3 {
                guard noteAmps[ni] > 0.0001 else { continue }

                let baseFreq = freqs[ni]
                let vibratoOffset = wobble * 0.004 * baseFreq * sin(vibratoPhase)
                let freq = baseFreq + vibratoOffset

                notePhases[ni] = (notePhases[ni] + twoPi * freq / GpuVoice.sampleRate)
                    .truncatingRemainder(dividingBy: twoPi)

                var noteSample: Float = 0
                for (h, weight) in GpuVoice.harmonicWeights.enumerated() {
                    noteSample += weight * sin(Float(h + 1) * notePhases[ni])
                }
                noteSample /= GpuVoice.harmonicWeightSum

                let tremolo = 1.0 + wobble * 0.25 * sin(tremoloPhase)
                noteSample *= tremolo * noteAmps[ni]
                noteAmps[ni] *= GpuVoice.organDecay
                sample += noteSample
            }
            sample /= 3.0  // normalize across max 3 simultaneous notes

            buffer[i] = sample

            vibratoPhase = (vibratoPhase + vibratoInc).truncatingRemainder(dividingBy: twoPi)
            tremoloPhase = (tremoloPhase + tremoloInc).truncatingRemainder(dividingBy: twoPi)
        }
    }
}
