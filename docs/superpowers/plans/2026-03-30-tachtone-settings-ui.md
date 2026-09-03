# TachTone macOS — Settings UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a programmatic Settings panel to the menu bar app with per-channel volume sliders and an impatient-honking checkbox.

**Architecture:** `SettingsViewController` (NSViewController, programmatic UI, no NIB) owns six `NSSlider` instances and one `NSButton` checkbox. It reads initial values from `SharedState` on appear and writes back on every control change. `AppDelegate` creates the view controller on demand, wraps it in a reusable `NSWindow`, and exposes it from a new "Settings…" menu item.

**Tech Stack:** Swift 6, AppKit (`NSViewController`, `NSStackView`, `NSSlider`, `NSButton`, `NSWindow`), XCTest

---

## File Structure

```
TachToneMac/UI/
└── SettingsViewController.swift   ← programmatic UI, reads/writes SharedState

TachToneMacTests/
└── SettingsViewControllerTests.swift

Modified:
TachToneMac/App/AppDelegate.swift  ← adds Settings… menu item + window management
```

---

## Task 1: SettingsViewController

**Files:**
- Create: `TachToneMac/UI/SettingsViewController.swift`
- Create: `TachToneMacTests/SettingsViewControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/SettingsViewControllerTests.swift`:

  ```swift
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
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: build error — `SettingsViewController` not found.

- [ ] **Step 3: Write `TachToneMac/UI/SettingsViewController.swift`**

  ```swift
  import AppKit

  final class SettingsViewController: NSViewController {
      private let sharedState: SharedState

      // Internal for testing
      var masterSlider:      NSSlider!
      var cpuSlider:         NSSlider!
      var networkSlider:     NSSlider!
      var diskSlider:        NSSlider!
      var gpuSlider:         NSSlider!
      var honkSlider:        NSSlider!
      var impatientCheckbox: NSButton!

      // Maps each slider to its numeric readout label
      private var valueLabels: [NSSlider: NSTextField] = [:]

      init(state: SharedState) {
          self.sharedState = state
          super.init(nibName: nil, bundle: nil)
      }

      required init?(coder: NSCoder) { fatalError("use init(state:)") }

      override func loadView() {
          view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 300))
      }

      override func viewDidLoad() {
          super.viewDidLoad()
          buildUI()
          loadValues()
      }

      // Refresh values every time the panel becomes visible
      override func viewWillAppear() {
          super.viewWillAppear()
          loadValues()
      }

      // MARK: - Build UI

      private func buildUI() {
          let stack = NSStackView()
          stack.orientation = .vertical
          stack.alignment = .leading
          stack.spacing = 10
          stack.translatesAutoresizingMaskIntoConstraints = false
          view.addSubview(stack)
          NSLayoutConstraint.activate([
              stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
              stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
              stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
          ])

          masterSlider  = makeSlider()
          cpuSlider     = makeSlider()
          networkSlider = makeSlider()
          diskSlider    = makeSlider()
          gpuSlider     = makeSlider()
          honkSlider    = makeSlider()

          let rows: [(String, NSSlider)] = [
              ("Master",  masterSlider),
              ("CPU",     cpuSlider),
              ("Network", networkSlider),
              ("Disk",    diskSlider),
              ("GPU",     gpuSlider),
              ("Honk",    honkSlider),
          ]
          for (label, slider) in rows {
              stack.addArrangedSubview(makeRow(label: label, slider: slider))
          }

          impatientCheckbox = NSButton(checkboxWithTitle: "Impatient honking",
                                       target: self, action: #selector(checkboxChanged(_:)))
          stack.addArrangedSubview(impatientCheckbox)
      }

      private func makeSlider() -> NSSlider {
          let s = NSSlider(value: 50, minValue: 0, maxValue: 100,
                           target: self, action: #selector(sliderChanged(_:)))
          s.isContinuous = true
          return s
      }

      private func makeRow(label: String, slider: NSSlider) -> NSView {
          let row = NSStackView()
          row.orientation = .horizontal
          row.spacing = 8

          let lbl = NSTextField(labelWithString: label + ":")
          lbl.frame.size.width = 70
          lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

          let valLbl = NSTextField(labelWithString: "50")
          valLbl.alignment = .right
          valLbl.frame.size.width = 32
          valLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          valueLabels[slider] = valLbl

          row.addArrangedSubview(lbl)
          row.addArrangedSubview(slider)
          row.addArrangedSubview(valLbl)
          return row
      }

      // MARK: - Load / Save

      private func loadValues() {
          let s = sharedState.snapshot()
          apply(masterSlider,  value: s.volume)
          apply(cpuSlider,     value: s.cpuVol)
          apply(networkSlider, value: s.networkVol)
          apply(diskSlider,    value: s.diskVol)
          apply(gpuSlider,     value: s.gpuVol)
          apply(honkSlider,    value: s.honkVol)
          impatientCheckbox.state = s.impatientHonkingEnabled ? .on : .off
      }

      private func apply(_ slider: NSSlider, value: Int) {
          slider.integerValue = value
          valueLabels[slider]?.stringValue = "\(value)"
      }

      // MARK: - Actions

      @objc func sliderChanged(_ sender: NSSlider) {
          let val = sender.integerValue
          valueLabels[sender]?.stringValue = "\(val)"
          sharedState.update { s in
              if sender === self.masterSlider       { s.volume     = val }
              else if sender === self.cpuSlider     { s.cpuVol     = val }
              else if sender === self.networkSlider { s.networkVol = val }
              else if sender === self.diskSlider    { s.diskVol    = val }
              else if sender === self.gpuSlider     { s.gpuVol     = val }
              else if sender === self.honkSlider    { s.honkVol    = val }
          }
      }

      @objc func checkboxChanged(_ sender: NSButton) {
          sharedState.update { $0.impatientHonkingEnabled = sender.state == .on }
      }
  }
  ```

- [ ] **Step 4: Run xcodegen + run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

  Expected: all `SettingsViewControllerTests` pass (12 tests). All prior suites pass.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/shuskey/github/TachToneMac
  git add TachToneMac/UI/SettingsViewController.swift TachToneMacTests/SettingsViewControllerTests.swift
  git commit -m "feat: SettingsViewController — volume sliders + impatient honking checkbox"
  ```

---

## Task 2: AppDelegate Wiring

**Files:**
- Modify: `TachToneMac/App/AppDelegate.swift`

- [ ] **Step 1: Write the failing test**

  Add to an existing or new `AppDelegateTests.swift` file — check if `TachToneMacTests/AppDelegateTests.swift` exists; if not, create it:

  ```swift
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
  ```

- [ ] **Step 2: Run xcodegen + confirm tests fail**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodegen generate && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD"
  ```

  Expected: build error — `settingsWindow` and `openSettings` not found on `AppDelegate`.

- [ ] **Step 3: Replace `TachToneMac/App/AppDelegate.swift`**

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem!
      private let sharedState = SharedState()
      private lazy var cpuPoller     = CpuPoller(state: sharedState)
      private lazy var networkPoller = NetworkPoller(state: sharedState)
      private lazy var diskPoller    = DiskPoller(state: sharedState)
      private lazy var gpuPoller     = GpuPoller(state: sharedState)
      private lazy var honkListener  = HonkListener(state: sharedState)
      private lazy var audioEngine   = TachToneAudioEngine(state: sharedState)

      // Internal for testing
      var settingsWindow: NSWindow?

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button { button.title = "T" }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
          menu.addItem(.separator())
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu

          cpuPoller.start()
          networkPoller.start()
          diskPoller.start()
          gpuPoller.start()
          honkListener.start()
          try? audioEngine.start()
      }

      @objc func openSettings() {
          if settingsWindow == nil {
              let vc = SettingsViewController(state: sharedState)
              let window = NSWindow(contentViewController: vc)
              window.title = "TachTone Settings"
              window.styleMask = [.titled, .closable]
              window.isReleasedWhenClosed = false
              settingsWindow = window
          }
          settingsWindow?.makeKeyAndOrderFront(nil)
          NSApp.activate(ignoringOtherApps: true)
      }

      @objc private func quit() {
          audioEngine.stop()
          NSApp.terminate(nil)
      }
  }
  ```

- [ ] **Step 4: Run tests**

  ```bash
  cd /Users/shuskey/github/TachToneMac && xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "Test Suite.*passed|Test Suite.*failed|BUILD|error:"
  ```

  Expected: `AppDelegateTests` passes (2 tests). All prior suites pass.

- [ ] **Step 5: Build to verify**

  ```bash
  xcodebuild -scheme TachToneMac -destination 'platform=macOS' build 2>&1 | tail -3
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Smoke test**

  Build and run. Click the **T** in the menu bar. You should see:
  - **Settings…** (⌘,)
  - A separator line
  - **Quit TachTone** (⌘Q)

  Click **Settings…** — a floating window should appear with 6 labeled sliders (Master, CPU, Network, Disk, GPU, Honk) and an "Impatient honking" checkbox. Drag a slider and confirm the numeric readout updates. Close and re-open — slider values should persist.

- [ ] **Step 7: Commit**

  ```bash
  cd /Users/shuskey/github/TachToneMac
  git add TachToneMac/App/AppDelegate.swift TachToneMacTests/AppDelegateTests.swift
  git commit -m "feat: Settings menu item + window — volume sliders accessible from menu bar"
  ```

---

## Self-Review

**Spec coverage:**
- ✅ Master volume slider
- ✅ CPU, Network, Disk, GPU, Honk per-channel sliders
- ✅ Impatient honking checkbox
- ✅ Accessible from "T" menu bar item
- ✅ Values read from SharedState on open, written back on change

**Placeholder scan:** No TBDs, no "add appropriate handling" language — all code is complete.

**Type consistency:** `SettingsViewController` uses `var masterSlider: NSSlider!` throughout. `AppDelegate` uses `var settingsWindow: NSWindow?` consistently. `openSettings()` is spelled consistently in both the test and the implementation.
