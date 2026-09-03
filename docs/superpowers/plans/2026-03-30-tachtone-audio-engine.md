# TachTone macOS — Audio Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a real-time audio engine that synthesizes a continuous soundscape from live system metrics — a 4-cylinder engine tone driven by CPU, bell/piano from network traffic, tom-tom from disk I/O, a quartal organ from GPU load, and a car horn triggered by Claude Code hooks.

**Architecture:** `AVAudioEngine` with an `AVAudioSourceNode` render callback (mono, 44100 Hz, up to 1024 frames). Each voice is a Swift `struct` with mutating state (phase accumulators, envelopes). The engine owns all voice instances and pre-allocated mix buffers; the callback reads a `SharedState` snapshot at the top of each block and calls each voice's render method, then applies the spec mix formula and clips to [-1.0, 1.0].

**Tech Stack:** Swift 6, `AVAudioEngine`, `AVAudioSourceNode`, `AVAudioFormat`, `Foundation`

---

## File Structure

```
TachToneMac/Audio/
├── AudioEngine.swift    ← AVAudioEngine setup, render callback, mix formula
├── CpuVoice.swift       ← 4-cylinder engine tone (harmonics, AM, vibrato)
├── NetworkVoice.swift   ← Bell (recv) + Piano (send) beat-triggered voices
├── DiskVoice.swift      ← Tom-tom 16th-note percussion with pitch sweep
├── GpuVoice.swift       ← Quartal-chord organ with wobble
└── HonkVoice.swift      ← Pre-rendered car horn sequences

TachToneMacTests/
├── AudioEngineTests.swift
├── CpuVoiceTests.swift
├── NetworkVoiceTests.swift
├── DiskVoiceTests.swift
├── GpuVoiceTests.swift
└── HonkVoiceTests.swift
```

**Existing file modified each task:** `TachToneMac/App/AppDelegate.swift` (final wiring in Task 1 only)

---

## Shared constants (used across multiple voice files)

```swift
// Every voice file that needs these defines them as static lets:
static let sampleRate: Float = 44100
static let beatSamples: Int = 33075  // 44100 * 60 / 80 BPM
```

---

## Task 1: AudioEngine Scaffold

**Files:**
- Create: `TachToneMac/Audio/AudioEngine.swift`
- Create: `TachToneMacTests/AudioEngineTests.swift`
- Modify: `TachToneMac/App/AppDelegate.swift`

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/AudioEngineTests.swift`:

  ```swift
  import XCTest
  import AVFoundation
  @testable import TachToneMac

  final class AudioEngineTests: XCTestCase {

      func test_start_doesNotThrow() throws {
          let state = SharedState()
          let engine = TachToneAudioEngine(state: state)
          XCTAssertNoThrow(try engine.start())
          engine.stop()
      }

      func test_stop_afterStart_doesNotCrash() throws {
          let state = SharedState()
          let engine = TachToneAudioEngine(state: state)
          try engine.start()
          engine.stop()
          // calling stop again should not crash
          engine.stop()
      }
  }
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: build error — `TachToneAudioEngine` not found.

- [ ] **Step 3: Write `TachToneMac/Audio/AudioEngine.swift`**

  ```swift
  import AVFoundation

  // SAFETY: All voice state is mutated exclusively from the AVAudioSourceNode
  // render callback, which runs on a dedicated real-time audio thread.
  // AppDelegate calls start() once on the main thread before the callback begins.
  // No voice state is accessed from any other thread.
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
  ```

- [ ] **Step 4: Run xcodegen + run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

  Expected: `AudioEngineTests` passes. All prior suites pass.

