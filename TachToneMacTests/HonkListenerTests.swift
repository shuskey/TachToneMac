import XCTest
@testable import TachToneMac

final class HonkListenerTests: XCTestCase {

    func test_needAttention_triggersHonkAndStartsTimer() {
        let state = SharedState()
        let listener = HonkListener(state: state)
        listener.handleDatagram("need attention")
        XCTAssertTrue(state.snapshot().honk)
        XCTAssertTrue(listener.impatientTimerActive)
    }

    func test_gotAttention_cancelsTimers() {
        let state = SharedState()
        let listener = HonkListener(state: state)
        listener.handleDatagram("need attention")
        listener.handleDatagram("got attention")
        XCTAssertFalse(listener.impatientTimerActive)
        XCTAssertFalse(listener.approvalTimerActive)
    }

    func test_taskComplete_cancelsTimersAndHonks() {
        let state = SharedState()
        let listener = HonkListener(state: state)
        listener.handleDatagram("need attention")
        state.update { $0.honk = false }   // clear so we can detect the re-trigger
        listener.handleDatagram("claude task complete")
        XCTAssertTrue(state.snapshot().honk)
        XCTAssertFalse(listener.impatientTimerActive)
    }

    func test_preToolUse_cancelsImpatientStartsApproval() {
        let state = SharedState()
        let listener = HonkListener(state: state)
        listener.handleDatagram("need attention")
        listener.handleDatagram("pre_tool_use")
        XCTAssertFalse(listener.impatientTimerActive)
        XCTAssertTrue(listener.approvalTimerActive)
    }

    func test_postToolUse_cancelsApprovalTimer() {
        let state = SharedState()
        let listener = HonkListener(state: state)
        listener.handleDatagram("pre_tool_use")
        listener.handleDatagram("post_tool_use")
        XCTAssertFalse(listener.approvalTimerActive)
    }

    func test_unknownDatagram_isIgnored() {
        let state = SharedState()
        let listener = HonkListener(state: state)
        listener.handleDatagram("garbage xyz")
        XCTAssertFalse(state.snapshot().honk)
        XCTAssertFalse(listener.impatientTimerActive)
    }

    func test_impatientHonkingDisabled_timerDoesNotSetFlag() {
        let state = SharedState()
        state.update { $0.impatientHonkingEnabled = false }
        let listener = HonkListener(state: state)
        listener.handleDatagram("need attention")
        // Fire the timer manually (don't wait 30s)
        listener.fireImpatientTimerForTesting()
        XCTAssertFalse(state.snapshot().impatientHonk)
    }
}
