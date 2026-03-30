import XCTest
@testable import TachToneMac

final class SharedStateTests: XCTestCase {

    func test_defaultValues() {
        let state = SharedState()
        let s = state.snapshot()
        XCTAssertEqual(s.cpuPercent, 0.0)
        XCTAssertEqual(s.ctxRate, 0.0)
        XCTAssertEqual(s.netRecvRate, 0.0)
        XCTAssertEqual(s.netSendRate, 0.0)
        XCTAssertEqual(s.diskRate, 0.0)
        XCTAssertEqual(s.gpu3dPercent, 0.0)
        XCTAssertEqual(s.volume, 50)
        XCTAssertEqual(s.cpuVol, 80)
        XCTAssertEqual(s.interruptsVol, 12)
        XCTAssertEqual(s.networkVol, 50)
        XCTAssertEqual(s.diskVol, 50)
        XCTAssertEqual(s.gpuVol, 50)
        XCTAssertEqual(s.honkVol, 100)
        XCTAssertFalse(s.honk)
        XCTAssertFalse(s.impatientHonk)
        XCTAssertTrue(s.impatientHonkingEnabled)
    }

    func test_updateAndSnapshot() {
        let state = SharedState()
        state.update { $0.cpuPercent = 42.5 }
        XCTAssertEqual(state.snapshot().cpuPercent, 42.5)
    }

    func test_clearHonkFlags() {
        let state = SharedState()
        state.update { $0.honk = true; $0.impatientHonk = true }
        state.clearHonkFlags()
        let s = state.snapshot()
        XCTAssertFalse(s.honk)
        XCTAssertFalse(s.impatientHonk)
    }

    func test_concurrentWrites_doNotCrash() {
        let state = SharedState()
        let group = DispatchGroup()
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                state.update { $0.cpuPercent = Float(i) }
                _ = state.snapshot()
                group.leave()
            }
        }
        group.wait()
        // no crash = pass
    }
}
