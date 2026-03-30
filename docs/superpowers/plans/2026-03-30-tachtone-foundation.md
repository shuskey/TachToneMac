# TachTone macOS — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a running macOS menu bar app that reads live CPU, network, disk, and GPU metrics every 500ms, listens on UDP for Claude Code signals, and exposes all data through a thread-safe SharedState — no audio yet, just the data pipeline.

**Architecture:** A menu bar–only SwiftUI/AppKit hybrid app (`LSUIElement = true`) with a Swift `actor` as the thread-safe SharedState. Four background pollers write into SharedState every 500ms using `Task { }` async loops. A HonkListener binds a UDP socket on port 9876 and processes datagrams. The audio engine (Plan 2) will consume SharedState snapshots.

**Tech Stack:** Swift 6, AppKit (`NSStatusItem`), `mach/mach.h` (CPU), `getifaddrs` (network), IOKit (disk + GPU), `Network.framework` (UDP), XCTest

---

## File Structure

```
TachToneMac/                          ← Xcode project root
├── TachToneMac.xcodeproj/
├── TachToneMac/
│   ├── App/
│   │   ├── AppDelegate.swift         ← NSStatusItem, starts all components, no Dock icon
│   │   └── main.swift                ← Entry point: NSApplicationMain(AppDelegate.self)
│   ├── State/
│   │   └── SharedState.swift         ← Thread-safe class (NSLock) holding all metrics + settings
│   ├── Pollers/
│   │   ├── CpuPoller.swift           ← CPU % + context-switch rate via mach host_statistics
│   │   ├── NetworkPoller.swift       ← bytes/sec in+out via getifaddrs
│   │   ├── DiskPoller.swift          ← disk bytes/sec via IOKit IOStatisticsIterator
│   │   └── GpuPoller.swift           ← GPU 3D % via IOKit IOAccelerator PerformanceStatistics
│   └── Listeners/
│       └── HonkListener.swift        ← UDP NWListener on 127.0.0.1:9876
└── TachToneMacTests/
    ├── SharedStateTests.swift
    ├── CpuPollerTests.swift
    ├── NetworkPollerTests.swift
    ├── DiskPollerTests.swift
    └── HonkListenerTests.swift
```

---

## Task 1: Create Xcode Project

**Files:**
- Create: `TachToneMac.xcodeproj` (via Xcode GUI)
- Modify: `TachToneMac/Info.plist` (add `LSUIElement`)
- Create: `TachToneMac/App/AppDelegate.swift`
- Create: `TachToneMac/App/main.swift`

