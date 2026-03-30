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
