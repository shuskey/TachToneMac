import XCTest
@testable import TachToneMac

final class GpuPollerTests: XCTestCase {

    func test_gpuPercent_isInValidRange() {
        let state = SharedState()
        let poller = GpuPoller(state: state)
        poller.pollOnce()
        let pct = state.snapshot().gpu3dPercent
        XCTAssertGreaterThanOrEqual(pct, 0.0)
        XCTAssertLessThanOrEqual(pct, 100.0)
    }

    func test_gpuPercent_doesNotCrashOnMissingData() {
        // GpuPoller must default to 0.0 if IOKit returns nothing
        let state = SharedState()
        let poller = GpuPoller(state: state)
        for _ in 0..<5 { poller.pollOnce() }
        XCTAssertGreaterThanOrEqual(state.snapshot().gpu3dPercent, 0.0)
    }

    func test_parsePercent_fromDictionary_deviceUtilization() {
        let dict: [String: Any] = ["Device Utilization %": 42]
        let pct = GpuPoller.parseUtilization(from: dict)
        XCTAssertEqual(pct, 42.0, accuracy: 0.01)
    }

    func test_parsePercent_fromDictionary_gpuActivity() {
        let dict: [String: Any] = ["GPU Activity(%)": 75]
        let pct = GpuPoller.parseUtilization(from: dict)
        XCTAssertEqual(pct, 75.0, accuracy: 0.01)
    }

    func test_parsePercent_missingKey_returnsZero() {
        let pct = GpuPoller.parseUtilization(from: [:])
        XCTAssertEqual(pct, 0.0)
    }

    func test_parsePercent_floatValue() {
        let dict: [String: Any] = ["Device Utilization %": Float(33.5)]
        let pct = GpuPoller.parseUtilization(from: dict)
        XCTAssertEqual(pct, 33.5, accuracy: 0.01)
    }
}