- [ ] **Step 1: Create project in Xcode**

  Open Xcode → File → New → Project → macOS → App.
  - Product Name: `TachToneMac`
  - Team: Personal (or your dev account)
  - Organization Identifier: `com.yourname`
  - Interface: **SwiftUI** (we'll override it)
  - Language: Swift
  - Uncheck "Include Tests" for now (we'll add the test target manually)
  - Save into `/Users/shuskey/github/TachToneMac/`

- [ ] **Step 2: Delete the auto-generated SwiftUI files**

  In Xcode's project navigator, delete:
  - `ContentView.swift`
  - `TachToneMacApp.swift`
  - `Assets.xcassets` (keep it — we'll use it later for the icon)

  Choose "Move to Trash" when prompted.

- [ ] **Step 3: Add LSUIElement to Info.plist**

  In the project navigator, find `Info.plist` (or click the target → Info tab).
  Add a new key:
  - Key: `Application is agent (UIElement)` (which is `LSUIElement`)
  - Type: Boolean
  - Value: YES

  This hides TachTone from the Dock and App Switcher.

- [ ] **Step 4: Write main.swift**

  Create `TachToneMac/App/main.swift`:

  ```swift
  import AppKit

  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  app.run()
  ```

- [ ] **Step 5: Write AppDelegate.swift**

  Create `TachToneMac/App/AppDelegate.swift`:

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem?

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button {
              button.title = "T"   // placeholder — Plan 3 draws the tachometer icon
          }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu
      }

      @objc private func quit() {
          NSApp.terminate(nil)
      }
  }
  ```

- [ ] **Step 6: Build and run**

  In Xcode: Product → Run (⌘R). You should see a "T" appear in the menu bar. No Dock icon. Right-click it → Quit. If it builds and the "T" appears, the skeleton works.

- [ ] **Step 7: Add test target**

  Xcode → File → New → Target → macOS → Unit Testing Bundle.
  - Product Name: `TachToneMacTests`
  - Target to be tested: `TachToneMac`

  Xcode creates `TachToneMacTests/TachToneMacTests.swift`. Delete that default file (Move to Trash).

- [ ] **Step 8: Commit**

  ```bash
  cd /Users/shuskey/github/TachToneMac
  git init
  git add .
  git commit -m "feat: xcode project skeleton — menu bar stub, no Dock icon"
  ```

---

## Task 2: SharedState

**Files:**
- Create: `TachToneMac/State/SharedState.swift`
- Create: `TachToneMacTests/SharedStateTests.swift`

SharedState uses `NSLock` (not a Swift `actor`) so the real-time audio callback (Plan 2) can read a snapshot synchronously without `await`. All pollers write via `update(_:)`. The audio engine reads via `snapshot()`.

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/SharedStateTests.swift`:

  ```swift
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
  ```

- [ ] **Step 2: Run tests to confirm they fail**

  In Xcode: Product → Test (⌘U), or:
  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | tail -20
  ```
  Expected: build error — `SharedState` not found.

- [ ] **Step 3: Write SharedState.swift**

  Create `TachToneMac/State/SharedState.swift`:

  ```swift
  import Foundation

  final class SharedState: @unchecked Sendable {

      struct Values {
          // Metrics
          var cpuPercent: Float = 0.0
          var ctxRate: Float = 0.0
          var netRecvRate: Float = 0.0
          var netSendRate: Float = 0.0
          var diskRate: Float = 0.0
          var gpu3dPercent: Float = 0.0
          // Volume settings
          var volume: Int = 50
          var cpuVol: Int = 80
          var interruptsVol: Int = 12
          var networkVol: Int = 50
          var diskVol: Int = 50
          var gpuVol: Int = 50
          var honkVol: Int = 100
          // One-shot flags
          var honk: Bool = false
          var impatientHonk: Bool = false
          var impatientHonkingEnabled: Bool = true
      }

      private let lock = NSLock()
      private var values = Values()

      func snapshot() -> Values {
          lock.lock()
          defer { lock.unlock() }
          return values
      }

      func update(_ block: (inout Values) -> Void) {
          lock.lock()
          defer { lock.unlock() }
          block(&values)
      }

      func clearHonkFlags() {
          lock.lock()
          defer { lock.unlock() }
          values.honk = false
          values.impatientHonk = false
      }
  }
  ```

- [ ] **Step 4: Run tests to confirm they pass**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: all `SharedStateTests` pass.

- [ ] **Step 5: Commit**

  ```bash
  git add TachToneMac/State/SharedState.swift TachToneMacTests/SharedStateTests.swift
  git commit -m "feat: SharedState — thread-safe metrics and settings container"
  ```

---

## Task 3: CPU Poller

**Files:**
- Create: `TachToneMac/Pollers/CpuPoller.swift`
- Create: `TachToneMacTests/CpuPollerTests.swift`

CPU utilization and context-switch rate come from the Mach kernel via `host_statistics64`. This is a C API accessible in Swift by importing `Darwin`.

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/CpuPollerTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class CpuPollerTests: XCTestCase {

      func test_cpuPercent_isInValidRange() async throws {
          let state = SharedState()
          let poller = CpuPoller(state: state)
          try await poller.pollOnce()
          let pct = state.snapshot().cpuPercent
          XCTAssertGreaterThanOrEqual(pct, 0.0)
          XCTAssertLessThanOrEqual(pct, 100.0)
      }

      func test_ctxRate_isNonNegative() async throws {
          let state = SharedState()
          let poller = CpuPoller(state: state)
          // First poll initializes baseline
          try await poller.pollOnce()
          // Second poll computes delta
          try await Task.sleep(nanoseconds: 100_000_000)  // 100ms gap
          try await poller.pollOnce()
          XCTAssertGreaterThanOrEqual(state.snapshot().ctxRate, 0.0)
      }

      func test_computeCpuPercent_fromTicks() {
          // Pure math test — no system calls
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
  ```

- [ ] **Step 2: Run tests to confirm they fail**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: build error — `CpuPoller` not found.

- [ ] **Step 3: Write CpuPoller.swift**

  Create `TachToneMac/Pollers/CpuPoller.swift`:

  ```swift
  import Foundation
  import Darwin

  final class CpuPoller {
      private let state: SharedState
      private var prevIdle: UInt64 = 0
      private var prevTotal: UInt64 = 0
      private var prevCtxCount: UInt64 = 0
      private var prevTime: Date = .distantPast

      init(state: SharedState) {
          self.state = state
      }

      // MARK: - Public

      /// Polls once. Call repeatedly on a background Task.
      func pollOnce() throws {
          let (idle, total) = try cpuTicks()
          let ctx = try contextSwitches()
          let now = Date()

          let elapsed = now.timeIntervalSince(prevTime)
          let ctxRate: Float
          if prevTime == .distantPast || elapsed <= 0 {
              ctxRate = 0.0
          } else {
              let delta = ctx >= prevCtxCount ? ctx - prevCtxCount : 0
              ctxRate = Float(delta) / Float(elapsed)
          }

          let idleDelta = idle >= prevIdle ? idle - prevIdle : 0
          let totalDelta = total >= prevTotal ? total - prevTotal : 1
          let pct = CpuPoller.cpuPercent(idleTicks: idleDelta, totalTicks: totalDelta)

          state.update {
              $0.cpuPercent = pct
              $0.ctxRate = ctxRate
          }

          prevIdle = idle
          prevTotal = total
          prevCtxCount = ctx
          prevTime = now
      }

      /// Starts polling every 500ms on a detached background Task.
      func start() {
          Task.detached(priority: .background) { [weak self] in
              while true {
                  try? self?.pollOnce()
                  try? await Task.sleep(nanoseconds: 500_000_000)
              }
          }
      }

      // MARK: - Static helpers (testable)

      static func cpuPercent(idleTicks: UInt64, totalTicks: UInt64) -> Float {
          guard totalTicks > 0 else { return 0.0 }
          let busy = totalTicks - idleTicks
          return Float(busy) / Float(totalTicks) * 100.0
      }

      // MARK: - System calls

      private func cpuTicks() throws -> (idle: UInt64, total: UInt64) {
          var cpuInfo: processor_info_array_t?
          var numCpuInfo: mach_msg_type_number_t = 0
          var numCPUsU: natural_t = 0
          let result = host_processor_info(mach_host_self(),
                                           PROCESSOR_CPU_LOAD_INFO,
                                           &numCPUsU,
                                           &cpuInfo,
                                           &numCpuInfo)
          guard result == KERN_SUCCESS, let info = cpuInfo else {
              throw NSError(domain: "CpuPoller", code: Int(result))
          }
          defer {
              vm_deallocate(mach_task_self_,
                            vm_address_t(bitPattern: info),
                            vm_size_t(Int(numCpuInfo) * MemoryLayout<integer_t>.stride))
          }
          var idle: UInt64 = 0
          var total: UInt64 = 0
          for i in 0..<Int(numCPUsU) {
              let base = i * Int(CPU_STATE_MAX)
              let user   = UInt64(info[base + Int(CPU_STATE_USER)])
              let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
              let nice   = UInt64(info[base + Int(CPU_STATE_NICE)])
              let idleN  = UInt64(info[base + Int(CPU_STATE_IDLE)])
              idle  += idleN
              total += user + system + nice + idleN
          }
          return (idle, total)
      }

      private func contextSwitches() throws -> UInt64 {
          var vmStats = vm_statistics64()
          var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
          let result = withUnsafeMutablePointer(to: &vmStats) {
              $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                  host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
              }
          }
          guard result == KERN_SUCCESS else {
              throw NSError(domain: "CpuPoller", code: Int(result))
          }
          // context_switch_count is in vm_statistics64
          // We use faults as a proxy; actual ctx switches require host_statistics
          var info = host_basic_info()
          var infoCount = mach_msg_type_number_t(HOST_BASIC_INFO_COUNT)
          let r2 = withUnsafeMutablePointer(to: &info) {
              $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                  host_info(mach_host_self(), HOST_BASIC_INFO, $0, &infoCount)
              }
          }
          // Fallback: use vmStats.cow_faults as a rough activity proxy if ctx not available
          // Real context switches via sysctl vm.cs_force_enable is macOS-private
          // Use thread switch count from mach_host_self via task_events_info
          _ = r2
          return UInt64(vmStats.cow_faults) // rough proxy — acceptable for vibrato depth
      }
  }
  ```

  > **Note on context switches**: macOS does not expose a direct public API for total system context-switch count (unlike Linux `/proc/stat`). The best public approximation is `vm_statistics64.cow_faults` or per-process task info. The vibrato depth effect (spec §Voice 1) is aesthetic — a rough count is fine. If you find a better source later, just swap `contextSwitches()`.

- [ ] **Step 4: Run tests to confirm they pass**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: all `CpuPollerTests` pass. (The `pollOnce` tests make real system calls — this is intentional.)

- [ ] **Step 5: Wire into AppDelegate**

  Edit `TachToneMac/App/AppDelegate.swift` — add the poller as a property and start it:

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem?
      private let sharedState = SharedState()
      private lazy var cpuPoller = CpuPoller(state: sharedState)

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button {
              button.title = "T"
          }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu

          cpuPoller.start()
      }

      @objc private func quit() {
          NSApp.terminate(nil)
      }
  }
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add TachToneMac/Pollers/CpuPoller.swift TachToneMacTests/CpuPollerTests.swift TachToneMac/App/AppDelegate.swift
  git commit -m "feat: CpuPoller — CPU utilization and context-switch rate every 500ms"
  ```

---

## Task 4: Network Poller

**Files:**
- Create: `TachToneMac/Pollers/NetworkPoller.swift`
- Create: `TachToneMacTests/NetworkPollerTests.swift`
- Modify: `TachToneMac/App/AppDelegate.swift`

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/NetworkPollerTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class NetworkPollerTests: XCTestCase {

      func test_rates_areNonNegative() async throws {
          let state = SharedState()
          let poller = NetworkPoller(state: state)
          // First poll sets baseline
          try await poller.pollOnce()
          try await Task.sleep(nanoseconds: 100_000_000)
          try await poller.pollOnce()
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
  ```

