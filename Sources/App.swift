import ServiceManagement
import SwiftUI

@main
struct DisplayDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: delegate.manager) { SettingsWindow.shared.show(keys: delegate.keys) }
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = DisplayManager()
    lazy var keys = MediaKeys(manager: manager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if keys.brightnessEnabled || keys.volumeEnabled { keys.start() }
        let showWindow = UserDefaults.standard.object(forKey: "showWindowAtLaunch") as? Bool ?? true
        if showWindow && !launchedAsLoginItem { SettingsWindow.shared.show(keys: keys) }

        Telemetry.send("TelemetryDeck.Session.started")
        Telemetry.send("App.launched", payload: [
            "atLogin": "\(launchedAsLoginItem)",
            "launchAtLogin": "\(SMAppService.mainApp.status == .enabled)",
            "brightnessKeys": "\(keys.brightnessEnabled)",
            "volumeKeys": "\(keys.volumeEnabled)",
        ])
        // Give DDC probing time to settle before reporting how each display is controlled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [manager] in
            let externals = manager.displays.filter { !$0.isBuiltin }
            Telemetry.send("Displays.detected", payload: [
                "total": "\(manager.displays.count)",
                "external": "\(externals.count)",
                "externalDDC": "\(externals.filter { $0.source == .ddc }.count)",
                "externalSoftware": "\(externals.filter { $0.source == .gamma }.count)",
                "externalApple": "\(externals.filter { $0.source == .apple }.count)",
                "withSpeakers": "\(externals.filter { $0.volume != nil }.count)",
            ])
        }
    }

    /// Opening the app again while it's running (Finder, Spotlight, Dock) brings up the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show(keys: keys)
        return true
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        if manager.displays.contains(where: { $0.source == .gamma && $0.brightness < 1 }) {
            GammaDimmer.restoreAll()
        }
    }
}

struct MenuView: View {
    let manager: DisplayManager
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(manager.displays) { display in
                DisplayCard(display: display)
                if display.id != manager.displays.last?.id { Divider() }
            }

            Divider()

            if manager.displays.count > 1 {
                Toggle("Mirror displays", isOn: Binding(get: { manager.isMirrored }, set: { manager.setMirrored($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.callout)
            }

            HStack {
                Button("Refresh Displays") { manager.reload() }
                Spacer()
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",")
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 330)
        .onAppear { Telemetry.send("Menu.opened") }
    }
}

struct DisplayCard: View {
    let display: Display

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(display.name, systemImage: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.headline)
                Spacer()
                Text(display.sourceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SliderRow(symbol: "sun.max.fill", value: display.brightness, disabled: display.probing) { display.setBrightness($0) }
            if let contrast = display.contrast {
                SliderRow(symbol: "circle.lefthalf.filled", value: contrast) { display.setContrast($0) }
            }
            if let volume = display.volume {
                SliderRow(symbol: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", value: volume) { display.setVolume($0) }
            }

            HStack(spacing: 8) {
                Picker("Resolution", selection: Binding(
                    get: { display.currentMode.flatMap { cur in display.resolutionOptions.first { $0.sizeKey == cur.sizeKey } } },
                    set: { if let option = $0 { display.apply(option) } }
                )) {
                    ForEach(display.resolutionOptions) { option in
                        Text(option.sizeLabel).tag(Optional(option))
                    }
                }
                .labelsHidden()

                if display.refreshOptions.count > 1 {
                    Picker("Refresh rate", selection: Binding(
                        get: { display.currentMode },
                        set: { if let option = $0 { display.apply(option) } }
                    )) {
                        ForEach(display.refreshOptions) { option in
                            Text(option.refreshLabel).tag(Optional(option))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }
            .controlSize(.small)
        }
    }
}

struct SliderRow: View {
    let symbol: String
    let value: Double
    var disabled = false
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                .controlSize(.small)
            Text("\(Int((value * 100).rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .disabled(disabled)
    }
}
