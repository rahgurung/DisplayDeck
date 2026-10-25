import AppKit
import Observation

enum BrightnessSource { case apple, ddc, gamma }

@Observable
final class Display: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let ddc: DDCChannel?

    var source: BrightnessSource
    var brightness: Double = 1
    var contrast: Double?
    var volume: Double?
    var inputs: [InputSource] = []
    var currentInput: InputSource?
    /// The input the monitor was on when DisplayDeck found it, which is the one this Mac is connected to.
    private var macInput: InputSource?
    /// Names the user gave this monitor's inputs, by input value.
    private(set) var inputNames: [UInt8: String] = [:]
    var probing: Bool
    var modes: [ModeOption] = []
    var currentMode: ModeOption?

    private var maxValues: [VCP: UInt16] = [:]

    init(id: CGDirectDisplayID, name: String, ddc: DDCChannel?) {
        self.id = id
        self.name = name
        self.isBuiltin = CGDisplayIsBuiltin(id) != 0
        self.ddc = ddc
        if isBuiltin || AppleBrightness.get(id) != nil {
            source = .apple
            brightness = Double(AppleBrightness.get(id) ?? 1)
            probing = false
        } else {
            source = ddc == nil ? .gamma : .ddc
            probing = ddc != nil
        }
        reloadModes()
        probeDDC()
        inputNames = (Self.savedInputNames[inputNamesKey] ?? [:]).reduce(into: [:]) { names, entry in
            if let value = UInt8(entry.key) { names[value] = entry.value }
        }
    }

    var sourceLabel: String {
        switch source {
        case .apple: return isBuiltin ? "Built-in" : "Apple display"
        case .ddc: return probing ? "Connecting over DDC…" : "Hardware (DDC)"
        case .gamma: return "Software dimming"
        }
    }

    private func probeDDC() {
        guard let ddc, source == .ddc else { return }
        ddc.read(.brightness) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.maxValues[.brightness] = result.max
                    self.brightness = Double(result.current) / Double(result.max)
                    self.probeInputs()
                } else {
                    self.source = .gamma  // Monitor didn't answer; fall back to software dimming.
                }
                self.probing = false
            }
        }
        for code in [VCP.volume, .contrast] {
            ddc.read(code) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, let result else { return }
                    self.maxValues[code] = result.max
                    let value = Double(result.current) / Double(result.max)
                    if code == .volume { self.volume = value } else { self.contrast = value }
                }
            }
        }
    }

    /// Reads the current input, then the inputs the monitor lists in its capabilities string. Falls back to the
    /// common connectors when the monitor reports an input but doesn't list them.
    private func probeInputs() {
        guard let ddc else { return }
        ddc.read(.inputSource) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if let value = result.map({ UInt8($0.current & 0xFF) }), value != 0 {
                    self.currentInput = InputSource(value: value, vendor: self.vendor)
                    self.macInput = self.currentInput
                }
                if let listed = Self.listedInputs[self.id] { self.setInputs(listed) }
            }
        }
        // The capabilities string takes a couple of seconds to read and holds up other DDC commands meanwhile,
        // so it's read once per display rather than on every reload.
        guard Self.listedInputs[id] == nil else { return }
        let vendor = vendor
        ddc.readCapabilities { [weak self] capabilities in
            let listed = capabilities.map { InputSource.parse(capabilities: $0, vendor: vendor) } ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                if capabilities != nil { Self.listedInputs[self.id] = listed }
                self.setInputs(listed)
            }
        }
    }

    private var vendor: UInt32 { CGDisplayVendorNumber(id) }

    func label(for input: InputSource) -> String {
        inputNames[input.value]?.trimmingCharacters(in: .whitespaces) ?? defaultName(for: input)
    }

    /// The connector name where the code is known. Otherwise "This Mac" for the input the Mac is on, and
    /// "Other input" for the rest, numbered when there's more than one.
    func defaultName(for input: InputSource) -> String {
        if let name = input.knownName { return name }
        if input == macInput { return "This Mac" }
        let others = inputs.filter { $0.knownName == nil && $0 != macInput }
        guard others.count > 1, let index = others.firstIndex(of: input) else { return "Other input" }
        return "Other input \(index + 1)"
    }

    /// Called on every keystroke, so the name is only trimmed when shown. An empty name goes back to the default.
    func renameInput(_ input: InputSource, to name: String) {
        inputNames[input.value] = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
        saveInputNames()
    }

    /// Goes back to the default name for every input on this monitor.
    func resetInputNames() {
        inputNames = [:]
        saveInputNames()
    }

    private func saveInputNames() {
        var saved = Self.savedInputNames
        saved[inputNamesKey] = inputNames.isEmpty ? nil : Dictionary(uniqueKeysWithValues: inputNames.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(saved, forKey: "inputNames")
    }

    /// Identifies the monitor across reconnects, and tells two of the same model apart by serial number.
    private var inputNamesKey: String { "\(vendor)-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))" }

    private static var savedInputNames: [String: [String: String]] {
        UserDefaults.standard.dictionary(forKey: "inputNames") as? [String: [String: String]] ?? [:]
    }

    private static var listedInputs: [CGDirectDisplayID: [InputSource]] = [:]

    private func setInputs(_ listed: [InputSource]) {
        var inputs = listed.isEmpty && currentInput != nil ? InputSource.common(vendor: vendor) : listed
        if let current = currentInput, !inputs.contains(current) { inputs.append(current) }
        self.inputs = inputs
    }

    func reloadModes() {
        modes = DisplayModes.all(for: id)
        currentMode = DisplayModes.current(for: id)
    }

    func setBrightness(_ value: Double) {
        brightness = min(1, max(0, value))
        switch source {
        case .apple: AppleBrightness.set(id, Float(brightness))
        case .ddc: send(.brightness, brightness)
        case .gamma: GammaDimmer.set(id, brightness)
        }
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        send(.volume, volume!)
    }

    func setContrast(_ value: Double) {
        contrast = min(1, max(0, value))
        send(.contrast, contrast!)
    }

    /// Switching to an input connected to another device usually makes this display disappear from the Mac;
    /// the reconfiguration callback in DisplayManager then reloads the list. If the input has no signal, the monitor
    /// hunts for one that does, which can take a while, so keep reading the input back until it settles.
    func setInput(_ input: InputSource) {
        currentInput = input
        ddc?.set(.inputSource, UInt16(input.value))
        Telemetry.send("Input.switched")
        inputSwitch += 1
        let attempt = inputSwitch
        for delay in [3.0, 6.0, 10.0, 15.0, 20.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.inputSwitch == attempt else { return }  // A newer switch is being checked.
                self.refreshInput(attempt: attempt)
            }
        }
    }

    /// Reads the input the monitor is showing now. Called whenever the menu opens, since the input can also change
    /// from the monitor's own buttons or when it switches to a device that turns on.
    func refreshInput() { refreshInput(attempt: inputSwitch) }

    private func refreshInput(attempt: Int) {
        guard source == .ddc, !probing, !inputs.isEmpty else { return }
        ddc?.read(.inputSource) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.inputSwitch == attempt,
                      let value = result.map({ UInt8($0.current & 0xFF) }), value != 0 else { return }
                let current = InputSource(value: value, vendor: self.vendor)
                self.currentInput = current
                if !self.inputs.contains(current) { self.inputs.append(current) }
            }
        }
    }

    @ObservationIgnored private var inputSwitch = 0

    private func send(_ code: VCP, _ value: Double) {
        let max = maxValues[code] ?? 100
        ddc?.set(code, UInt16((value * Double(max)).rounded()))
    }

    // MARK: Resolution

    /// One entry per distinct resolution, preferring the current refresh rate.
    var resolutionOptions: [ModeOption] {
        var bySize: [String: ModeOption] = [:]
        var order: [String] = []
        let currentRefresh = currentMode?.refresh ?? 0
        for mode in modes {
            if let existing = bySize[mode.sizeKey] {
                if abs(mode.refresh - currentRefresh) < abs(existing.refresh - currentRefresh) { bySize[mode.sizeKey] = mode }
            } else {
                bySize[mode.sizeKey] = mode
                order.append(mode.sizeKey)
            }
        }
        return order.compactMap { bySize[$0] }
    }

    struct RefreshChoice: Identifiable {
        let mode: ModeOption
        let rate: Int
        /// Reaching this rate means switching between the HiDPI and non-HiDPI variant of the resolution.
        let changesHiDPI: Bool
        var id: Int { rate }
    }

    /// Every refresh rate available at the current resolution, whether or not it needs the other HiDPI variant
    /// (some monitors only offer high rates without HiDPI). Prefers the current variant for each rate.
    var refreshChoices: [RefreshChoice] {
        guard let currentMode else { return [] }
        func rank(_ mode: ModeOption) -> Int {
            mode.sizeKey == currentMode.sizeKey ? 0 : mode.isHiDPI == currentMode.isHiDPI ? 1 : 2
        }
        var byRate: [Int: ModeOption] = [:]
        for mode in modes where mode.width == currentMode.width && mode.height == currentMode.height {
            let rate = Int(mode.refresh.rounded())
            if let existing = byRate[rate], rank(existing) <= rank(mode) { continue }
            byRate[rate] = mode
        }
        return byRate.keys.sorted().map { rate in
            let mode = byRate[rate]!
            return RefreshChoice(mode: mode, rate: rate, changesHiDPI: mode.isHiDPI != currentMode.isHiDPI)
        }
    }

    func apply(_ option: ModeOption) {
        DisplayModes.apply(option, to: id)
        reloadModes()
    }
}

