import Foundation

struct CpuVoice {
    static let sampleRate: Float = 44100
    static let harmonicWeights: [Float] = [0.30, 1.00, 0.45, 0.80, 0.25, 0.55, 0.15, 0.35]
    static let weightSum: Float = harmonicWeights.reduce(0, +)  // 3.85

    var phase: Float = 0       // fundamental phase accumulator [0, 2π)
    var amPhase: Float = 0     // AM (chug) phase accumulator
    var lfoPhase: Float = 0    // vibrato LFO phase accumulator
    var smoothedFreq: Float = 700.0 / 60.0  // start at idle RPM

    // MARK: - Static helpers (testable)

    static func targetFrequency(cpuPercent: Float) -> Float {
        let rpm = 700 + cpuPercent * 63  // 700 RPM at 0%, 7000 RPM at 100%
        return rpm / 60
    }

    static func amDepth(cpuPercent: Float) -> Float {
        return 0.40 * max(0, 1 - cpuPercent / 67)
    }

    // MARK: - Render

    mutating func render(into buffer: inout [Float], frameCount: Int, snapshot: SharedState.Values) {
        let twoPi = Float.pi * 2
        let target = CpuVoice.targetFrequency(cpuPercent: snapshot.cpuPercent)

        // Frequency smoothing — once per block (spec: α = 0.02 per block)
        smoothedFreq = 0.02 * target + 0.98 * smoothedFreq

        let amDepth = CpuVoice.amDepth(cpuPercent: snapshot.cpuPercent)
        let vibratoDepth = (snapshot.ctxRate / 50_000) * smoothedFreq
            * 0.05 * Float(snapshot.interruptsVol) / 100

        let amPhaseInc  = twoPi * (2 * smoothedFreq) / CpuVoice.sampleRate
        let lfoPhaseInc = twoPi * 7.0 / CpuVoice.sampleRate

        for i in 0..<frameCount {
            // Per-sample modulated frequency (vibrato)
            let modulatedFreq = smoothedFreq + vibratoDepth * sin(lfoPhase)
            let phaseInc = twoPi * modulatedFreq / CpuVoice.sampleRate

            // Advance fundamental phase
            phase = (phase + phaseInc).truncatingRemainder(dividingBy: twoPi)

            // Harmonic stack: all harmonics derived from one phase accumulator
            var sample: Float = 0
            for (h, weight) in CpuVoice.harmonicWeights.enumerated() {
                sample += weight * sin(Float(h + 1) * phase)
            }
            sample /= CpuVoice.weightSum

            // AM idle chug: ranges from (1 - amDepth) to 1.0
            let amMod = 1.0 - amDepth / 2 + amDepth / 2 * cos(amPhase)
            sample *= amMod

            // Mechanical noise
            sample += Float.random(in: -0.004...0.004)

            buffer[i] = sample

            amPhase  = (amPhase  + amPhaseInc ).truncatingRemainder(dividingBy: twoPi)
            lfoPhase = (lfoPhase + lfoPhaseInc).truncatingRemainder(dividingBy: twoPi)
        }
    }
}