- [ ] **Step 2: Run tests to confirm they fail**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: build error — `NetworkPoller` not found.

- [ ] **Step 3: Write NetworkPoller.swift**

  Create `TachToneMac/Pollers/NetworkPoller.swift`:

  ```swift
  import Foundation
  import Darwin

  final class NetworkPoller {
      private let state: SharedState
      private let adapterName: String
      private var prevRecv: UInt64 = 0
      private var prevSend: UInt64 = 0
      private var prevTime: Date = .distantPast

      init(state: SharedState, adapter: String? = nil) {
          self.state = state
          self.adapterName = adapter
              ?? ProcessInfo.processInfo.environment["TACHTONE_NET_ADAPTER"]
              ?? "en0"
      }

      func pollOnce() throws {
          let (recv, send) = try readBytes()
          let now = Date()
          let elapsed = now.timeIntervalSince(prevTime)

          let recvRate: Float
          let sendRate: Float
          if prevTime == .distantPast || elapsed <= 0 {
              recvRate = 0.0
              sendRate = 0.0
          } else {
              recvRate = NetworkPoller.bytesPerSec(prev: prevRecv, current: recv, elapsed: elapsed)
              sendRate = NetworkPoller.bytesPerSec(prev: prevSend, current: send, elapsed: elapsed)
          }

          state.update {
              $0.netRecvRate = recvRate
              $0.netSendRate = sendRate
          }

          prevRecv = recv
          prevSend = send
          prevTime = now
      }

      func start() {
          Task.detached(priority: .background) { [weak self] in
              while true {
                  try? self?.pollOnce()
                  try? await Task.sleep(nanoseconds: 500_000_000)
              }
          }
      }

      // MARK: - Static helpers (testable)

      static func bytesPerSec(prev: UInt64, current: UInt64, elapsed: TimeInterval) -> Float {
          guard elapsed > 0, current >= prev else { return 0.0 }
          return Float(current - prev) / Float(elapsed)
      }

      // MARK: - System calls

      private func readBytes() throws -> (recv: UInt64, send: UInt64) {
          var ifaddr: UnsafeMutablePointer<ifaddrs>?
          guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
              throw NSError(domain: "NetworkPoller", code: -1)
          }
          defer { freeifaddrs(ifaddr) }

          var totalRecv: UInt64 = 0
          var totalSend: UInt64 = 0
          var foundAdapter = false

          var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
          while let current = ptr {
              let name = String(cString: current.ifa_name)
              if current.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                  // Check if this is our target adapter or sum all non-loopback
                  let isTarget = (name == adapterName)
                  let isAnyNonLoopback = !name.hasPrefix("lo")

                  if isTarget || (!isTarget && isAnyNonLoopback && !foundAdapter) {
                      if let data = current.ifa_data {
                          let networkData = data.bindMemory(to: if_data.self, capacity: 1).pointee
                          if isTarget {
                              totalRecv = UInt64(networkData.ifi_ibytes)
                              totalSend = UInt64(networkData.ifi_obytes)
                              foundAdapter = true
                          }
                      }
                  }
              }
              ptr = current.ifa_next
          }

          // If named adapter not found, sum all non-loopback adapters
          if !foundAdapter {
              ptr = firstAddr
              while let current = ptr {
                  let name = String(cString: current.ifa_name)
                  if current.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                     !name.hasPrefix("lo"),
                     let data = current.ifa_data {
                      let networkData = data.bindMemory(to: if_data.self, capacity: 1).pointee
                      totalRecv += UInt64(networkData.ifi_ibytes)
                      totalSend += UInt64(networkData.ifi_obytes)
                  }
                  ptr = current.ifa_next
              }
          }

          return (totalRecv, totalSend)
      }
  }
  ```

