import Foundation
import Network

final class HonkListener: @unchecked Sendable {
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
            self.impatientTimerActive = false
            guard self.state.snapshot().impatientHonkingEnabled else { return }
            self.state.update { $0.impatientHonk = true }
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
            self.approvalTimerActive = false
            self.state.update { $0.honk = true }
            self.startImpatientTimer()
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

    // MARK: - Test support

    /// Fires the impatient timer's event handler synchronously for testing.
    /// Does NOT cancel the real timer.
    func fireImpatientTimerForTesting() {
        impatientTimerActive = false
        guard state.snapshot().impatientHonkingEnabled else { return }
        state.update { $0.impatientHonk = true }
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
