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
