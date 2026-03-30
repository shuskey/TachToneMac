import Foundation

// SAFETY: All mutable state is protected by `lock`. No property is ever
// accessed without holding the lock, so cross-actor use is safe.
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
