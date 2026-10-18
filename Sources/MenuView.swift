import AppKit
import SwiftUI

/// The panel shown from the menu bar icon: one card per display, then mirroring and the footer actions.
struct MenuView: View {
    let manager: DisplayManager
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(manager.displays) { display in
                DisplayCard(display: display)
            }

            if manager.displays.count > 1 {
                Toggle(isOn: Binding(get: { manager.isMirrored }, set: { manager.setMirrored($0) })) {
                    Label("Mirror displays", systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(CardBackground())
            }

            HStack(spacing: 2) {
                Text("DisplayDeck")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Spacer()
                if Updater.shared.isAvailable {
                    FooterButton(title: "Check for Updates…", systemImage: "arrow.down.circle") { Updater.shared.checkForUpdates() }
                        .disabled(!Updater.shared.canCheckForUpdates)
                }
                FooterButton(title: "Refresh displays", systemImage: "arrow.clockwise") { manager.reload() }
                FooterButton(title: "Settings…", systemImage: "gearshape") { openSettings() }
                    .keyboardShortcut(",")
                FooterButton(title: "Quit DisplayDeck", systemImage: "power") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(10)
        .frame(width: 340)
        .onAppear { Telemetry.send("Menu.opened") }
    }
}

struct DisplayCard: View {
    let display: Display

    @AppStorage("separateRefreshMenu") private var separateRefreshMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(display.sourceLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if !separateRefreshMenu {
                    ModeMenu(display: display, includesRefresh: true)
                }
            }

            if separateRefreshMenu {
                HStack(spacing: 6) {
                    ModeMenu(display: display, includesRefresh: false)
                    if display.refreshChoices.count > 1 {
                        RefreshMenu(display: display)
                    }
                }
                .padding(.leading, 32)
            }

            VStack(spacing: 6) {
                SliderRow(symbol: "sun.max.fill", label: "Brightness", value: display.brightness, disabled: display.probing) {
                    display.setBrightness($0)
                }
                if let contrast = display.contrast {
                    SliderRow(symbol: "circle.lefthalf.filled", label: "Contrast", value: contrast) { display.setContrast($0) }
                }
                if let volume = display.volume {
                    SliderRow(symbol: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", label: "Volume", value: volume) {
                        display.setVolume($0)
                    }
                }
            }
        }
        .padding(12)
        .background(CardBackground())
    }
}

/// Resolution menu shown as a pill in a display card. When `includesRefresh` is set it also lists refresh rates
/// and shows the current rate in its label, as long as there is more than one to choose from.
private struct ModeMenu: View {
    let display: Display
    let includesRefresh: Bool

    var body: some View {
        let current = display.currentMode
        let showsRefresh = includesRefresh && display.refreshChoices.count > 1
        Menu {
            Picker("Resolution", selection: Binding(
                get: { current.flatMap { cur in display.resolutionOptions.first { $0.sizeKey == cur.sizeKey } } },
                set: { if let option = $0 { display.apply(option) } }
            )) {
                ForEach(display.resolutionOptions) { option in
                    Text(option.sizeLabel).tag(Optional(option))
                }
            }
            .pickerStyle(.inline)

            if showsRefresh {
                RefreshPicker(display: display)
            }
        } label: {
            let size = current.map { "\($0.width) × \($0.height)" } ?? "Resolution"
            PillLabel(text: showsRefresh ? "\(size) · \(current?.refreshLabel ?? "")" : size)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(showsRefresh ? "Resolution and refresh rate" : "Resolution")
    }
}

/// Separate refresh rate pill, used when "Show refresh rate as a separate menu" is on.
private struct RefreshMenu: View {
    let display: Display

    var body: some View {
        Menu {
            RefreshPicker(display: display)
        } label: {
            PillLabel(text: display.currentMode?.refreshLabel ?? "Refresh rate")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Refresh rate")
    }
}

private struct RefreshPicker: View {
    let display: Display

    var body: some View {
        let isHiDPI = display.currentMode?.isHiDPI ?? false
        Picker("Refresh Rate", selection: Binding(
            get: { display.currentMode.map { Int($0.refresh.rounded()) } },
            set: { rate in
                if let choice = display.refreshChoices.first(where: { $0.rate == rate }) { display.apply(choice.mode) }
            }
        )) {
            ForEach(display.refreshChoices) { choice in
                let note = choice.changesHiDPI ? (isHiDPI ? "  (turns off HiDPI)" : "  (turns on HiDPI)") : ""
                Text(verbatim: choice.mode.refreshLabel + note).tag(Optional(choice.rate))
            }
        }
        .pickerStyle(.inline)
    }
}

private struct PillLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: text)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(.primary.opacity(0.06)))
        .contentShape(Capsule())
    }
}

struct SliderRow: View {
    let symbol: String
    let label: String
    let value: Double
    var disabled = false
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                .controlSize(.small)
                .accessibilityLabel(label)
            Text("\(Int((value * 100).rounded()))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .disabled(disabled)
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}
