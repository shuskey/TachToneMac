import Foundation

struct HonkVoice {
    static let sampleRate:    Float = 44100
    static let hornFreq1:     Float = 392   // G4
    static let hornFreq2:     Float = 494   // B4
    static let attackSamples:   Int = Int(0.010 * 44100)  // 441
    static let releaseSamples:  Int = Int(0.025 * 44100)  // 1102

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

    /// Generates a two-tone blast with attack and release envelopes.
    /// Phases are passed inout so consecutive blasts are phase-continuous.
    private static func blast(seconds: Double, phase1: inout Float, phase2: inout Float) -> [Float] {
        let n = Int(seconds * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        let twoPi = Float.pi * 2
        let inc1 = twoPi * hornFreq1 / sampleRate
        let inc2 = twoPi * hornFreq2 / sampleRate

        for i in 0..<n {
            phase1 = (phase1 + inc1).truncatingRemainder(dividingBy: twoPi)
            phase2 = (phase2 + inc2).truncatingRemainder(dividingBy: twoPi)
            var s = 0.5 * (sin(phase1) + sin(phase2))

            // Attack
            if i < attackSamples {
                s *= Float(i) / Float(attackSamples)
            }
            // Release
            if i >= n - releaseSamples {
                s *= Float(n - 1 - i) / Float(releaseSamples)
            }
            out[i] = s
        }
        return out
    }
}