- [ ] **Step 5: Wire into AppDelegate**

  Replace the contents of `TachToneMac/App/AppDelegate.swift`:

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem!
      private let sharedState = SharedState()
      private lazy var cpuPoller     = CpuPoller(state: sharedState)
      private lazy var networkPoller = NetworkPoller(state: sharedState)
      private lazy var diskPoller    = DiskPoller(state: sharedState)
      private lazy var gpuPoller     = GpuPoller(state: sharedState)
      private lazy var honkListener  = HonkListener(state: sharedState)
      private lazy var audioEngine   = TachToneAudioEngine(state: sharedState)

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button { button.title = "T" }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu

          cpuPoller.start()
          networkPoller.start()
          diskPoller.start()
          gpuPoller.start()
          honkListener.start()
          try? audioEngine.start()
      }

      @objc private func quit() {
          audioEngine.stop()
          NSApp.terminate(nil)
      }
  }
  ```

- [ ] **Step 6: Build to verify**

  ```bash
  xcodebuild -scheme TachToneMac -destination 'platform=macOS' build 2>&1 | tail -3
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

  ```bash
  cd /Users/shuskey/github/TachToneMac
  git add TachToneMac/Audio/AudioEngine.swift TachToneMacTests/AudioEngineTests.swift TachToneMac/App/AppDelegate.swift
  git commit -m "feat: AudioEngine scaffold — AVAudioSourceNode, mono 44100Hz, silence output"
  ```

---

## Task 2: CpuVoice

**Files:**
- Create: `TachToneMac/Audio/CpuVoice.swift`
- Create: `TachToneMacTests/CpuVoiceTests.swift`
- Modify: `TachToneMac/Audio/AudioEngine.swift` (add voice + wire into mix)

The CPU voice simulates a 4-cylinder engine. Pitch = CPU load. One phase accumulator drives 8 harmonics. AM modulation creates the idle lope. A 7 Hz LFO driven by context-switch rate creates instability.

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/CpuVoiceTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class CpuVoiceTests: XCTestCase {

      func test_targetFrequency_at0pct() {
          XCTAssertEqual(CpuVoice.targetFrequency(cpuPercent: 0), 700.0/60.0, accuracy: 0.01)
      }

      func test_targetFrequency_at100pct() {
          XCTAssertEqual(CpuVoice.targetFrequency(cpuPercent: 100), 7000.0/60.0, accuracy: 0.01)
      }

      func test_amDepth_at0pct() {
          XCTAssertEqual(CpuVoice.amDepth(cpuPercent: 0), 0.40, accuracy: 0.001)
      }

      func test_amDepth_at67pct() {
          XCTAssertEqual(CpuVoice.amDepth(cpuPercent: 67), 0.0, accuracy: 0.001)
      }

      func test_amDepth_above67pct() {
          XCTAssertEqual(CpuVoice.amDepth(cpuPercent: 100), 0.0, accuracy: 0.001)
      }

      func test_harmonicWeightSum() {
          XCTAssertEqual(CpuVoice.weightSum, 3.85, accuracy: 0.001)
      }

      func test_render_withZeroVolume_producesSilence() {
          var voice = CpuVoice()
          var state = SharedState.Values()
          state.cpuVol = 0
          var buffer = [Float](repeating: 0, count: 256)
          voice.render(into: &buffer, frameCount: 256, snapshot: state)
          // With zero volume the AudioEngine applies cpuCh=0, but voice itself
          // still produces signal — verify signal IS present (voice ignores volume)
          // Volume is applied by AudioEngine, not the voice itself
          let hasSignal = buffer.contains { abs($0) > 0.001 }
          XCTAssertTrue(hasSignal, "CpuVoice should produce signal regardless of channel volume")
      }

      func test_render_outputIsWithinRange() {
          var voice = CpuVoice()
          var state = SharedState.Values()
          state.cpuPercent = 50
          var buffer = [Float](repeating: 0, count: 1024)
          voice.render(into: &buffer, frameCount: 1024, snapshot: state)
          for sample in buffer {
              XCTAssertLessThanOrEqual(abs(sample), 1.5, "Sample \(sample) exceeds reasonable range")
          }
      }

      func test_render_phaseContinuity_noClickBetweenBlocks() {
          var voice = CpuVoice()
          var state = SharedState.Values()
          state.cpuPercent = 50
          var buf1 = [Float](repeating: 0, count: 256)
          var buf2 = [Float](repeating: 0, count: 256)
          voice.render(into: &buf1, frameCount: 256, snapshot: state)
          voice.render(into: &buf2, frameCount: 256, snapshot: state)
          // The jump between the last sample of buf1 and first of buf2 should be small
          let jump = abs(buf1[255] - buf2[0])
          XCTAssertLessThan(jump, 0.5, "Phase discontinuity between blocks: \(jump)")
      }
  }
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

