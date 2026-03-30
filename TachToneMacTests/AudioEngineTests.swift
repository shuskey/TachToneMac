import XCTest
import AVFoundation
@testable import TachToneMac

final class AudioEngineTests: XCTestCase {

    func test_start_doesNotThrow() throws {
        let state = SharedState()
        let engine = TachToneAudioEngine(state: state)
        try engine.start()
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
