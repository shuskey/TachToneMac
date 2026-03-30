import Foundation
import IOKit

// SAFETY: GpuPoller has no mutable state between polls. `pollOnce()` is
// safe to call from any thread. `start()` must be called at most once —
// calling it again creates a duplicate background task.
final class GpuPoller: @unchecked Sendable {
    private let state: SharedState
    private var started = false

    init(state: SharedState) {
        self.state = state
    }

    func pollOnce() {
        let pct = readGpuUtilization()
        state.update { $0.gpu3dPercent = pct }
    }

    /// Starts polling every 500ms on a detached background Task. Must be called at most once.
    func start() {
        guard !started else { return }
        started = true
        Task.detached(priority: .background) { [weak self] in
            while true {
                self?.pollOnce()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    // MARK: - Static helpers (testable)

    /// Tries known utilization keys in priority order. Returns 0.0 if none found.
    /// Handles Int, Float, and Double value types from IOKit.
    static func parseUtilization(from stats: [String: Any]) -> Float {
        let keys = ["Device Utilization %", "GPU Activity(%)", "3D(%)", "Utilization(%)"]
        for key in keys {
            if let val = stats[key] {
                if let i = val as? Int    { return Float(i) }
                if let f = val as? Float  { return f }
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
