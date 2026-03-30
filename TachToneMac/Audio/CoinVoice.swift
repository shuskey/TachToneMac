import Foundation

// CoinVoice plays N retro-coin "ping" tones in quick succession.
// Each ping is a square-wave approximation at B5 (~988 Hz) with a fast
// ~8 ms attack followed by a smooth linear decay.
// All coins except the last use a short 120 ms decay for rapid stacking.
// The final coin always uses a long 450 ms decay so the sequence tails off naturally.
struct CoinVoice {
    static let sampleRate: Float   = 44100
    static let chirpSeconds: Double = 0.120   // short ping for all-but-last coins
    static let longChirpSeconds: Double = 0.450   // long trailing ping for the final coin
    static let gapSeconds:   Double = 0.000   // silence between coins
    static let freq:         Float  = 988.0   // B5 – single sustained pitch, no sweep
    static let attackSamples: Int   = Int(0.008 * 44100)   // 8 ms sharp attack

    var buffer:      [Float] = []
    var bufferIndex: Int     = 0

    // MARK: - Trigger

    mutating func triggerCoins(_ count: Int) {
        let gap = [Float](repeating: 0, count: Int(CoinVoice.gapSeconds * Double(CoinVoice.sampleRate)))
        var buf: [Float] = []
        for i in 0..<count {
            let isLast = (i == count - 1)
            buf += CoinVoice.chirp(seconds: isLast ? CoinVoice.longChirpSeconds : CoinVoice.chirpSeconds)
            if !isLast { buf += gap }
        }
        buffer      = buf
        bufferIndex = 0
    }

    // MARK: - Render

    mutating func render(into coinBuffer: inout [Float], frameCount: Int) {
        for i in 0..<frameCount {
            coinBuffer[i] = bufferIndex < buffer.count ? buffer[bufferIndex] : 0
            bufferIndex  += 1
        }
    }

    // MARK: - Private

    /// One retro-coin ping: square-wave timbre (odd harmonics 1,3,5,7) at B5
    /// with a fast attack and linear amplitude decay over `seconds`.
    private static func chirp(seconds: Double) -> [Float] {
        let n = Int(seconds * Double(sampleRate))
        var out = [Float](repeating: 0, count: n)
        let twoPi = Float.pi * 2
        let step  = twoPi * freq / sampleRate

        // Independent phase accumulators for each harmonic
        var ph1: Float = 0
        var ph3: Float = 0
        var ph5: Float = 0
        var ph7: Float = 0

        // Scale factor: (4/π) normalizes odd-harmonic sum to square-wave amplitude,
        // then 0.70 provides headroom against clipping.
        let scale: Float = (4.0 / Float.pi) * 0.70

        for i in 0..<n {
            ph1 = (ph1 + step       ).truncatingRemainder(dividingBy: twoPi)
            ph3 = (ph3 + step * 3.0 ).truncatingRemainder(dividingBy: twoPi)
            ph5 = (ph5 + step * 5.0 ).truncatingRemainder(dividingBy: twoPi)
            ph7 = (ph7 + step * 7.0 ).truncatingRemainder(dividingBy: twoPi)

            let s = (sin(ph1) + sin(ph3) / 3.0 + sin(ph5) / 5.0 + sin(ph7) / 7.0) * scale

            // Fast attack, then smooth linear decay to silence over the rest of the chirp
            let envelope: Float
            if i < attackSamples {
                envelope = Float(i) / Float(attackSamples)
            } else {
                let decayProgress = Float(i - attackSamples) / Float(n - attackSamples)
                envelope = 1.0 - decayProgress
            }
            out[i] = s * envelope
        }
        return out
    }
}