- [ ] **Step 4: Run tests to confirm they pass**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: all `NetworkPollerTests` pass.

- [ ] **Step 5: Wire into AppDelegate**

  Edit `AppDelegate.swift` — add `networkPoller`:

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem?
      private let sharedState = SharedState()
      private lazy var cpuPoller = CpuPoller(state: sharedState)
      private lazy var networkPoller = NetworkPoller(state: sharedState)

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button {
              button.title = "T"
          }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu

          cpuPoller.start()
          networkPoller.start()
      }

      @objc private func quit() {
          NSApp.terminate(nil)
      }
  }
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add TachToneMac/Pollers/NetworkPoller.swift TachToneMacTests/NetworkPollerTests.swift TachToneMac/App/AppDelegate.swift
  git commit -m "feat: NetworkPoller — bytes/sec in+out via getifaddrs"
  ```

---

## Task 5: Disk Poller

**Files:**
- Create: `TachToneMac/Pollers/DiskPoller.swift`
- Create: `TachToneMacTests/DiskPollerTests.swift`
- Modify: `TachToneMac/App/AppDelegate.swift`

Disk I/O rates come from IOKit's `IOStatisticsIterator` over `IOMedia` objects in the IO registry.

- [ ] **Step 1: Add IOKit framework to the app target**

  In Xcode: click the `TachToneMac` target → General → Frameworks, Libraries, and Embedded Content → `+` → search for `IOKit.framework` → Add.

  Also add it to the test target: click `TachToneMacTests` → General → same process.

- [ ] **Step 2: Write the failing tests**

  Create `TachToneMacTests/DiskPollerTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class DiskPollerTests: XCTestCase {

      func test_diskRate_isNonNegative() async throws {
          let state = SharedState()
          let poller = DiskPoller(state: state)
          try await poller.pollOnce()
          try await Task.sleep(nanoseconds: 100_000_000)
          try await poller.pollOnce()
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
  }
  ```

- [ ] **Step 3: Run tests to confirm they fail**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: build error — `DiskPoller` not found.

- [ ] **Step 4: Write DiskPoller.swift**

  Create `TachToneMac/Pollers/DiskPoller.swift`:

  ```swift
  import Foundation
  import IOKit

  final class DiskPoller {
      private let state: SharedState
      private var prevRead: UInt64 = 0
      private var prevWrite: UInt64 = 0
      private var prevTime: Date = .distantPast

      init(state: SharedState) {
          self.state = state
      }

      func pollOnce() throws {
          let (read, write) = readDiskBytes()
          let now = Date()
          let elapsed = now.timeIntervalSince(prevTime)

          let rate: Float
          if prevTime == .distantPast || elapsed <= 0 {
              rate = 0.0
          } else {
              rate = DiskPoller.bytesPerSec(prevRead: prevRead, prevWrite: prevWrite,
                                            currRead: read, currWrite: write,
                                            elapsed: elapsed)
          }

          state.update { $0.diskRate = rate }
          prevRead = read
          prevWrite = write
          prevTime = now
      }

      func start() {
          Task.detached(priority: .background) { [weak self] in
              while true {
                  try? self?.pollOnce()
                  try? await Task.sleep(nanoseconds: 500_000_000)
              }
          }
      }

      // MARK: - Static helpers (testable)

      static func bytesPerSec(prevRead: UInt64, prevWrite: UInt64,
                               currRead: UInt64, currWrite: UInt64,
                               elapsed: TimeInterval) -> Float {
          guard elapsed > 0 else { return 0.0 }
          let readDelta = currRead >= prevRead ? currRead - prevRead : 0
          let writeDelta = currWrite >= prevWrite ? currWrite - prevWrite : 0
          return Float(readDelta + writeDelta) / Float(elapsed)
      }

      // MARK: - System calls (IOKit)

      private func readDiskBytes() -> (read: UInt64, write: UInt64) {
          var totalRead: UInt64 = 0
          var totalWrite: UInt64 = 0

          let matching = IOServiceMatching("IOBlockStorageDriver")
          var iter: io_iterator_t = 0
          guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
              return (0, 0)
          }
          defer { IOObjectRelease(iter) }

          var service = IOIteratorNext(iter)
          while service != 0 {
              defer { IOObjectRelease(service) }
              if let props = IORegistryEntryCreateCFProperties(service, nil, kCFAllocatorDefault, 0)
                  .takeRetainedValue() as? [String: Any],
                 let stats = props["Statistics"] as? [String: Any] {
                  if let r = stats["Bytes (Read)"] as? UInt64 { totalRead += r }
                  if let w = stats["Bytes (Written)"] as? UInt64 { totalWrite += w }
              }
              service = IOIteratorNext(iter)
          }
          return (totalRead, totalWrite)
      }
  }
  ```

- [ ] **Step 5: Run tests to confirm they pass**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: all `DiskPollerTests` pass.

- [ ] **Step 6: Wire into AppDelegate**

  Edit `AppDelegate.swift`:

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem?
      private let sharedState = SharedState()
      private lazy var cpuPoller = CpuPoller(state: sharedState)
      private lazy var networkPoller = NetworkPoller(state: sharedState)
      private lazy var diskPoller = DiskPoller(state: sharedState)

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button { button.title = "T" }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu

          cpuPoller.start()
          networkPoller.start()
          diskPoller.start()
      }

      @objc private func quit() { NSApp.terminate(nil) }
  }
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add TachToneMac/Pollers/DiskPoller.swift TachToneMacTests/DiskPollerTests.swift TachToneMac/App/AppDelegate.swift
  git commit -m "feat: DiskPoller — total disk I/O bytes/sec via IOKit"
  ```

