import AppKit
import Carbon.HIToolbox

/// A key combination for a global shortcut.
struct KeyCombo: Codable, Equatable {
    let keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`), as RegisterEventHotKey takes them.
    let modifiers: UInt32
    /// The key's name when it was recorded, e.g. "K" or "↑", since turning a key code back into a character depends on
    /// the keyboard layout.
    let key: String

    /// How many of ⌘, ⌃ and ⌥ a key needs to be a global shortcut. A global shortcut takes the keys from every app, so
    /// a letter, number or symbol needs two: with one, it could replace ⌘C or ⌘Q everywhere, or stop ⌥E typing an
    /// accent. Arrows and other special keys need one, and function keys none.
    static func modifiersNeeded(keyCode: UInt16) -> Int {
        let code = UInt32(keyCode)
        return functionKeys[code] != nil ? 0 : specialKeys[code] != nil ? 1 : 2
    }

    /// The combination typed in the recorder, or nil without the modifiers the key needs (`modifiersNeeded`).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = UInt32(event.keyCode)
        let held = [NSEvent.ModifierFlags.command, .option, .control].filter(flags.contains).count
        guard held >= Self.modifiersNeeded(keyCode: event.keyCode) else { return nil }
        guard let key = Self.specialKeys[code] ?? Self.functionKeys[code]
                ?? event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        keyCode = code
        modifiers = (flags.contains(.control) ? UInt32(controlKey) : 0) | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0) | (flags.contains(.command) ? UInt32(cmdKey) : 0)
        self.key = key
    }

    /// In the order macOS menus show them, e.g. "⌃⌥⌘K".
    var description: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "")
            + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + key
    }

    func sameKeys(as other: KeyCombo) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }

    private static let specialKeys: [UInt32: String] = [
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space", UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
    ]
    private static let functionKeys: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12", UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]
}

/// Something a shortcut does. Stored by `id`, e.g. "brightnessUp" or "input:2513-10052-1:19".
enum ShortcutAction: Hashable {
    case brightnessUp, brightnessDown, volumeUp, volumeDown, mute
    /// Switches the monitor with this `Display.monitorKey` to the input with this VCP 0x60 value.
    case input(monitor: String, value: UInt8)

    static let levels: [ShortcutAction] = [.brightnessUp, .brightnessDown, .volumeUp, .volumeDown, .mute]

    var id: String {
        switch self {
        case .brightnessUp: "brightnessUp"
        case .brightnessDown: "brightnessDown"
        case .volumeUp: "volumeUp"
        case .volumeDown: "volumeDown"
        case .mute: "mute"
        case let .input(monitor, value): "input:\(monitor):\(value)"
        }
    }

    init?(id: String) {
        if let action = Self.levels.first(where: { $0.id == id }) { self = action; return }
        let parts = id.split(separator: ":")
        guard parts.count == 3, parts[0] == "input", let value = UInt8(parts[2]) else { return nil }
        self = .input(monitor: String(parts[1]), value: value)
    }

    var title: String {
        switch self {
        case .brightnessUp: "Brightness up"
        case .brightnessDown: "Brightness down"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        case .input: "Input"
        }
    }

    /// Brightness and volume repeat while the shortcut is held, like the keys they stand in for.
    var repeats: Bool { self != .mute && !isInput }

    private var isInput: Bool { if case .input = self { true } else { false } }
}

/// User-defined global shortcuts, for keyboards without Mac media keys and for switching inputs. They use Carbon hot
/// keys, which work in every app without Accessibility access.
@Observable
final class Shortcuts {
    private(set) var combos: [String: KeyCombo] = [:]
    /// Shortcuts macOS wouldn't register, usually because another app already has them.
    private(set) var unavailable: Set<String> = []
    /// The action whose shortcut is being recorded in Settings. Shortcuts are switched off meanwhile, so pressing one
    /// records it rather than running it.
    var recording: ShortcutAction? {
        didSet { if recording == nil { register() } else { unregister() } }
    }

    @ObservationIgnored private let manager: DisplayManager
    @ObservationIgnored private var refs: [EventHotKeyRef] = []
    @ObservationIgnored private var actions: [UInt32: ShortcutAction] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var repeatTimer: Timer?

    private static let step = 1.0 / 16.0
    private static let defaultsKey = "shortcuts"
    private static let signature = OSType(0x4444_4b53)  // "DDKS"

    init(manager: DisplayManager) {
        self.manager = manager
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            combos = saved
        }
    }

    func start() {
        installHandler()
        register()
    }

    func combo(for action: ShortcutAction) -> KeyCombo? { combos[action.id] }

    /// Sets or clears a shortcut. A combination already used by another action moves to this one.
    func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        if let combo {
            combos = combos.filter { !$0.value.sameKeys(as: combo) }
            combos[action.id] = combo
        } else {
            combos[action.id] = nil
        }
        if let data = try? JSONEncoder().encode(combos) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
        if recording == nil { register() }
    }

    // MARK: Registering

    private func register() {
        unregister()
        var unavailable: Set<String> = []
        for (number, (id, combo)) in combos.sorted(by: { $0.key < $1.key }).enumerated() {
            guard let action = ShortcutAction(id: id) else { continue }
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(number + 1))
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref) == noErr,
               let ref {
                refs.append(ref)
                actions[hotKeyID.id] = action
            } else {
                unavailable.insert(id)
            }
        }
        if unavailable != self.unavailable { self.unavailable = unavailable }
    }

    private func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
        stopRepeating()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let shortcuts = Unmanaged<Shortcuts>.fromOpaque(context).takeUnretainedValue()
            guard hotKeyID.signature == Shortcuts.signature, let action = shortcuts.actions[hotKeyID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { shortcuts.pressed(action) } else { shortcuts.stopRepeating() }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    // MARK: Running

    private func pressed(_ action: ShortcutAction) {
        perform(action)
        guard action.repeats else { return }
        stopRepeating()
        // Like key repeat: a pause, then steady steps until the shortcut is released.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in self?.perform(action) }
        }
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    /// The displays a brightness or volume shortcut adjusts: the one under the pointer, or all of them, as for the keys.
    private var targets: [Display] {
        UserDefaults.standard.bool(forKey: "keysControlAllDisplays") ? manager.displays : manager.displaysUnderCursor()
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .brightnessUp: stepBrightness(Self.step)
        case .brightnessDown: stepBrightness(-Self.step)
        case .volumeUp: stepVolume(Self.step)
        case .volumeDown: stepVolume(-Self.step)
        case .mute: stepVolume(nil)
        case let .input(monitor, value): switchInput(monitor: monitor, value: value)
        }
    }

    private func stepBrightness(_ delta: Double) {
        var targets = targets
        var followers = 0
        // Monitors following the built-in display move with it (including ones still connecting, once they're done);
        // stepping them as well would move them twice. Apple displays don't follow, so they still step.
        if DisplayManager.followsBuiltin, let builtin = targets.first(where: \.isBuiltin) {
            targets = [builtin] + targets.filter { !$0.isBuiltin && $0.source == .apple }
            followers = manager.displays.filter(\.canFollowBuiltin).count
        }
        guard !targets.isEmpty else { return }
        for display in targets {
            // The built-in display also changes from its own keys and auto-brightness, so start from its real level.
            if display.source == .apple, let level = AppleBrightness.get(display.id) { display.brightness = Double(level) }
            display.setBrightness(display.brightness + delta)
        }
        HUD.shared.show(symbol: "sun.max.fill", value: targets[0].brightness,
                        caption: targets.count + followers > 1 ? "All displays" : nil)
    }

    /// - Parameter delta: the step, or nil to mute (or unmute to half volume).
    private func stepVolume(_ delta: Double?) {
        var targets = targets.filter { $0.volume != nil }
        // These only control monitor speakers, so over a display without any (like the built-in one), use every
        // monitor that has them rather than doing nothing.
        if targets.isEmpty { targets = manager.displays.filter { $0.volume != nil } }
        guard !targets.isEmpty else { return }
        for display in targets {
            let current = display.volume ?? 0
            display.setVolume(delta.map { current + $0 } ?? (current > 0 ? 0 : 0.5))
        }
        let volume = targets[0].volume ?? 0
        HUD.shared.show(symbol: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", value: volume,
                        caption: targets.count > 1 ? "All displays" : nil)
    }

    private func switchInput(monitor: String, value: UInt8) {
        // A monitor that isn't connected (or is showing another computer) has no Display, so there's nothing to do.
        guard let display = manager.displays.first(where: { $0.monitorKey == monitor && $0.source == .ddc }),
              let input = display.inputs.first(where: { $0.value == value }) else { return }
        if display.currentInput != input { display.setInput(input) }
        HUD.shared.show(symbol: "rectangle.connected.to.line.below", value: nil, caption: display.label(for: input))
    }
}
