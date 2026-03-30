import Foundation
import Darwin

// SAFETY: Mutable `prev*` state is only ever accessed from the single
// background task started by `start()`. Calling `start()` more than once
// creates a data race — callers must not do this.
final class NetworkPoller: @unchecked Sendable {
    private let state: SharedState
    private let adapterName: String
    private var prevRecv: UInt64 = 0
    private var prevSend: UInt64 = 0
    private var prevTime: Date = .distantPast
    private var started = false

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

        // Try named adapter first
        var targetRecv: UInt64 = 0
        var targetSend: UInt64 = 0
        var foundTarget = false

        // Fallback: sum all non-loopback adapters
        var fallbackRecv: UInt64 = 0
        var fallbackSend: UInt64 = 0

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cursor = ptr {
            let name = String(cString: cursor.pointee.ifa_name)
            if cursor.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               let data = cursor.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                if name == adapterName {
                    targetRecv = UInt64(networkData.ifi_ibytes)
                    targetSend = UInt64(networkData.ifi_obytes)
                    foundTarget = true
                }
                if !name.hasPrefix("lo") {
                    fallbackRecv += UInt64(networkData.ifi_ibytes)
                    fallbackSend += UInt64(networkData.ifi_obytes)
                }
            }
            ptr = cursor.pointee.ifa_next
        }

        return foundTarget
            ? (targetRecv, targetSend)
            : (fallbackRecv, fallbackSend)
    }
}
