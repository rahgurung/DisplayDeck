import AppKit
import CoreGraphics

/// Built-in / Apple display brightness via the private DisplayServices framework (loaded lazily).
enum AppleBrightness {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getter: Getter? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Getter.self) }
    private static let setter: Setter? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Setter.self) }

    static func get(_ id: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        guard let getter, getter(id, &value) == 0 else { return nil }
        return value
    }

    static func set(_ id: CGDirectDisplayID, _ value: Float) {
        _ = setter?(id, value)
    }
}

/// Software dimming through the gamma table, for displays that don't speak DDC.
enum GammaDimmer {
    static func set(_ id: CGDirectDisplayID, _ value: Double) {
        let v = Float(max(0.15, min(1, value)))
        CGSetDisplayTransferByFormula(id, 0, v, 1, 0, v, 1, 0, v, 1)
    }

    static func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }
}

struct ModeOption: Identifiable, Hashable {
    let mode: CGDisplayMode
    var id: Int32 { mode.ioDisplayModeID }
    var width: Int { mode.width }
    var height: Int { mode.height }
    var pixelWidth: Int { mode.pixelWidth }
    var refresh: Double { mode.refreshRate }
    var isHiDPI: Bool { mode.pixelWidth > mode.width }

    /// Identifies the "resolution" independent of refresh rate.
    var sizeKey: String { "\(width)x\(height)@\(pixelWidth)" }
    var sizeLabel: String { "\(width) × \(height)" + (isHiDPI ? "  HiDPI" : "") }
    var refreshLabel: String { refresh > 0 ? "\(Int(refresh.rounded())) Hz" : "Default" }

    static func == (a: ModeOption, b: ModeOption) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum DisplayModes {
    static func all(for id: CGDirectDisplayID) -> [ModeOption] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        var seen = Set<String>()
        return modes
            .filter { $0.isUsableForDesktopGUI() }
            .map(ModeOption.init)
            .filter { seen.insert("\($0.sizeKey)/\(Int($0.refresh.rounded()))").inserted }
            .sorted { ($0.width, $0.isHiDPI ? 1 : 0, $0.refresh) > ($1.width, $1.isHiDPI ? 1 : 0, $1.refresh) }
    }

    static func current(for id: CGDirectDisplayID) -> ModeOption? {
        CGDisplayCopyDisplayMode(id).map(ModeOption.init)
    }

    @discardableResult
    static func apply(_ option: ModeOption, to id: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, id, option.mode, nil)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}

enum Mirroring {
    static var isMirrored: Bool {
        onlineDisplays().contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    static func setMirrored(_ on: Bool) {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        let main = CGMainDisplayID()
        let primary = onlineDisplays().first { CGDisplayIsBuiltin($0) != 0 } ?? main
        let unmirrored: CGDirectDisplayID = 0  // kCGNullDirectDisplay, which some SDKs import as an optional
        for id in onlineDisplays() where id != primary {
            CGConfigureDisplayMirrorOfDisplay(config, id, on ? primary : unmirrored)
        }
        CGCompleteDisplayConfiguration(config, .permanently)
    }

    static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }
}
