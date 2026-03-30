import Foundation
import Darwin

// SAFETY: Mutable `prev*` state is only ever accessed from the single
// background task started by `start()`. Calling `start()` more than once
// creates a data race — callers must not do this.
final class CpuPoller: @unchecked Sendable {
    private let state: SharedState
    private var prevIdle: UInt64 = 0
    private var prevTotal: UInt64 = 0
    private var prevCtxCount: UInt64 = 0
    private var prevTime: Date = .distantPast
    private var started = false

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
        // macOS does not expose a direct public API for total system context-switch
        // count. cow_faults from vm_statistics64 is used as a rough activity proxy —
        // sufficient for driving the RPM-instability vibrato effect (spec §Voice 1).
        return UInt64(vmStats.cow_faults)
    }
}