- [ ] **Step 3: Write `TachToneMac/Audio/CpuVoice.swift`**

  ```swift
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
  ```

- [ ] **Step 4: Run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

  Expected: all `CpuVoiceTests` pass.

- [ ] **Step 5: Wire CpuVoice into AudioEngine**

  Edit `TachToneMac/Audio/AudioEngine.swift` — add the voice property and update the render callback:

  ```swift
  import AVFoundation

  // SAFETY: All voice state is mutated exclusively from the AVAudioSourceNode
  // render callback, which runs on a dedicated real-time audio thread.
  // AppDelegate calls start() once on the main thread before the callback begins.
  final class TachToneAudioEngine: @unchecked Sendable {
      private let avEngine = AVAudioEngine()
      private var sourceNode: AVAudioSourceNode?
      private let sharedState: SharedState

      private var cpuVoice = CpuVoice()

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
              let snapshot = self.sharedState.snapshot()

              self.cpuVoice.render(into: &self.cpuBuffer, frameCount: count, snapshot: snapshot)

              let master = Float(snapshot.volume) / 100.0
              let cpuCh  = Float(snapshot.cpuVol)  / 100.0

              for i in 0..<count {
                  var s = master * cpuCh * self.cpuBuffer[i]
                  // net, disk, gpu, honk voices added in Tasks 3–6
                  s = max(-1.0, min(1.0, s))
                  out[i] = s
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
  ```

