import XCTest
@testable import TachToneMac

final class AppDelegateTests: XCTestCase {

    func test_openSettings_createsWindow() {
        let delegate = AppDelegate()
        XCTAssertNil(delegate.settingsWindow)
        delegate.openSettings()
        XCTAssertNotNil(delegate.settingsWindow)
    }

    func test_openSettings_calledTwice_reusesSameWindow() {
        let delegate = AppDelegate()
        delegate.openSettings()
        let first = delegate.settingsWindow
        delegate.openSettings()
        let second = delegate.settingsWindow
        XCTAssertTrue(first === second, "openSettings should reuse the same NSWindow")
    }
}
