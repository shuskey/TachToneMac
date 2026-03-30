import AppKit
import ServiceManagement

final class SettingsViewController: NSViewController {
    private let sharedState: SharedState

    // Internal for testing
    var masterSlider:      NSSlider!
    var cpuSlider:         NSSlider!
    var networkSlider:     NSSlider!
    var diskSlider:        NSSlider!
    var gpuSlider:         NSSlider!
    var honkSlider:        NSSlider!
    var coinSlider:        NSSlider!
    var impatientCheckbox:   NSButton!
    var launchAtLoginCheckbox: NSButton!

    // Maps each slider to its numeric readout label
    private var valueLabels: [NSSlider: NSTextField] = [:]

    init(state: SharedState) {
        self.sharedState = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("use init(state:)") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 360))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        loadValues()
    }

    // Refresh values every time the panel becomes visible
    override func viewWillAppear() {
        super.viewWillAppear()
        loadValues()
    }

    // MARK: - Build UI

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        masterSlider  = makeSlider()
        cpuSlider     = makeSlider()
        networkSlider = makeSlider()
        diskSlider    = makeSlider()
        gpuSlider     = makeSlider()
        honkSlider    = makeSlider()
        coinSlider    = makeSlider()

        let rows: [(String, NSSlider)] = [
            ("Master",      masterSlider),
            ("CPU",         cpuSlider),
            ("Network",     networkSlider),
            ("Disk",        diskSlider),
            ("GPU",         gpuSlider),
            ("Honk",        honkSlider),
            ("Token Cost",  coinSlider),
        ]
        for (label, slider) in rows {
            stack.addArrangedSubview(makeRow(label: label, slider: slider))
        }

        impatientCheckbox = NSButton(checkboxWithTitle: "Impatient honking",
                                     target: self, action: #selector(checkboxChanged(_:)))
        stack.addArrangedSubview(impatientCheckbox)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login",
                                         target: self, action: #selector(launchAtLoginChanged(_:)))
        stack.addArrangedSubview(launchAtLoginCheckbox)
    }

    private func makeSlider() -> NSSlider {
        let s = NSSlider(value: 50, minValue: 0, maxValue: 100,
                         target: self, action: #selector(sliderChanged(_:)))
        s.isContinuous = true
        return s
    }

    private func makeRow(label: String, slider: NSSlider) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let lbl = NSTextField(labelWithString: label + ":")
        lbl.frame.size.width = 70
        lbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let valLbl = NSTextField(labelWithString: "50")
        valLbl.alignment = .right
        valLbl.frame.size.width = 32
        valLbl.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        valueLabels[slider] = valLbl

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valLbl)
        return row
    }

    // MARK: - Load / Save

    private func loadValues() {
        let s = sharedState.snapshot()
        apply(masterSlider,  value: s.volume)
        apply(cpuSlider,     value: s.cpuVol)
        apply(networkSlider, value: s.networkVol)
        apply(diskSlider,    value: s.diskVol)
        apply(gpuSlider,     value: s.gpuVol)
        apply(honkSlider,    value: s.honkVol)
        apply(coinSlider,    value: s.coinVol)
        impatientCheckbox.state = s.impatientHonkingEnabled ? .on : .off
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func apply(_ slider: NSSlider, value: Int) {
        slider.integerValue = value
        valueLabels[slider]?.stringValue = "\(value)"
    }

    // MARK: - Actions

    @objc func sliderChanged(_ sender: NSSlider) {
        let val = sender.integerValue
        valueLabels[sender]?.stringValue = "\(val)"
        let s = sender
        sharedState.update { state in
            if s === self.masterSlider       { state.volume     = val }
            else if s === self.cpuSlider     { state.cpuVol     = val }
            else if s === self.networkSlider { state.networkVol = val }
            else if s === self.diskSlider    { state.diskVol    = val }
            else if s === self.gpuSlider     { state.gpuVol     = val }
            else if s === self.honkSlider    { state.honkVol    = val }
            else if s === self.coinSlider    { state.coinVol    = val }
        }
    }

    @objc func checkboxChanged(_ sender: NSButton) {
        sharedState.update { $0.impatientHonkingEnabled = sender.state == .on }
    }

    @objc func launchAtLoginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert checkbox to reflect actual state if the call failed
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
}