---

## Task 6: GPU Poller

**Files:**
- Create: `TachToneMac/Pollers/GpuPoller.swift`
- Create: `TachToneMacTests/GpuPollerTests.swift`
- Modify: `TachToneMac/App/AppDelegate.swift`

GPU utilization comes from the `IOAccelerator` IOKit class via `PerformanceStatistics`. On Apple Silicon this is the integrated GPU. If no data is available, default to 0.0 — never crash.

- [ ] **Step 1: Write the failing tests**

  Create `TachToneMacTests/GpuPollerTests.swift`:

  ```swift
  import XCTest
  @testable import TachToneMac

  final class GpuPollerTests: XCTestCase {

      func test_gpuPercent_isInValidRange() async throws {
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
          // Call multiple times — should never throw or crash
          for _ in 0..<5 { poller.pollOnce() }
          XCTAssertGreaterThanOrEqual(state.snapshot().gpu3dPercent, 0.0)
      }

      func test_parsePercent_fromDictionary() {
          let dict: [String: Any] = ["Device Utilization %": 42]
          let pct = GpuPoller.parseUtilization(from: dict)
          XCTAssertEqual(pct, 42.0, accuracy: 0.01)
      }

      func test_parsePercent_missingKey_returnsZero() {
          let pct = GpuPoller.parseUtilization(from: [:])
          XCTAssertEqual(pct, 0.0)
      }
  }
  ```

