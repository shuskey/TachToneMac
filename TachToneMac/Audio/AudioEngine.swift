import AVFoundation

// SAFETY: All voice state is mutated exclusively from the AVAudioSourceNode
// render callback, which runs on a dedicated real-time audio thread.
// AppDelegate calls start() once on the main thread before the callback begins.
// No voice state is accessed from any other thread.
// NOTE: The render callback calls sharedState.snapshot(), which acquires an NSLock.
// This is a known audio-thread tradeoff — the lock is uncontended in normal operation
// (pollers hold it for microseconds). A lock-free approach can be adopted if glitches occur.
final class TachToneAudioEngine: @unchecked Sendable {
    private let avEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let sharedState: SharedState

    // Pre-allocated mix buffers — never reallocated in the callback
    private var cpuBuffer    = [Float](repeating: 0, count: 4096)
    private var bellBuffer   = [Float](repeating: 0, count: 4096)
    private var pianoBuffer  = [Float](repeating: 0, count: 4096)
    private var diskBuffer   = [Float](repeating: 0, count: 4096)
    private var gpuBuffer    = [Float](repeating: 0, count: 4096)
    private var honkBuffer   = [Float](repeating: 0, count: 4096)

    init(state: SharedState) {
        self.sharedState = state
    }

    func start() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        sourceNode = AVAudioSourceNode(format: format) { [weak self] isSilence, _, frameCount, audioBufferList in
            guard let self else { isSilence.pointee = true; return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let count = Int(frameCount)
            let snapshot = self.sharedState.snapshot()
            _ = snapshot

            // Zero all output (voices added in Tasks 2–6)
            for i in 0..<count { out[i] = 0 }
            return noErr
        }

        guard let node = sourceNode else { return }
        avEngine.attach(node)
        avEngine.connect(node, to: avEngine.mainMixerNode, format: format)
        try avEngine.start()
    }

    func stop() {
        avEngine.stop()
    }
}
