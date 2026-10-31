import AppIntents
import Foundation

// Actions for the Shortcuts app (and so automations and Focus filters). They run inside DisplayDeck, which macOS
// launches first if needed. build.sh generates the metadata Shortcuts reads (Metadata.appintents) when the Xcode tool
// for it is available.

/// A connected display, identified by `Display.monitorKey`, so a shortcut keeps working after a reconnect.
struct DisplayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
    static let defaultQuery = DisplayQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct DisplayQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DisplayEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DisplayEntity] {
        try await MainActor.run {
            try IntentContext.app().manager.displays.map { DisplayEntity(id: $0.monitorKey, name: $0.name) }
        }
    }
}

/// One input of a connected monitor, e.g. "BenQ EX271Q – USB-C".
struct InputEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Input"
    static let defaultQuery = InputQuery()

    /// "<monitorKey>|<input value>".
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct InputQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [InputEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [InputEntity] {
        try await MainActor.run {
            try IntentContext.app().manager.displays.flatMap { display in
                display.inputs.map { InputEntity(id: "\(display.monitorKey)|\($0.value)", name: "\(display.name) – \(display.label(for: $0))") }
            }
        }
    }
}

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Preset"
    static let defaultQuery = PresetQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PresetQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        try await MainActor.run { try IntentContext.app().presets.all.map { PresetEntity(id: $0.id, name: $0.name) } }
    }
}

enum DisplaySetting: String, AppEnum {
    case brightness, contrast, volume

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Setting"
    static let caseDisplayRepresentations: [DisplaySetting: DisplayRepresentation] = [
        .brightness: "Brightness", .contrast: "Contrast", .volume: "Volume",
    ]
}

struct SetDisplayLevelIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Level"
    static let description = IntentDescription("Sets a display’s brightness, or a monitor’s contrast or speaker volume.")

    @Parameter(title: "Setting", default: .brightness) var setting: DisplaySetting
    @Parameter(title: "Display") var display: DisplayEntity
    @Parameter(title: "Level", inclusiveRange: (0, 100)) var level: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$setting) of \(\.$display) to \(\.$level)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let target = try await IntentContext.connected(display.id, named: display.name)
        let value = Double(level) / 100
        switch setting {
        case .brightness:
            target.setBrightness(value)
        case .contrast:
            guard target.contrast != nil else { throw IntentFailure("\(target.name) has no contrast control.") }
            target.setContrast(value)
        case .volume:
            guard target.volume != nil else { throw IntentFailure("\(target.name) has no speakers.") }
            target.setVolume(value)
        }
        Telemetry.send("Intent.performed", payload: ["action": "level"])
        return .result()
    }
}

struct ApplyPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Preset"
    static let description = IntentDescription("Sets every display to a DisplayDeck preset.")

    @Parameter(title: "Preset") var preset: PresetEntity

    static var parameterSummary: some ParameterSummary { Summary("Apply \(\.$preset)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        let app = try IntentContext.app()
        guard let saved = app.presets.preset(preset.id) else { throw IntentFailure("The preset “\(preset.name)” no longer exists.") }
        await IntentContext.waitForDisplays()
        app.presets.apply(saved, to: app.manager.displays)
        Telemetry.send("Intent.performed", payload: ["action": "preset"])
        return .result()
    }
}

struct SwitchInputIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Monitor Input"
    static let description = IntentDescription("Switches a monitor to one of its inputs.")

    @Parameter(title: "Input") var input: InputEntity

    static var parameterSummary: some ParameterSummary { Summary("Switch to \(\.$input)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        let parts = input.id.split(separator: "|")
        let name = String(input.name.split(separator: "–").first ?? "").trimmingCharacters(in: .whitespaces)
        guard parts.count == 2, let value = UInt8(parts[1]) else { throw IntentFailure("Choose the input again.") }
        let target = try await IntentContext.connected(String(parts[0]), named: name)
        guard let source = target.inputs.first(where: { $0.value == value }) else {
            throw IntentFailure("\(target.name) doesn’t list that input any more.")
        }
        target.setInput(source)
        Telemetry.send("Intent.performed", payload: ["action": "input"])
        return .result()
    }
}

struct SetMirroringIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Display Mirroring"
    static let description = IntentDescription("Turns display mirroring on or off.")

    @Parameter(title: "Mirroring", default: true) var on: Bool

    static var parameterSummary: some ParameterSummary { Summary("Turn mirroring \(\.$on)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        try IntentContext.app().manager.setMirrored(on)
        Telemetry.send("Intent.performed", payload: ["action": "mirroring"])
        return .result()
    }
}

/// An error shown in the Shortcuts app.
struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// Reaches the running app's displays and presets from an action.
@MainActor
enum IntentContext {
    /// Set by AppDelegate as soon as it exists, before an action can run.
    static weak var delegate: AppDelegate?
    /// When DisplayDeck started: right after a launch (a shortcut can launch it), macOS may report a monitor a moment
    /// after the built-in display.
    static var launched = Date()

    static func app() throws -> AppDelegate {
        guard let delegate else { throw IntentFailure("DisplayDeck isn’t ready yet. Try again in a moment.") }
        return delegate
    }

    /// Waits (up to 10 s) for the first seconds after launch and for monitors connecting over DDC, which report
    /// placeholder levels meanwhile.
    static func waitForDisplays() async {
        for _ in 0..<40 {
            let settling = Date().timeIntervalSince(launched) < 5
            guard settling || ((try? app())?.manager.displays.contains(where: \.probing) ?? false) else { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// The display, once it's listed and connected (up to 10 s, e.g. right after launch or a wake).
    static func connected(_ monitorKey: String, named name: String) async throws -> Display {
        for _ in 0..<40 {
            if let display = try app().manager.displays.first(where: { $0.monitorKey == monitorKey }), !display.probing {
                guard !display.isOff else { throw IntentFailure("\(name) is turned off in DisplayDeck.") }
                return display
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw IntentFailure("\(name) isn’t connected.")
    }
}
