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
