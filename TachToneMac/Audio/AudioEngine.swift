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

    // Voices
    private var cpuVoice     = CpuVoice()
    private var networkVoice = NetworkVoice()
    private var diskVoice    = DiskVoice()
    private var gpuVoice     = GpuVoice()
    private var honkVoice    = HonkVoice()

    // Pre-allocated mix buffers — no allocation in the real-time callback
    private var cpuBuffer    = [Float](repeating: 0, count: 4096)
    private var bellBuffer   = [Float](repeating: 0, count: 4096)
    private var pianoBuffer  = [Float](repeating: 0, count: 4096)
    private var diskBuffer   = [Float](repeating: 0, count: 4096)
    private var gpuBuffer    = [Float](repeating: 0, count: 4096)
    private var honkBuffer   = [Float](repeating: 0, count: 4096)

    init(state: SharedState) { self.sharedState = state }

    func start() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

        sourceNode = AVAudioSourceNode(format: format) { [weak self] isSilence, _, frameCount, audioBufferList in
            guard let self else { isSilence.pointee = true; return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }

            let count = Int(frameCount)

            // Snapshot shared state once — no further reads in this block
            var snapshot = self.sharedState.snapshot()

            // Handle one-shot honk flags (must clear after reading)
            if snapshot.honk || snapshot.impatientHonk {
                if snapshot.impatientHonk {
                    self.honkVoice.triggerImpatientHonk()
                } else {
                    self.honkVoice.triggerStandardHonk()
                }
                self.sharedState.clearHonkFlags()
                snapshot = self.sharedState.snapshot()
            }

            // Render all voices
            self.cpuVoice.render(into: &self.cpuBuffer, frameCount: count, snapshot: snapshot)
            self.networkVoice.render(bellBuffer: &self.bellBuffer, pianoBuffer: &self.pianoBuffer,
                                     frameCount: count, snapshot: snapshot)
            self.diskVoice.render(into: &self.diskBuffer, frameCount: count, snapshot: snapshot)
            self.gpuVoice.render(into: &self.gpuBuffer, frameCount: count, snapshot: snapshot)
            self.honkVoice.render(into: &self.honkBuffer, frameCount: count)

            // Mix (spec formula)
            let master  = Float(snapshot.volume)     / 100.0
            let cpuCh   = Float(snapshot.cpuVol)     / 100.0
            let netCh   = Float(snapshot.networkVol) / 100.0
            let diskCh  = Float(snapshot.diskVol)    / 100.0
            let gpuCh   = Float(snapshot.gpuVol)     / 100.0
            let honkCh  = Float(snapshot.honkVol)    / 100.0

            for i in 0..<count {
                var s = master * cpuCh  * self.cpuBuffer[i]
                      + master * 0.27 * netCh  * (self.bellBuffer[i] + self.pianoBuffer[i])
                      + master * 0.35 * diskCh * self.diskBuffer[i]
                      + master * honkCh          * self.honkBuffer[i]
                      + master * 0.30 * gpuCh  * self.gpuBuffer[i]
                out[i] = max(-1.0, min(1.0, s))
            }
            return noErr
        }

        guard let node = sourceNode else { return }
        avEngine.attach(node)
        avEngine.connect(node, to: avEngine.mainMixerNode, format: format)
        try avEngine.start()
    }

    func stop() { avEngine.stop() }
}
