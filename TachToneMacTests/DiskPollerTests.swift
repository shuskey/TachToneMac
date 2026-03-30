import XCTest
@testable import TachToneMac

final class DiskPollerTests: XCTestCase {

    func test_diskRate_isNonNegative() throws {
        let state = SharedState()
        let poller = DiskPoller(state: state)
        try poller.pollOnce()
        Thread.sleep(forTimeInterval: 0.1)
        try poller.pollOnce()
        XCTAssertGreaterThanOrEqual(state.snapshot().diskRate, 0.0)
    }

    func test_computeRate_normalDelta() {
        let rate = DiskPoller.bytesPerSec(prevRead: 0, prevWrite: 0,
                                           currRead: 1000, currWrite: 500,
                                           elapsed: 0.5)
        XCTAssertEqual(rate, 3000.0, accuracy: 0.1)  // (1500 bytes) / 0.5s
    }

    func test_computeRate_counterWrap_clampedToZero() {
        let rate = DiskPoller.bytesPerSec(prevRead: 5000, prevWrite: 0,
                                           currRead: 100, currWrite: 0,
                                           elapsed: 0.5)
        XCTAssertEqual(rate, 0.0)
    }

    func test_computeRate_zeroElapsed_returnsZero() {
        let rate = DiskPoller.bytesPerSec(prevRead: 0, prevWrite: 0,
                                           currRead: 1000, currWrite: 500,
                                           elapsed: 0.0)
        XCTAssertEqual(rate, 0.0)
    }
}
