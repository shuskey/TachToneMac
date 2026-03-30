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
