import Foundation

/// Saved levels for every display, applied together: e.g. "Day", "Night" or "Movie".
struct Preset: Codable, Identifiable, Equatable {
    struct Levels: Codable, Equatable {
        /// The display's name when the preset was saved, to describe the preset when that display isn't connected.
        var display: String
        var brightness: Double?
        var contrast: Double?
        var volume: Double?
    }

    var id = UUID()
    var name: String
    /// By `Display.monitorKey`.
    var levels: [String: Levels]
}

/// The user's presets, kept in order in UserDefaults.
@Observable
final class Presets {
    private(set) var all: [Preset] = []

    private static let defaultsKey = "presets"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            all = saved
        }
    }

    func preset(_ id: UUID) -> Preset? { all.first { $0.id == id } }

    /// Saves the current levels of every display that's on as a new preset, named "Preset 1", "Preset 2" and so on.
    @discardableResult
    func saveCurrent(from displays: [Display]) -> Preset {
        let taken = Set(all.map(\.name))
        let name = (1...).lazy.map { "Preset \($0)" }.first { !taken.contains($0) }!
        let preset = Preset(name: name, levels: Self.levels(of: displays))
        all.append(preset)
        save()
        return preset
    }

    /// Replaces a preset's levels with the current ones, keeping its name and any shortcut.
    func update(_ id: UUID, from displays: [Display]) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].levels = Self.levels(of: displays)
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].name = name
        save()
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
        save()
    }

    /// Sets every connected display the preset has levels for. The built-in display goes first, so monitors following
    /// it don't move again afterwards; a monitor following it takes the preset's level as its new balance, as when its
    /// slider is moved.
    func apply(_ preset: Preset, to displays: [Display]) {
        for display in displays.sorted(by: { $0.isBuiltin && !$1.isBuiltin }) where !display.isOff {
            guard let levels = preset.levels[display.monitorKey] else { continue }
            if let brightness = levels.brightness, abs(brightness - display.brightness) >= 0.005 {
                display.setBrightness(brightness)
            }
            if let contrast = levels.contrast, display.contrast != nil { display.setContrast(contrast) }
            if let volume = levels.volume, display.volume != nil { display.setVolume(volume) }
        }
        HUD.shared.show(symbol: "slider.horizontal.3", value: nil, caption: preset.name)
        Telemetry.send("Preset.applied")
    }

    /// The preset matching every connected display's current levels, so the menu can show it's in effect.
    func matching(_ displays: [Display]) -> Preset? {
        let on = displays.filter { !$0.isOff }
        return all.first { preset in
            let shared = on.filter { preset.levels[$0.monitorKey] != nil }
            return !shared.isEmpty && shared.allSatisfy { display in
                let levels = preset.levels[display.monitorKey]!
                return Self.close(levels.brightness, display.brightness) && Self.close(levels.contrast, display.contrast)
                    && Self.close(levels.volume, display.volume)
            }
        }
    }

    /// A short description, e.g. "BenQ EX271Q 55% · Built-in Retina Display 72%".
    func summary(of preset: Preset, displays: [Display]) -> String {
        let order = displays.map(\.monitorKey)
        return preset.levels
            .sorted { (order.firstIndex(of: $0.key) ?? .max, $0.value.display) < (order.firstIndex(of: $1.key) ?? .max, $1.value.display) }
            .map { _, levels in
                levels.brightness.map { "\(levels.display) \(Int(($0 * 100).rounded()))%" } ?? levels.display
            }
            .joined(separator: " · ")
    }

    private static func levels(of displays: [Display]) -> [String: Preset.Levels] {
        var levels: [String: Preset.Levels] = [:]
        for display in displays where !display.isOff && !display.probing {
            display.refreshBrightness()  // The built-in display's level may have changed with its own keys.
            levels[display.monitorKey] = Preset.Levels(display: display.name, brightness: display.brightness,
                                                       contrast: display.contrast, volume: display.volume)
        }
        return levels
    }

    /// Within half a percent. A level the preset doesn't set, or the display doesn't report right now (some monitors
    /// miss a request at startup), is skipped, as `apply` skips it.
    private static func close(_ saved: Double?, _ current: Double?) -> Bool {
        guard let saved, let current else { return true }
        return abs(saved - current) < 0.005
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }
}