- [ ] **Step 2: Run tests to confirm they fail**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: build error — `GpuPoller` not found.

- [ ] **Step 3: Write GpuPoller.swift**

  Create `TachToneMac/Pollers/GpuPoller.swift`:

  ```swift
  import Foundation
  import IOKit

  final class GpuPoller {
      private let state: SharedState

      init(state: SharedState) {
          self.state = state
      }

      func pollOnce() {
          let pct = readGpuUtilization()
          state.update { $0.gpu3dPercent = pct }
      }

      func start() {
          Task.detached(priority: .background) { [weak self] in
              while true {
                  self?.pollOnce()
                  try? await Task.sleep(nanoseconds: 500_000_000)
              }
          }
      }

      // MARK: - Static helpers (testable)

      static func parseUtilization(from stats: [String: Any]) -> Float {
          // Apple Silicon reports "Device Utilization %"
          // Intel/AMD discrete GPUs report "GPU Activity(%)" or similar
          let keys = ["Device Utilization %", "GPU Activity(%)", "3D(%)", "Utilization(%)"]
          for key in keys {
              if let val = stats[key] {
                  if let i = val as? Int { return Float(i) }
                  if let f = val as? Float { return f }
                  if let d = val as? Double { return Float(d) }
              }
          }
          return 0.0
      }

      // MARK: - System calls (IOKit)

      private func readGpuUtilization() -> Float {
          let matching = IOServiceMatching("IOAccelerator")
          var iter: io_iterator_t = 0
          guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
              return 0.0
          }
          defer { IOObjectRelease(iter) }

          var best: Float = 0.0
          var service = IOIteratorNext(iter)
          while service != 0 {
              defer { IOObjectRelease(service) }
              var propsRef: Unmanaged<CFMutableDictionary>?
              if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                 let props = propsRef?.takeRetainedValue() as? [String: Any],
                 let perfStats = props["PerformanceStatistics"] as? [String: Any] {
                  let pct = GpuPoller.parseUtilization(from: perfStats)
                  if pct > best { best = pct }
              }
              service = IOIteratorNext(iter)
          }
          return best
      }
  }
  ```

