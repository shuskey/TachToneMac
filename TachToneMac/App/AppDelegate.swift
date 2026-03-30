import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let sharedState = SharedState()
    private lazy var cpuPoller = CpuPoller(state: sharedState)
    private lazy var networkPoller = NetworkPoller(state: sharedState)
    private lazy var diskPoller = DiskPoller(state: sharedState)
    private lazy var gpuPoller = GpuPoller(state: sharedState)
    private lazy var honkListener = HonkListener(state: sharedState)

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
        diskPoller.start()
        gpuPoller.start()
        honkListener.start()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
