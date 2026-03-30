import XCTest
@testable import TachToneMac

final class SettingsViewControllerTests: XCTestCase {

    func test_viewDidLoad_setsSliderValuesFromState() {
        let state = SharedState()
        state.update { $0.volume = 75; $0.cpuVol = 60; $0.networkVol = 40 }
        let vc = SettingsViewController(state: state)
        _ = vc.view  // triggers viewDidLoad
        XCTAssertEqual(vc.masterSlider.integerValue, 75)
        XCTAssertEqual(vc.cpuSlider.integerValue, 60)
        XCTAssertEqual(vc.networkSlider.integerValue, 40)
    }

    func test_viewDidLoad_setsRemainingSliders() {
        let state = SharedState()
        state.update { $0.diskVol = 33; $0.gpuVol = 22; $0.honkVol = 11 }
        let vc = SettingsViewController(state: state)
        _ = vc.view
        XCTAssertEqual(vc.diskSlider.integerValue, 33)
        XCTAssertEqual(vc.gpuSlider.integerValue, 22)
        XCTAssertEqual(vc.honkSlider.integerValue, 11)
    }

    func test_viewDidLoad_setsCheckboxOn_whenEnabled() {
        let state = SharedState()
        state.update { $0.impatientHonkingEnabled = true }
        let vc = SettingsViewController(state: state)
        _ = vc.view
        XCTAssertEqual(vc.impatientCheckbox.state, .on)
    }

    func test_viewDidLoad_setsCheckboxOff_whenDisabled() {
        let state = SharedState()
        state.update { $0.impatientHonkingEnabled = false }
        let vc = SettingsViewController(state: state)
        _ = vc.view
        XCTAssertEqual(vc.impatientCheckbox.state, .off)
    }

    func test_masterSliderChange_updatesState() {
        let state = SharedState()
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.masterSlider.integerValue = 80
        vc.sliderChanged(vc.masterSlider)
        XCTAssertEqual(state.snapshot().volume, 80)
    }

    func test_cpuSliderChange_updatesState() {
        let state = SharedState()
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.cpuSlider.integerValue = 45
        vc.sliderChanged(vc.cpuSlider)
        XCTAssertEqual(state.snapshot().cpuVol, 45)
    }

    func test_networkSliderChange_updatesState() {
        let state = SharedState()
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.networkSlider.integerValue = 33
        vc.sliderChanged(vc.networkSlider)
        XCTAssertEqual(state.snapshot().networkVol, 33)
    }

    func test_diskSliderChange_updatesState() {
        let state = SharedState()
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.diskSlider.integerValue = 22
        vc.sliderChanged(vc.diskSlider)
        XCTAssertEqual(state.snapshot().diskVol, 22)
    }

    func test_gpuSliderChange_updatesState() {
        let state = SharedState()
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.gpuSlider.integerValue = 11
        vc.sliderChanged(vc.gpuSlider)
        XCTAssertEqual(state.snapshot().gpuVol, 11)
    }

    func test_honkSliderChange_updatesState() {
        let state = SharedState()
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.honkSlider.integerValue = 0
        vc.sliderChanged(vc.honkSlider)
        XCTAssertEqual(state.snapshot().honkVol, 0)
    }

    func test_checkboxOff_disablesImpatientHonking() {
        let state = SharedState()
        state.update { $0.impatientHonkingEnabled = true }
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.impatientCheckbox.state = .off
        vc.checkboxChanged(vc.impatientCheckbox)
        XCTAssertFalse(state.snapshot().impatientHonkingEnabled)
    }

    func test_checkboxOn_enablesImpatientHonking() {
        let state = SharedState()
        state.update { $0.impatientHonkingEnabled = false }
        let vc = SettingsViewController(state: state)
        _ = vc.view
        vc.impatientCheckbox.state = .on
        vc.checkboxChanged(vc.impatientCheckbox)
        XCTAssertTrue(state.snapshot().impatientHonkingEnabled)
    }
}
