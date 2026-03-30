import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let sharedState = SharedState()
    private lazy var cpuPoller = CpuPoller(state: sharedState)
    private lazy var networkPoller = NetworkPoller(state: sharedState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.title = "T"   // placeholder — Plan 3 draws the tachometer icon
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
