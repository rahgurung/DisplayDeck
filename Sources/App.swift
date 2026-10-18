import SwiftUI
import ServiceManagement

@main
struct DisplayDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: delegate.manager, keys: delegate.keys)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        if manager.displays.contains(where: { $0.source == .gamma && $0.brightness < 1 }) {
            GammaDimmer.restoreAll()
        }
    }
}

struct MenuView: View {
    let manager: DisplayManager
    let keys: MediaKeys

    @AppStorage("brightnessKeys") private var brightnessKeys = true
    @AppStorage("volumeKeys") private var volumeKeys = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(manager.displays) { display in
                DisplayCard(display: display)
                if display.id != manager.displays.last?.id { Divider() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if manager.displays.count > 1 {
                    Toggle("Mirror displays", isOn: Binding(get: { manager.isMirrored }, set: { manager.setMirrored($0) }))
                }
                Toggle("Brightness keys control monitors", isOn: $brightnessKeys)
                    .onChange(of: brightnessKeys) { _, on in if on { keys.start() } }
                Toggle("Volume keys control monitor speakers", isOn: $volumeKeys)
                    .onChange(of: volumeKeys) { _, on in if on { keys.start() } }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.callout)

            HStack {
                Button("Refresh Displays") { manager.reload() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 330)
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
