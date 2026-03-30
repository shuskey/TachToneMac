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
