import AppKit
import ApplicationServices

/// Intercepts the hardware brightness / volume keys and routes them to external monitors.
final class MediaKeys {
    private let manager: DisplayManager
    private var tap: CFMachPort?
    private var retryTimer: Timer?

    private static let step = 1.0 / 16.0
    private static let keyVolumeUp = 0, keyVolumeDown = 1, keyBrightnessUp = 2, keyBrightnessDown = 3, keyMute = 7

    var brightnessEnabled: Bool { UserDefaults.standard.object(forKey: "brightnessKeys") as? Bool ?? true }
    var volumeEnabled: Bool { UserDefaults.standard.bool(forKey: "volumeKeys") }
    /// Whether the keys adjust every display rather than the one under the pointer. Holding Control does the other for one
    /// press (not Option: Option with a brightness key opens Displays settings in macOS).
    var controlsAllDisplays: Bool { UserDefaults.standard.bool(forKey: "keysControlAllDisplays") }

    init(manager: DisplayManager) {
        self.manager = manager
    }

    /// Starts the tap, prompting for Accessibility permission if needed.
    func start() {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() { timer.invalidate(); self?.start() }
            }
            return
        }
        let mask = CGEventMask(1 << 14)  // NX_SYSDEFINED
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, context in
            let keys = Unmanaged<MediaKeys>.fromOpaque(context!).takeUnretainedValue()
            return keys.handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = (ns.data1 & 0xFFFF_0000) >> 16
        let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
        let isBrightness = keyCode == Self.keyBrightnessUp || keyCode == Self.keyBrightnessDown
        let isVolume = keyCode == Self.keyVolumeUp || keyCode == Self.keyVolumeDown || keyCode == Self.keyMute
        let all = controlsAllDisplays != ns.modifierFlags.contains(.control)

        if isBrightness && brightnessEnabled {
            let targets = all ? manager.displays : manager.displaysUnderCursor()
            let externals = targets.filter { !$0.isBuiltin }
            guard !externals.isEmpty else { return Unmanaged.passUnretained(event) }
            // Monitors following the built-in display follow the change macOS makes to it; adjusting them here as well
            // would move them twice.
            if all && DisplayManager.followsBuiltin && targets.contains(where: \.isBuiltin) {
                return Unmanaged.passUnretained(event)
            }
            if isDown {
                let delta = keyCode == Self.keyBrightnessUp ? Self.step : -Self.step
                let caption = all && targets.count > 1 ? "All displays" : nil
                DispatchQueue.main.async {
                    for display in externals { display.setBrightness(display.brightness + delta) }
                    if let first = externals.first {
                        HUD.shared.show(symbol: "sun.max.fill", value: first.brightness, caption: caption)
                    }
                }
            }
            // If the built-in is also targeted (all displays, or mirroring), let macOS handle it too.
            return targets.contains { $0.isBuiltin } ? Unmanaged.passUnretained(event) : nil
        }

        if isVolume && volumeEnabled {
            let targets = all ? manager.displays : manager.displaysUnderCursor()
            let externals = targets.filter { !$0.isBuiltin && $0.volume != nil }
            guard !externals.isEmpty else { return Unmanaged.passUnretained(event) }
            if isDown {
                let caption = all && externals.count > 1 ? "All displays" : nil
                DispatchQueue.main.async {
                    for display in externals {
                        let current = display.volume ?? 0
                        let next = keyCode == Self.keyMute ? (current > 0 ? 0 : 0.5)
                            : current + (keyCode == Self.keyVolumeUp ? Self.step : -Self.step)
                        display.setVolume(next)
                    }
                    if let v = externals.first?.volume {
                        HUD.shared.show(symbol: v == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", value: v, caption: caption)
                    }
                }
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
