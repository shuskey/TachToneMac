import Foundation

// HonkVoice synthesizes a dual-tone car horn at G3 (196 Hz) + Eb4 (311 Hz).
// The harmonic profile — strong 2nd harmonic on both tones, plus a prominent
// 3rd harmonic on Eb4 — is derived from spectral analysis of a real car horn
// recording (dominant peaks at 388 Hz, 624 Hz, and 936 Hz).
struct HonkVoice {
    static let sampleRate:    Float = 44100
    static let hornFreq1:     Float = 196.0  // G3 — lower horn tone
    static let hornFreq2:     Float = 311.0  // Eb4 — upper horn tone
    static let attackSamples:   Int = Int(0.035 * 44100)  // 35 ms
    static let releaseSamples:  Int = Int(0.065 * 44100)  // 65 ms

    var buffer:      [Float] = []
    var bufferIndex:    Int  = 0

    // MARK: - Trigger

    mutating func triggerStandardHonk() {
        var p1: Float = 0
        var p2: Float = 0
        var buf: [Float] = []
        buf += HonkVoice.blast(seconds: 0.180, phase1: &p1, phase2: &p2)
        buf += [Float](repeating: 0, count: Int(0.090 * 44100))
        buf += HonkVoice.blast(seconds: 0.180, phase1: &p1, phase2: &p2)
        buffer      = buf
        bufferIndex = 0
    }

    mutating func triggerImpatientHonk() {
        var p1: Float = 0
        var p2: Float = 0
        var buf: [Float] = []

        let pause = [Float](repeating: 0, count: Int(0.350 * 44100))
        let quickGap = [Float](repeating: 0, count: Int(0.090 * 44100))

        // Cluster 1: 3–4 quick honks
        let n1 = Int.random(in: 3...4)
        for _ in 0..<n1 {
            buf += HonkVoice.blast(seconds: 0.180, phase1: &p1, phase2: &p2)
            buf += quickGap
        }
        buf += pause

        // Long lean: 4.5–5.5 seconds
        let longLean = Double.random(in: 4.5...5.5)
        buf += HonkVoice.blast(seconds: longLean, phase1: &p1, phase2: &p2)
        buf += pause

        // Cluster 2: 3–4 quick honks
        let n2 = Int.random(in: 3...4)
        for _ in 0..<n2 {
            buf += HonkVoice.blast(seconds: 0.180, phase1: &p1, phase2: &p2)
            buf += quickGap
        }
        buf += pause

        // Medium lean: 1.8–2.2 seconds
        let medLean = Double.random(in: 1.8...2.2)
        buf += HonkVoice.blast(seconds: medLean, phase1: &p1, phase2: &p2)

        buffer      = buf
        bufferIndex = 0
    }

    // MARK: - Render

    mutating func render(into hornBuffer: inout [Float], frameCount: Int) {
        for i in 0..<frameCount {
            if bufferIndex < buffer.count {
                hornBuffer[i] = buffer[bufferIndex]
                bufferIndex  += 1
            } else {
                hornBuffer[i] = 0
            }
        }
    }

    // MARK: - Private helpers

    /// Generates a two-tone car-horn blast with attack and release envelopes.
    /// Phases are passed inout so consecutive blasts are phase-continuous.
    ///
    /// Harmonic weights are matched to measured spectral analysis of a real horn:
    ///   G3  tone: h2 dominant (≈388 Hz), h4 moderate (≈784 Hz), h1/h8 weak
    ///   Eb4 tone: h2 dominant (≈622 Hz), h3 strong (≈933 Hz), h4 moderate, h1 weak
    private static func blast(seconds: Double, phase1: inout Float, phase2: inout Float) -> [Float] {
        let n = Int(seconds * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        let twoPi = Float.pi * 2
        let inc1 = twoPi * hornFreq1 / sampleRate
        let inc2 = twoPi * hornFreq2 / sampleRate

        // Peak of s1+s2 is bounded by sum of weights: (1.4 + 1.9) = 3.3.
        // Scale 0.42 keeps combined peak near 0.70, leaving headroom.
        let scale: Float = 0.42

        for i in 0..<n {
            phase1 = (phase1 + inc1).truncatingRemainder(dividingBy: twoPi)
            phase2 = (phase2 + inc2).truncatingRemainder(dividingBy: twoPi)

            // G3 tone: 2nd harmonic dominant, 4th moderate, fundamental & 8th weak
            let s1 =  sin(phase1)       * 0.10   // h1 ≈  196 Hz (weak fundamental)
                    + sin(2 * phase1)   * 1.00   // h2 ≈  392 Hz (dominant)
                    + sin(4 * phase1)   * 0.20   // h4 ≈  784 Hz (moderate)
                    + sin(8 * phase1)   * 0.10   // h8 ≈ 1568 Hz (slight shimmer)

            // Eb4 tone: 2nd harmonic dominant, 3rd strong, 4th moderate, fundamental weak
            let s2 =  sin(phase2)       * 0.20   // h1 ≈  311 Hz (weak fundamental)
                    + sin(2 * phase2)   * 1.00   // h2 ≈  622 Hz (dominant)
                    + sin(3 * phase2)   * 0.50   // h3 ≈  933 Hz (strong — real-horn buzz)
                    + sin(4 * phase2)   * 0.20   // h4 ≈ 1244 Hz (moderate)

            var s = (s1 + s2) * scale

            if i < attackSamples {
                s *= Float(i) / Float(attackSamples)
            }
            if i >= n - releaseSamples {
                s *= Float(n - 1 - i) / Float(releaseSamples)
            }
            out[i] = s
        }
        return out
    }
}
