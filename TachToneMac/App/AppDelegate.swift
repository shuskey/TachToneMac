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
