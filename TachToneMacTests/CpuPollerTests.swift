import XCTest
@testable import TachToneMac

final class CpuPollerTests: XCTestCase {

    func test_cpuPercent_isInValidRange() throws {
        let state = SharedState()
        let poller = CpuPoller(state: state)
        try poller.pollOnce()
        let pct = state.snapshot().cpuPercent
        XCTAssertGreaterThanOrEqual(pct, 0.0)
        XCTAssertLessThanOrEqual(pct, 100.0)
    }

    func test_ctxRate_isNonNegative() throws {
        let state = SharedState()
        let poller = CpuPoller(state: state)
        // First poll initializes baseline
        try poller.pollOnce()
        // Second poll computes delta
        Thread.sleep(forTimeInterval: 0.1)
        try poller.pollOnce()
        XCTAssertGreaterThanOrEqual(state.snapshot().ctxRate, 0.0)
    }

    func test_computeCpuPercent_fromTicks() {
        let idle: UInt64 = 500
        let total: UInt64 = 1000
        let pct = CpuPoller.cpuPercent(idleTicks: idle, totalTicks: total)
        XCTAssertEqual(pct, 50.0, accuracy: 0.01)
    }

    func test_computeCpuPercent_allIdle() {
        let pct = CpuPoller.cpuPercent(idleTicks: 1000, totalTicks: 1000)
        XCTAssertEqual(pct, 0.0, accuracy: 0.01)
    }

    func test_computeCpuPercent_noneIdle() {
        let pct = CpuPoller.cpuPercent(idleTicks: 0, totalTicks: 1000)
        XCTAssertEqual(pct, 100.0, accuracy: 0.01)
    }
}
