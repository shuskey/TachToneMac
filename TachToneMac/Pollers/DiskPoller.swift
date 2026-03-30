import Foundation
import IOKit

// SAFETY: Mutable `prev*` state is only ever accessed from the single
// background task started by `start()`. Calling `start()` more than once
// creates a data race — callers must not do this.
final class DiskPoller: @unchecked Sendable {
    private let state: SharedState
    private var prevRead: UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime: Date = .distantPast
    private var started = false

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

    /// Starts polling every 500ms on a detached background Task. Must be called at most once.
    func start() {
        guard !started else { return }
        started = true
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
            var propsRef: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = propsRef?.takeRetainedValue() as? [String: Any],
               let stats = props["Statistics"] as? [String: Any] {
                if let r = stats["Bytes (Read)"] as? UInt64 { totalRead += r }
                if let w = stats["Bytes (Written)"] as? UInt64 { totalWrite += w }
            }
            service = IOIteratorNext(iter)
        }
        return (totalRead, totalWrite)
    }
}