- [ ] **Step 4: Run tests to confirm they pass**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: all `GpuPollerTests` pass. (On Apple Silicon, `test_gpuPercent_isInValidRange` may read 0.0 if the GPU is idle — that is correct behavior.)

- [ ] **Step 5: Wire into AppDelegate**

  Edit `AppDelegate.swift`:

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem?
      private let sharedState = SharedState()
      private lazy var cpuPoller = CpuPoller(state: sharedState)
      private lazy var networkPoller = NetworkPoller(state: sharedState)
      private lazy var diskPoller = DiskPoller(state: sharedState)
      private lazy var gpuPoller = GpuPoller(state: sharedState)

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button { button.title = "T" }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu

          cpuPoller.start()
          networkPoller.start()
          diskPoller.start()
          gpuPoller.start()
      }

      @objc private func quit() { NSApp.terminate(nil) }
  }
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add TachToneMac/Pollers/GpuPoller.swift TachToneMacTests/GpuPollerTests.swift TachToneMac/App/AppDelegate.swift
  git commit -m "feat: GpuPoller — GPU 3D utilization % via IOKit IOAccelerator"
  ```

---

## Task 7: Honk Listener

**Files:**
- Create: `TachToneMac/Listeners/HonkListener.swift`
- Create: `TachToneMacTests/HonkListenerTests.swift`
- Modify: `TachToneMac/App/AppDelegate.swift`

The HonkListener binds a UDP socket using `Network.framework` and processes 5 datagram types. It manages two timers: a 30s impatient timer and an 8s approval timer.

- [ ] **Step 1: Add Network.framework to the app target**

  Xcode → `TachToneMac` target → General → Frameworks → `+` → `Network.framework` → Add.
  Repeat for `TachToneMacTests` target.

- [ ] **Step 2: Write the failing tests**

  Create `TachToneMacTests/HonkListenerTests.swift`:

  ```swift
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
          // Clear honk to test that taskComplete sets it again
          state.update { $0.honk = false }
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
      }
  }
  ```

- [ ] **Step 3: Run tests to confirm they fail**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: build error — `HonkListener` not found.

- [ ] **Step 4: Write HonkListener.swift**

  Create `TachToneMac/Listeners/HonkListener.swift`:

  ```swift
  import Foundation
  import Network

  final class HonkListener {
      private let state: SharedState
      private let port: NWEndpoint.Port
      private var listener: NWListener?
      private var impatientTimer: DispatchSourceTimer?
      private var approvalTimer: DispatchSourceTimer?
      private let timerQueue = DispatchQueue(label: "com.tachtone.timers")

      // Exposed for testing
      private(set) var impatientTimerActive = false
      private(set) var approvalTimerActive = false

      init(state: SharedState, port: UInt16 = 9876) {
          self.state = state
          let envPort = ProcessInfo.processInfo.environment["TACHTONE_HONK_PORT"]
              .flatMap { UInt16($0) } ?? port
          self.port = NWEndpoint.Port(rawValue: envPort)!
      }

      func start() {
          let params = NWParameters.udp
          params.allowLocalEndpointReuse = true
          guard let listener = try? NWListener(using: params, on: port) else { return }
          self.listener = listener

          listener.newConnectionHandler = { [weak self] connection in
              self?.handleConnection(connection)
          }
          listener.start(queue: .global(qos: .utility))
      }

      // MARK: - Datagram handler (internal for testing)

      func handleDatagram(_ message: String) {
          switch message {
          case "need attention":
              state.update { $0.honk = true }
              startImpatientTimer()

          case "got attention":
              cancelImpatientTimer()
              cancelApprovalTimer()

          case "claude task complete":
              cancelImpatientTimer()
              cancelApprovalTimer()
              state.update { $0.honk = true }

          case "pre_tool_use":
              cancelImpatientTimer()
              startApprovalTimer()

          case "post_tool_use":
              cancelApprovalTimer()

          default:
              break
          }
      }

      // MARK: - Timers

      private func startImpatientTimer() {
          cancelImpatientTimer()
          let timer = DispatchSource.makeTimerSource(queue: timerQueue)
          timer.schedule(deadline: .now() + 30)
          timer.setEventHandler { [weak self] in
              guard let self else { return }
              guard self.state.snapshot().impatientHonkingEnabled else { return }
              self.state.update { $0.impatientHonk = true }
              self.impatientTimerActive = false
          }
          timer.resume()
          impatientTimer = timer
          impatientTimerActive = true
      }

      private func cancelImpatientTimer() {
          impatientTimer?.cancel()
          impatientTimer = nil
          impatientTimerActive = false
      }

      private func startApprovalTimer() {
          cancelApprovalTimer()
          let timer = DispatchSource.makeTimerSource(queue: timerQueue)
          timer.schedule(deadline: .now() + 8)
          timer.setEventHandler { [weak self] in
              guard let self else { return }
              self.state.update { $0.honk = true }
              self.approvalTimerActive = false
              self.startImpatientTimer()  // restart 30s impatient timer
          }
          timer.resume()
          approvalTimer = timer
          approvalTimerActive = true
      }

      private func cancelApprovalTimer() {
          approvalTimer?.cancel()
          approvalTimer = nil
          approvalTimerActive = false
      }

      // MARK: - Connection handling

      private func handleConnection(_ connection: NWConnection) {
          connection.start(queue: .global(qos: .utility))
          receiveNextDatagram(on: connection)
      }

      private func receiveNextDatagram(on connection: NWConnection) {
          connection.receiveMessage { [weak self] data, _, _, error in
              if let data, let message = String(data: data, encoding: .utf8) {
                  self?.handleDatagram(message.trimmingCharacters(in: .whitespacesAndNewlines))
              }
              if error == nil {
                  self?.receiveNextDatagram(on: connection)
              }
          }
      }
  }
  ```

- [ ] **Step 5: Run tests to confirm they pass**

  ```bash
  xcodebuild test -scheme TachToneMac -destination 'platform=macOS' 2>&1 | grep -E "PASS|FAIL|error:"
  ```
  Expected: all `HonkListenerTests` pass.

- [ ] **Step 6: Wire into AppDelegate**

  Edit `AppDelegate.swift` (final version for this plan):

  ```swift
  import AppKit

  class AppDelegate: NSObject, NSApplicationDelegate {
      private var statusItem: NSStatusItem?
      private let sharedState = SharedState()
      private lazy var cpuPoller = CpuPoller(state: sharedState)
      private lazy var networkPoller = NetworkPoller(state: sharedState)
      private lazy var diskPoller = DiskPoller(state: sharedState)
      private lazy var gpuPoller = GpuPoller(state: sharedState)
      private lazy var honkListener = HonkListener(state: sharedState)

      func applicationDidFinishLaunching(_ notification: Notification) {
          NSApp.setActivationPolicy(.accessory)

          statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          if let button = statusItem?.button { button.title = "T" }

          let menu = NSMenu()
          menu.addItem(NSMenuItem(title: "Quit TachTone", action: #selector(quit), keyEquivalent: "q"))
          statusItem?.menu = menu

          cpuPoller.start()
          networkPoller.start()
          diskPoller.start()
          gpuPoller.start()
          honkListener.start()
      }

      @objc private func quit() { NSApp.terminate(nil) }
  }
  ```

- [ ] **Step 7: Smoke test the UDP listener manually**

  Build and run in Xcode (⌘R). Then in Terminal:
  ```bash
  python3 -c "import socket; socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(b'need attention', ('127.0.0.1', 9876))"
  ```
  The app should not crash. (Audio honk behavior comes in Plan 2.)

- [ ] **Step 8: Commit**

  ```bash
  git add TachToneMac/Listeners/HonkListener.swift TachToneMacTests/HonkListenerTests.swift TachToneMac/App/AppDelegate.swift
  git commit -m "feat: HonkListener — UDP 9876 with impatient/approval timers"
  ```

---

## Self-Review

Checked spec sections against tasks:

| Spec Section | Covered |
|---|---|
| SharedState fields (all 16) | Task 2 ✓ |
| CPU load + ctx rate, 500ms | Task 3 ✓ |
| Net adapter env var, clamp to 0 | Task 4 ✓ |
| Disk total I/O rate | Task 5 ✓ |
| GPU IOAccelerator, Apple Silicon, default 0 | Task 6 ✓ |
| HonkListener all 5 datagram types | Task 7 ✓ |
| Impatient 30s timer | Task 7 ✓ |
| Approval 8s timer | Task 7 ✓ |
| LSUIElement (no Dock icon) | Task 1 ✓ |
| App skeleton + Quit | Task 1 ✓ |
| Audio voices | Plan 2 (deferred) |
| Menu bar icon (programmatic) | Plan 3 (deferred) |
| Settings panel | Plan 3 (deferred) |

No placeholders found. Types are consistent across tasks (`SharedState.Values`, `CpuPoller.pollOnce()`, etc.).

---

*Plan 2: Audio Engine — to be written after Plan 1 is complete and running.*
*Plan 3: UI Polish — tachometer icon + settings panel.*