@Observable
final class DisplayManager {
    var displays: [Display] = []
    var isMirrored = false
    private var reloadWorkItem: DispatchWorkItem?

    init() {
        reload()
        CGDisplayRegisterReconfigurationCallback({ _, flags, context in
            guard let context, !flags.contains(.beginConfigurationFlag) else { return }
            let manager = Unmanaged<DisplayManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { manager.scheduleReload() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    func reload() {
        let ids = Mirroring.onlineDisplays()
        var channels = DDCChannel.discover()
        let externals = ids.filter { CGDisplayIsBuiltin($0) == 0 }
        let screenNames = Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        }, uniquingKeysWith: { a, _ in a })

        displays = ids.map { id in
            var channel: DDCChannel?
            var productName: String?
            if CGDisplayIsBuiltin(id) == 0, let index = bestChannel(for: id, in: channels, onlyOne: externals.count == 1) {
                channel = channels[index].channel
                productName = channels[index].attributes["ProductName"] as? String
                channels.remove(at: index)
            }
            let name = screenNames[id] ?? productName ?? (CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display \(id)")
            return Display(id: id, name: name, ddc: channel)
        }
        // Built-in first, then externals.
        displays.sort { ($0.isBuiltin ? 0 : 1) < ($1.isBuiltin ? 0 : 1) }
        isMirrored = Mirroring.isMirrored
    }

    private func bestChannel(for id: CGDirectDisplayID, in channels: [(attributes: [String: Any], channel: DDCChannel)], onlyOne: Bool) -> Int? {
        func int(_ value: Any?) -> UInt32? { (value as? NSNumber).map { UInt32(truncatingIfNeeded: $0.int64Value) } }
        let scored = channels.enumerated().map { index, entry -> (Int, Int) in
            var score = 0
            if int(entry.attributes["LegacyManufacturerID"]) == CGDisplayVendorNumber(id) { score += 1 }
            if int(entry.attributes["ProductID"]) == CGDisplayModelNumber(id) { score += 1 }
            let serial = CGDisplaySerialNumber(id)
            if serial != 0, int(entry.attributes["SerialNumber"]) == serial { score += 1 }
            return (index, score)
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 2 { return best.0 }
        return onlyOne && channels.count == 1 ? 0 : nil
    }

    func setMirrored(_ on: Bool) {
        Mirroring.setMirrored(on)
        isMirrored = on
        scheduleReload()
    }

    /// Displays affected by a key press: the one under the mouse plus anything mirroring it.
    func displaysUnderCursor() -> [Display] {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return [] }
        let id = number.uint32Value
        let primary = CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay ? CGDisplayMirrorsDisplay(id) : id
        return displays.filter { $0.id == primary || CGDisplayMirrorsDisplay($0.id) == primary }
    }
}
