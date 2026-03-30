import XCTest
@testable import TachToneMac

final class NetworkPollerTests: XCTestCase {

    func test_rates_areNonNegative() throws {
        let state = SharedState()
        let poller = NetworkPoller(state: state)
        // First poll sets baseline
        try poller.pollOnce()
        Thread.sleep(forTimeInterval: 0.1)
        try poller.pollOnce()
        let s = state.snapshot()
        XCTAssertGreaterThanOrEqual(s.netRecvRate, 0.0)
        XCTAssertGreaterThanOrEqual(s.netSendRate, 0.0)
    }

    func test_computeRate_normalDelta() {
        let rate = NetworkPoller.bytesPerSec(prev: 1000, current: 2000, elapsed: 0.5)
        XCTAssertEqual(rate, 2000.0, accuracy: 0.1)
    }

    func test_computeRate_counterWrap_clampedToZero() {
        // current < prev → counter reset → clamp to 0
        let rate = NetworkPoller.bytesPerSec(prev: 5000, current: 100, elapsed: 0.5)
        XCTAssertEqual(rate, 0.0)
    }

    func test_computeRate_zeroElapsed_returnsZero() {
        let rate = NetworkPoller.bytesPerSec(prev: 0, current: 1000, elapsed: 0.0)
        XCTAssertEqual(rate, 0.0)
    }
}