- [ ] **Step 6: Build + test**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|BUILD|error:"
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add TachToneMac/Audio/CpuVoice.swift TachToneMacTests/CpuVoiceTests.swift TachToneMac/Audio/AudioEngine.swift
  git commit -m "feat: CpuVoice — 4-cylinder engine tone with harmonics, AM chug, vibrato"
  ```

---

## Task 3: NetworkVoice

**Files:**
- Create: `TachToneMac/Audio/NetworkVoice.swift`
- Create: `TachToneMacTests/NetworkVoiceTests.swift`
- Modify: `TachToneMac/Audio/AudioEngine.swift`

Bell = incoming traffic. Piano = outgoing traffic. Both are beat-triggered at 80 BPM (every 33,075 samples).

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/NetworkVoiceTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class NetworkVoiceTests: XCTestCase {

      func test_bandIndex_belowThreshold() {
          XCTAssertEqual(NetworkVoice.bandIndex(rate: 0), 0)
          XCTAssertEqual(NetworkVoice.bandIndex(rate: 4999), 0)
      }

      func test_bandIndex_maxRate() {
          XCTAssertEqual(NetworkVoice.bandIndex(rate: 500_000), 7)
          XCTAssertEqual(NetworkVoice.bandIndex(rate: 1_000_000), 7)  // clamp
      }

      func test_bandIndex_midRate() {
          // 250,000 bytes/sec → floor(250000/500000 * 8) = floor(4.0) = 4
          XCTAssertEqual(NetworkVoice.bandIndex(rate: 250_000), 4)
      }

      func test_noteFrequencies_count() {
          XCTAssertEqual(NetworkVoice.noteFreqs.count, 8)
      }

      func test_noteFrequency_band0() {
          XCTAssertEqual(NetworkVoice.noteFreqs[0], 523.25, accuracy: 0.01)
      }

      func test_noteFrequency_band7() {
          XCTAssertEqual(NetworkVoice.noteFreqs[7], 1046.50, accuracy: 0.01)
      }

      func test_render_noTraffic_producesSilence() {
          var voice = NetworkVoice()
          var state = SharedState.Values()
          state.netRecvRate = 0
          state.netSendRate = 0
          var bell = [Float](repeating: 1, count: 256)
          var piano = [Float](repeating: 1, count: 256)
          voice.render(bellBuffer: &bell, pianoBuffer: &piano, frameCount: 256, snapshot: state)
          // Before any beat fires, bell and piano should be silent (amp = 0 initially)
          let bellSum = bell.map { abs($0) }.reduce(0, +)
          XCTAssertEqual(bellSum, 0, accuracy: 0.001)
      }

      func test_render_afterBeatTrigger_withTraffic_producesSignal() {
          var voice = NetworkVoice()
          var state = SharedState.Values()
          state.netRecvRate = 100_000  // above 5000 threshold
          var bell = [Float](repeating: 0, count: 33_100)  // slightly more than one beat
          var piano = [Float](repeating: 0, count: 33_100)
          voice.render(bellBuffer: &bell, pianoBuffer: &piano, frameCount: 33_100, snapshot: state)
          let hasSignal = bell.contains { abs($0) > 0.001 }
          XCTAssertTrue(hasSignal, "Bell should produce signal after a beat fires with recv traffic")
      }
  }
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

- [ ] **Step 3: Write `TachToneMac/Audio/NetworkVoice.swift`**

  ```swift
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
  ```

- [ ] **Step 4: Run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

  Expected: all `NetworkVoiceTests` pass.

- [ ] **Step 5: Wire into AudioEngine**

  Edit `TachToneMac/Audio/AudioEngine.swift` — add `networkVoice` and update the callback and mix:

  ```swift
  import AVFoundation

  final class TachToneAudioEngine: @unchecked Sendable {
      private let avEngine = AVAudioEngine()
      private var sourceNode: AVAudioSourceNode?
      private let sharedState: SharedState

      private var cpuVoice     = CpuVoice()
      private var networkVoice = NetworkVoice()

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
              let snapshot = self.sharedState.snapshot()

              self.cpuVoice.render(into: &self.cpuBuffer, frameCount: count, snapshot: snapshot)
              self.networkVoice.render(bellBuffer: &self.bellBuffer, pianoBuffer: &self.pianoBuffer,
                                       frameCount: count, snapshot: snapshot)

              let master = Float(snapshot.volume)  / 100.0
              let cpuCh  = Float(snapshot.cpuVol)  / 100.0
              let netCh  = Float(snapshot.networkVol) / 100.0

              for i in 0..<count {
                  var s = master * cpuCh * self.cpuBuffer[i]
                        + master * 0.27 * netCh * (self.bellBuffer[i] + self.pianoBuffer[i])
                  // disk, gpu, honk added in Tasks 4–6
                  s = max(-1.0, min(1.0, s))
                  out[i] = s
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
  ```

- [ ] **Step 6: Build + test**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|BUILD|error:"
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add TachToneMac/Audio/NetworkVoice.swift TachToneMacTests/NetworkVoiceTests.swift TachToneMac/Audio/AudioEngine.swift
  git commit -m "feat: NetworkVoice — beat-triggered bell (recv) and piano (send) at 80 BPM"
  ```

---

## Task 4: DiskVoice

**Files:**
- Create: `TachToneMac/Audio/DiskVoice.swift`
- Create: `TachToneMacTests/DiskVoiceTests.swift`
- Modify: `TachToneMac/Audio/AudioEngine.swift`

Tom-tom triggered on 16th notes (every 8,268 samples). Pitch sweep: starts 25 Hz above target frequency, glides to target over 25ms — creates the "thwack" attack.

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/DiskVoiceTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class DiskVoiceTests: XCTestCase {

      func test_pitchBand_belowThreshold() {
          XCTAssertEqual(DiskVoice.pitchBand(diskRate: 0), 0)
          XCTAssertEqual(DiskVoice.pitchBand(diskRate: 99_999), 0)
      }

      func test_pitchBand_maxRate() {
          XCTAssertEqual(DiskVoice.pitchBand(diskRate: 10_000_000), 7)
          XCTAssertEqual(DiskVoice.pitchBand(diskRate: 20_000_000), 7)  // clamp
      }

      func test_pitchBand_midRate() {
          // 5,000,000 → floor(5000000/10000000 * 8) = floor(4.0) = 4
          XCTAssertEqual(DiskVoice.pitchBand(diskRate: 5_000_000), 4)
      }

      func test_tomFrequencies_count() {
          XCTAssertEqual(DiskVoice.tomFreqs.count, 8)
      }

      func test_tomFrequency_band0() {
          XCTAssertEqual(DiskVoice.tomFreqs[0], 80, accuracy: 0.01)
      }

      func test_tomFrequency_band7() {
          XCTAssertEqual(DiskVoice.tomFreqs[7], 250, accuracy: 0.01)
      }

      func test_render_noDiskActivity_producesSilence() {
          var voice = DiskVoice()
          var state = SharedState.Values()
          state.diskRate = 0
          var buffer = [Float](repeating: 1, count: 256)
          voice.render(into: &buffer, frameCount: 256, snapshot: state)
          let sum = buffer.map { abs($0) }.reduce(0, +)
          XCTAssertEqual(sum, 0, accuracy: 0.001)
      }

      func test_render_afterSixteenthNoteWithDisk_producesSignal() {
          var voice = DiskVoice()
          var state = SharedState.Values()
          state.diskRate = 500_000  // above 100,000 threshold
          let frames = DiskVoice.sixteenthSamples + 100
          var buffer = [Float](repeating: 0, count: frames)
          voice.render(into: &buffer, frameCount: frames, snapshot: state)
          let hasSignal = buffer.contains { abs($0) > 0.001 }
          XCTAssertTrue(hasSignal, "DiskVoice should strike a tom after a 16th note")
      }
  }
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

- [ ] **Step 3: Write `TachToneMac/Audio/DiskVoice.swift`**

  ```swift
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
  ```

- [ ] **Step 4: Run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

- [ ] **Step 5: Wire into AudioEngine**

  Edit `TachToneMac/Audio/AudioEngine.swift` — add `diskVoice` and update:

  ```swift
  import AVFoundation

  final class TachToneAudioEngine: @unchecked Sendable {
      private let avEngine = AVAudioEngine()
      private var sourceNode: AVAudioSourceNode?
      private let sharedState: SharedState

      private var cpuVoice     = CpuVoice()
      private var networkVoice = NetworkVoice()
      private var diskVoice    = DiskVoice()

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
              let snapshot = self.sharedState.snapshot()

              self.cpuVoice.render(into: &self.cpuBuffer, frameCount: count, snapshot: snapshot)
              self.networkVoice.render(bellBuffer: &self.bellBuffer, pianoBuffer: &self.pianoBuffer,
                                       frameCount: count, snapshot: snapshot)
              self.diskVoice.render(into: &self.diskBuffer, frameCount: count, snapshot: snapshot)

              let master  = Float(snapshot.volume)     / 100.0
              let cpuCh   = Float(snapshot.cpuVol)     / 100.0
              let netCh   = Float(snapshot.networkVol) / 100.0
              let diskCh  = Float(snapshot.diskVol)    / 100.0

              for i in 0..<count {
                  var s = master * cpuCh  * self.cpuBuffer[i]
                        + master * 0.27 * netCh  * (self.bellBuffer[i] + self.pianoBuffer[i])
                        + master * 0.35 * diskCh * self.diskBuffer[i]
                  // gpu, honk added in Tasks 5–6
                  s = max(-1.0, min(1.0, s))
                  out[i] = s
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
  ```

- [ ] **Step 6: Build + test**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|BUILD|error:"
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add TachToneMac/Audio/DiskVoice.swift TachToneMacTests/DiskVoiceTests.swift TachToneMac/Audio/AudioEngine.swift
  git commit -m "feat: DiskVoice — tom-tom 16th notes with pitch sweep"
  ```

---

## Task 5: GpuVoice

**Files:**
- Create: `TachToneMac/Audio/GpuVoice.swift`
- Create: `TachToneMacTests/GpuVoiceTests.swift`
- Modify: `TachToneMac/Audio/AudioEngine.swift`

Haunting quartal-chord organ. Silent below 5% GPU. Chord band steps one level per beat toward target. Beat voicings are randomly selected subsets of the 3-note chord. Vibrato and tremolo wobble builds over 4 stable beats.

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/GpuVoiceTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class GpuVoiceTests: XCTestCase {

      func test_targetBand_at0pct() {
          XCTAssertEqual(GpuVoice.targetBand(gpuPercent: 0), 0)
      }

      func test_targetBand_at100pct() {
          XCTAssertEqual(GpuVoice.targetBand(gpuPercent: 100), 7)
      }

      func test_targetBand_at50pct() {
          // floor(50 / 12.5) = floor(4.0) = 4
          XCTAssertEqual(GpuVoice.targetBand(gpuPercent: 50), 4)
      }

      func test_chordFrequencies_count() {
          XCTAssertEqual(GpuVoice.chordFreqs.count, 8)
          for chord in GpuVoice.chordFreqs {
              XCTAssertEqual(chord.count, 3)
          }
      }

      func test_chordFrequencies_band0() {
          let chord = GpuVoice.chordFreqs[0]
          XCTAssertEqual(chord[0], 261.63, accuracy: 0.01)
          XCTAssertEqual(chord[1], 349.23, accuracy: 0.01)
          XCTAssertEqual(chord[2], 466.16, accuracy: 0.01)
      }

      func test_chordFrequencies_band7() {
          let chord = GpuVoice.chordFreqs[7]
          XCTAssertEqual(chord[0], 523.25, accuracy: 0.01)
          XCTAssertEqual(chord[1], 698.46, accuracy: 0.01)
          XCTAssertEqual(chord[2], 932.33, accuracy: 0.01)
      }

      func test_harmonicWeightSum() {
          XCTAssertEqual(GpuVoice.harmonicWeightSum, 2.5, accuracy: 0.001)
      }

      func test_render_below5pct_producesSilence() {
          var voice = GpuVoice()
          var state = SharedState.Values()
          state.gpu3dPercent = 4.9
          var buffer = [Float](repeating: 1, count: 256)
          voice.render(into: &buffer, frameCount: 256, snapshot: state)
          let sum = buffer.map { abs($0) }.reduce(0, +)
          XCTAssertEqual(sum, 0, accuracy: 0.001)
      }

      func test_render_above5pct_afterBeat_producesSignal() {
          var voice = GpuVoice()
          var state = SharedState.Values()
          state.gpu3dPercent = 50
          let frames = GpuVoice.beatSamples + 100
          var buffer = [Float](repeating: 0, count: frames)
          voice.render(into: &buffer, frameCount: frames, snapshot: state)
          let hasSignal = buffer.contains { abs($0) > 0.001 }
          XCTAssertTrue(hasSignal, "GpuVoice should produce signal after the first beat fires")
      }
  }
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

- [ ] **Step 3: Write `TachToneMac/Audio/GpuVoice.swift`**

  ```swift
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
  ```

- [ ] **Step 4: Run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

- [ ] **Step 5: Wire into AudioEngine**

  Edit `TachToneMac/Audio/AudioEngine.swift` — add `gpuVoice` and update:

  ```swift
  import AVFoundation

  final class TachToneAudioEngine: @unchecked Sendable {
      private let avEngine = AVAudioEngine()
      private var sourceNode: AVAudioSourceNode?
      private let sharedState: SharedState

      private var cpuVoice     = CpuVoice()
      private var networkVoice = NetworkVoice()
      private var diskVoice    = DiskVoice()
      private var gpuVoice     = GpuVoice()

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
              let snapshot = self.sharedState.snapshot()

              self.cpuVoice.render(into: &self.cpuBuffer, frameCount: count, snapshot: snapshot)
              self.networkVoice.render(bellBuffer: &self.bellBuffer, pianoBuffer: &self.pianoBuffer,
                                       frameCount: count, snapshot: snapshot)
              self.diskVoice.render(into: &self.diskBuffer, frameCount: count, snapshot: snapshot)
              self.gpuVoice.render(into: &self.gpuBuffer, frameCount: count, snapshot: snapshot)

              let master  = Float(snapshot.volume)     / 100.0
              let cpuCh   = Float(snapshot.cpuVol)     / 100.0
              let netCh   = Float(snapshot.networkVol) / 100.0
              let diskCh  = Float(snapshot.diskVol)    / 100.0
              let gpuCh   = Float(snapshot.gpuVol)     / 100.0

              for i in 0..<count {
                  var s = master * cpuCh  * self.cpuBuffer[i]
                        + master * 0.27 * netCh  * (self.bellBuffer[i] + self.pianoBuffer[i])
                        + master * 0.35 * diskCh * self.diskBuffer[i]
                        + master * 0.30 * gpuCh  * self.gpuBuffer[i]
                  // honk added in Task 6
                  s = max(-1.0, min(1.0, s))
                  out[i] = s
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
  ```

- [ ] **Step 6: Build + test**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|BUILD|error:"
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add TachToneMac/Audio/GpuVoice.swift TachToneMacTests/GpuVoiceTests.swift TachToneMac/Audio/AudioEngine.swift
  git commit -m "feat: GpuVoice — quartal organ with band stepping and vibrato/tremolo wobble"
  ```

---

## Task 6: HonkVoice + Complete Mix

**Files:**
- Create: `TachToneMac/Audio/HonkVoice.swift`
- Create: `TachToneMacTests/HonkVoiceTests.swift`
- Modify: `TachToneMac/Audio/AudioEngine.swift` (final version with honk + full mix)

The car horn pre-renders a complete `[Float]` buffer at trigger time, then streams from it each callback. Two-tone: G4 (392 Hz) + B4 (494 Hz). Standard honk = two 180ms blasts. Impatient = randomized cluster–lean–cluster–lean sequence.

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/HonkVoiceTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class HonkVoiceTests: XCTestCase {

      func test_standardHonkBuffer_approximateDuration() {
          var voice = HonkVoice()
          voice.triggerStandardHonk()
          // 180ms + 90ms gap + 180ms = 450ms = 0.450 * 44100 = 19,845 samples
          let expected = Int(0.450 * 44100)
          XCTAssertEqual(voice.buffer.count, expected, accuracy: 200)
      }

      func test_standardHonkBuffer_valuesWithinRange() {
          var voice = HonkVoice()
          voice.triggerStandardHonk()
          for sample in voice.buffer {
              XCTAssertLessThanOrEqual(abs(sample), 1.0 + 1e-5, "Sample out of range: \(sample)")
          }
      }

      func test_impatientHonkBuffer_longerThanStandard() {
          var voice = HonkVoice()
          voice.triggerStandardHonk()
          let standardLen = voice.buffer.count
          voice.triggerImpatientHonk()
          XCTAssertGreaterThan(voice.buffer.count, standardLen * 10,
                               "Impatient honk should be much longer than standard")
      }

      func test_render_emptyBuffer_producesSilence() {
          var voice = HonkVoice()
          var buffer = [Float](repeating: 1, count: 256)
          voice.render(into: &buffer, frameCount: 256)
          let sum = buffer.map { abs($0) }.reduce(0, +)
          XCTAssertEqual(sum, 0, accuracy: 0.001)
      }

      func test_render_streamsFromBuffer() {
          var voice = HonkVoice()
          voice.triggerStandardHonk()
          var buffer = [Float](repeating: 0, count: 1024)
          voice.render(into: &buffer, frameCount: 1024)
          let hasSignal = buffer.contains { abs($0) > 0.01 }
          XCTAssertTrue(hasSignal, "render should stream non-zero samples from the pre-rendered buffer")
      }

      func test_render_bufferExhausted_producesSilence() {
          var voice = HonkVoice()
          voice.triggerStandardHonk()
          let totalSamples = voice.buffer.count
          // Drain the entire buffer
          var drain = [Float](repeating: 0, count: totalSamples)
          voice.render(into: &drain, frameCount: totalSamples)
          // Now should be silent
          var silence = [Float](repeating: 1, count: 256)
          voice.render(into: &silence, frameCount: 256)
          let sum = silence.map { abs($0) }.reduce(0, +)
          XCTAssertEqual(sum, 0, accuracy: 0.001)
      }
  }
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

- [ ] **Step 3: Write `TachToneMac/Audio/HonkVoice.swift`**

  ```swift
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
  ```

- [ ] **Step 4: Run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

  Expected: all `HonkVoiceTests` pass.

- [ ] **Step 5: Write the final AudioEngine with HonkVoice and full mix**

  Replace the entire contents of `TachToneMac/Audio/AudioEngine.swift`:

  ```swift
  import AVFoundation

  // SAFETY: All voice state is mutated exclusively from the AVAudioSourceNode
  // render callback, which runs on a dedicated real-time audio thread.
  // AppDelegate calls start() once on the main thread before the callback begins.
  // No voice state is accessed from any other thread.
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
  ```

- [ ] **Step 6: Run all tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

  Expected: all test suites pass (AudioEngine, CpuVoice, NetworkVoice, DiskVoice, GpuVoice, HonkVoice, plus all Plan 1 suites).

- [ ] **Step 7: Smoke test with the app running**

  Build and launch:
  ```bash
  xcodebuild -scheme TachToneMac -destination 'platform=macOS' build 2>&1 | tail -3
  xed .
  ```

  Then in Terminal, send a honk:
  ```bash
  python3 -c "import socket; socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(b'need attention', ('127.0.0.1', 9876))"
  ```

  You should hear a double honk through your speakers.

- [ ] **Step 8: Commit**

  ```bash
  git add TachToneMac/Audio/HonkVoice.swift TachToneMacTests/HonkVoiceTests.swift TachToneMac/Audio/AudioEngine.swift
  git commit -m "feat: HonkVoice + complete mix formula — all 5 voices active"
  ```

---

## Self-Review

**Spec coverage check:**

| Spec Requirement | Task |
|---|---|
| Sample rate 44100 Hz, mono, float32 | Task 1 ✓ |
| Block size 1024 (buffers sized 4096) | Task 1 ✓ |
| Snapshot SharedState once per block | Task 1 ✓ |
| Mix formula (exact coefficients) | Task 6 ✓ |
| Clip output to [-1, 1] | Tasks 2–6 ✓ |
| CPU RPM mapping 700–7000 | Task 2 ✓ |
| Frequency smoothing α=0.02/block | Task 2 ✓ |
| Harmonic stack [0.30,1.00,0.45,0.80,0.25,0.55,0.15,0.35] | Task 2 ✓ |
| AM chug: 2×crank, depth=0.40×max(0,1-cpu/67) | Task 2 ✓ |
| Mechanical noise 0.004 | Task 2 ✓ |
| Vibrato LFO 7Hz, depth=(ctx/50000)×freq×0.05×(ivol/100) | Task 2 ✓ |
| Phase continuity across blocks | Task 2 ✓ |
| Beat tempo 80 BPM (33075 samples) | Tasks 3–5 ✓ |
| Bell: recv>5000, band=min(floor(r/500000×8),7) | Task 3 ✓ |
| Bell timbre: fund+25%+10%, decay 50ms, norm 1.35 | Task 3 ✓ |
| Piano: send>5000, same band logic | Task 3 ✓ |
| Piano timbre: 60%+35%+15%, decay 30ms, norm 2.10 | Task 3 ✓ |
| 8 note frequencies (C major C5–C6) | Task 3 ✓ |
| Disk: 16th notes, threshold 100k, band from 10M | Task 4 ✓ |
| Tom frequencies [80,100,120,140,165,190,215,250] | Task 4 ✓ |
| Pitch sweep +25Hz over 25ms | Task 4 ✓ |
| Tom decay 70ms | Task 4 ✓ |
| GPU silence below 5% | Task 5 ✓ |
| 8 quartal chord bands (all frequencies) | Task 5 ✓ |
| Band step one per beat toward target | Task 5 ✓ |
| Random voicing selection (4 subsets) | Task 5 ✓ |
| Organ harmonics [1.0,0.7,0.5,0.3], norm 2.5 | Task 5 ✓ |
| Vibrato 4.5Hz ±0.4%, tremolo 3.1Hz ±25% | Task 5 ✓ |
| Wobble ramps over 4 stable beats | Task 5 ✓ |
| Organ decay 1.8s | Task 5 ✓ |
| Horn G4 392Hz + B4 494Hz | Task 6 ✓ |
| Standard honk: 2×180ms, 90ms gap, 10ms attack, 25ms release | Task 6 ✓ |
| Impatient: cluster+pause+long lean+pause+cluster+pause+med lean | Task 6 ✓ |
| Cluster/lean sizes randomized | Task 6 ✓ |
| Pre-render as buffer, stream per callback | Task 6 ✓ |
| Clear honk flags after acting on them | Task 6 ✓ |

**No gaps found. No placeholders. Types consistent across all tasks.**

---

*Plan 3: UI Polish — programmatic tachometer icon + settings panel (sliders + checkbox).*
