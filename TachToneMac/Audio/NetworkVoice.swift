import Foundation

struct NetworkVoice {
    static let sampleRate: Float = 44100
    static let beatSamples: Int = 33075  // 44100 * 60 / 80 BPM
    static let noteFreqs: [Float] = [523.25, 587.33, 659.25, 698.46, 783.99, 880.00, 987.77, 1046.50]
    // Per-sample decay factors: exp(-1 / (τ * sampleRate))
    static let bellDecay:  Float = 0.999547  // τ = 50ms
    static let pianoDecay: Float = 0.999244  // τ = 30ms

    var beatCounter: Int = 0

    var bellPhase: Float = 0
    var bellAmp:   Float = 0
    var bellFreq:  Float = NetworkVoice.noteFreqs[0]

    var pianoPhase: Float = 0
    var pianoAmp:   Float = 0
    var pianoFreq:  Float = NetworkVoice.noteFreqs[0]

    // MARK: - Static helpers (testable)

    static func bandIndex(rate: Float) -> Int {
        return min(Int(rate / 500_000 * 8), 7)
    }

    // MARK: - Render

    mutating func render(bellBuffer: inout [Float], pianoBuffer: inout [Float],
                         frameCount: Int, snapshot: SharedState.Values) {
        let twoPi = Float.pi * 2

        for i in 0..<frameCount {
            beatCounter += 1
            if beatCounter >= NetworkVoice.beatSamples {
                beatCounter = 0

                if snapshot.netRecvRate > 5_000 {
                    let band = NetworkVoice.bandIndex(rate: snapshot.netRecvRate)
                    bellFreq = NetworkVoice.noteFreqs[band]
                    bellAmp  = 1.0
                }
                if snapshot.netSendRate > 5_000 {
                    let band = NetworkVoice.bandIndex(rate: snapshot.netSendRate)
                    pianoFreq = NetworkVoice.noteFreqs[band]
                    pianoAmp  = 1.0
                }
            }

            // Bell: fundamental + 2nd@25% + 3rd@10%, normalized by 1.35
            var bellSample: Float = 0
            if bellAmp > 0.0001 {
                bellPhase = (bellPhase + twoPi * bellFreq / NetworkVoice.sampleRate).truncatingRemainder(dividingBy: twoPi)
                bellSample = (sin(bellPhase)
                             + 0.25 * sin(2 * bellPhase)
                             + 0.10 * sin(3 * bellPhase)) / 1.35
                bellSample *= bellAmp
                bellAmp *= NetworkVoice.bellDecay
            }
            bellBuffer[i] = bellSample

            // Piano: fundamental + 60% + 35% + 15%, normalized by 2.10
            var pianoSample: Float = 0
            if pianoAmp > 0.0001 {
                pianoPhase = (pianoPhase + twoPi * pianoFreq / NetworkVoice.sampleRate).truncatingRemainder(dividingBy: twoPi)
                pianoSample = (sin(pianoPhase)
                              + 0.60 * sin(2 * pianoPhase)
                              + 0.35 * sin(3 * pianoPhase)
                              + 0.15 * sin(4 * pianoPhase)) / 2.10
                pianoSample *= pianoAmp
                pianoAmp *= NetworkVoice.pianoDecay
            }
            pianoBuffer[i] = pianoSample
        }
    }
}
