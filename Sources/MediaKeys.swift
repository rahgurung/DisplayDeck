import AppKit
import ApplicationServices

/// Intercepts the hardware brightness / volume keys and routes them to external monitors.
final class MediaKeys {
    private let manager: DisplayManager
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    private var trustTimer: Timer?
    private var trustObserver: NSObjectProtocol?

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
            waitForTrust()
            return
        }
        let mask = CGEventMask(1 << 14)  // NX_SYSDEFINED
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, context in
            let keys = Unmanaged<MediaKeys>.fromOpaque(context!).takeUnretainedValue()
            return keys.handle(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        watchTrust()
    }

    /// Removes the tap. An active tap left in place after Accessibility is revoked stops receiving events, and the
    /// system waits on it for every key press until it times out, which freezes input across the Mac.
    private func stop() {
        trustTimer?.invalidate()
        trustTimer = nil
        if let trustObserver { DistributedNotificationCenter.default().removeObserver(trustObserver) }
        trustObserver = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    /// Starts the tap once Accessibility is granted.
    private func waitForTrust() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() { timer.invalidate(); self?.start() }
        }
    }

    /// Removes the tap as soon as Accessibility is revoked, then waits for it to be granted again.
    private func watchTrust() {
        let check = { [weak self] in
            guard let self, tap != nil, !AXIsProcessTrusted() else { return }
            stop()
            waitForTrust()
        }
        // Posted when the list of trusted apps changes, slightly before the change takes effect, so check again shortly
        // after. The timer covers any change that doesn't post it.
        trustObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"),
                                                                            object: nil, queue: .main) { _ in
            check()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: check)
        }
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in check() }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Turning the tap back on after Accessibility was revoked would stall input again; remove it instead.
            if AXIsProcessTrusted() {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                DispatchQueue.main.async { [self] in stop(); waitForTrust() }
            }
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
