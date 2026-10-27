import AppKit
import SwiftUI

/// The panel shown from the menu bar icon: one card per display, then mirroring and the footer actions.
struct MenuView: View {
    let manager: DisplayManager
    let presets: Presets
    let openSettings: () -> Void

    /// Keeps the built-in display's slider in step with macOS (its keys, auto-brightness) while the menu is open.
    @State private var brightnessRefresh: Timer?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(manager.displays) { display in
                DisplayCard(display: display, canTurnOff: manager.canTurnOff(display))
            }

            // Only once there are presets, so the menu is unchanged for people who don't use them.
            if !presets.all.isEmpty {
                PresetsRow(manager: manager, presets: presets) {
                    UserDefaults.standard.set("presets", forKey: "settingsTab")
                    openSettings()
                }
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
                Text(appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Spacer()
                FooterButton(title: "Refresh displays", systemImage: "arrow.clockwise") { manager.reload() }
                FooterButton(title: "Settings…", systemImage: "gearshape") { openSettings() }
                    .keyboardShortcut(",")
                FooterButton(title: "Quit \(appName)", systemImage: "power") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(10)
        .frame(width: 340)
        .onAppear {
            manager.displays.forEach { $0.refreshInput(); $0.refreshBrightness(); $0.refreshPower() }
            brightnessRefresh?.invalidate()
            brightnessRefresh = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [manager] _ in
                manager.displays.forEach { $0.refreshBrightness() }
            }
            Telemetry.send("Menu.opened")
        }
        .onDisappear {
            brightnessRefresh?.invalidate()
            brightnessRefresh = nil
        }
    }
}

struct DisplayCard: View {
    let display: Display
    /// False for the last display you can see.
    var canTurnOff = true

    @AppStorage("separateRefreshMenu") private var separateRefreshMenu = false
    @AppStorage("dimBelowMinimum") private var dimBelowMinimum = false
    @AppStorage("showTurnOffButton") private var showTurnOffButton = false

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
                // Takes the free width itself rather than leaving it to a Spacer, which would add a gap on each side:
                // with the turn-off button, the header is tight enough that "Built-in Retina Display" only just fits.
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                HStack(spacing: 2) {
                    if !separateRefreshMenu && !display.isOff {
                        ModeMenu(display: display, includesRefresh: true, shortLabel: showTurnOffButton)
                    }
                    // Still shown for a display that's off, so it can always be turned on again.
                    if showTurnOffButton || display.isOff {
                        PowerButton(display: display, canTurnOff: canTurnOff)
                    }
                }
            }

            if display.isOff {
                HStack(spacing: 10) {
                    Text(display.isWaking ? "Turning on…" : "Turned off")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                    Spacer()
                    Button("Turn On") { display.turnOn() }
                        .controlSize(.small)
                        .disabled(display.isWaking)
                }
            } else {
                controls
            }
        }
        .padding(12)
        .background(CardBackground())
    }

    @ViewBuilder private var controls: some View {
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
            // A moon below 0, where the monitor is at its minimum and DisplayDeck dims it further.
            SliderRow(symbol: display.brightness < 0 ? "moon.fill" : "sun.max.fill", label: "Brightness", value: display.brightness,
                      range: (dimBelowMinimum ? display.minBrightness : 0)...1, disabled: display.probing) {
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
            if !display.inputs.isEmpty {
                InputRow(display: display)
            }
        }
    }
}

/// The brightness symbol crossed out, like SF Symbols' own slashed icons (which have no sun): the line is cut out of
/// the sun with a gap on each side. A template image, so it's tinted like the symbols around it.
private enum SunSlash {
    static let image: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let sun = NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            if let sun {
                sun.draw(in: NSRect(x: rect.midX - sun.size.width / 2, y: rect.midY - sun.size.height / 2,
                                    width: sun.size.width, height: sun.size.height))
            }
            let line = NSBezierPath()
            // Top right to bottom left (y goes up here).
            line.move(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2))
            line.line(to: NSPoint(x: rect.minX + 2, y: rect.minY + 2))
            line.lineCapStyle = .round
            // Clear a wider band first, so the sun has a gap on each side of the line.
            NSGraphicsContext.current?.compositingOperation = .clear
            line.lineWidth = 3.6
            line.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.set()
            line.lineWidth = 1.4
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// Turns a display off (DDC standby, or a black picture) and on again.
private struct PowerButton: View {
    let display: Display
    let canTurnOff: Bool

    var body: some View {
        Button { display.isOff ? display.turnOn() : display.turnOff() } label: {
            // Not the power symbol, which the footer uses for quitting, nor the moon that marks dimming below the
            // minimum.
            Image(nsImage: SunSlash.image)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(display.isOff ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .disabled(display.isWaking || (!display.isOff && !canTurnOff))
        .help(display.isOff ? "Turn On" : canTurnOff ? "Turn Off" : "The only display you can see can’t be turned off")
        .accessibilityLabel(display.isOff ? "Turn On \(display.name)" : "Turn Off \(display.name)")
    }
}

/// Input source picker, laid out like a slider row so it lines up with the controls above it. Input codes vary by
/// manufacturer and model, so the inputs can be renamed in place.
private struct InputRow: View {
    let display: Display

    @State private var renaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text("Input")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if renaming {
                    Button("Reset") { display.resetInputNames() }
                        .controlSize(.small)
                        .disabled(display.inputNames.isEmpty)
                        .help("Use the default name for every input")
                    Button("Done") { renaming = false }
                        .controlSize(.small)
                } else {
                    Menu {
                        Picker("Input", selection: Binding(
                            get: { display.currentInput },
                            set: { if let input = $0 { display.setInput(input) } }
                        )) {
                            ForEach(display.inputs) { input in
                                Label(display.label(for: input), systemImage: input.symbol).tag(Optional(input))
                            }
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Button("Rename Inputs…") { renaming = true }
                    } label: {
                        PillLabel(text: display.currentInput.map(display.label(for:)) ?? "Choose input")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Switch the monitor's input")
                }
            }

            if renaming {
                // Each field keeps its connector's name beside it, since the placeholder disappears once filled in.
                VStack(spacing: 4) {
                    ForEach(display.inputs) { input in
                        HStack(spacing: 6) {
                            Image(systemName: input.symbol)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(display.defaultName(for: input))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 84, alignment: .leading)
                            TextField("Name", text: Binding(
                                get: { display.inputNames[input.value] ?? "" },
                                set: { display.renameInput(input, to: $0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .accessibilityLabel("Name for \(display.defaultName(for: input))")
                            .onSubmit { renaming = false }
                        }
                    }
                }
                .padding(.leading, 32)
            }
        }
    }
}

/// Resolution menu shown as a pill in a display card. When `includesRefresh` is set it also lists refresh rates
/// and shows the current rate in its label, as long as there is more than one to choose from.
private struct ModeMenu: View {
    let display: Display
    let includesRefresh: Bool
    /// Just the resolution in the label, to leave the header room for the turn-off button; the refresh rate is still
    /// in the menu.
    var shortLabel = false

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
            PillLabel(text: showsRefresh && !shortLabel ? "\(size) · \(current?.refreshLabel ?? "")" : size)
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

/// Presets in a drop-down. The pill names the preset in effect: the one every display's levels still match.
private struct PresetsRow: View {
    let manager: DisplayManager
    let presets: Presets
    let editPresets: () -> Void

    var body: some View {
        let current = presets.matching(manager.displays)
        HStack {
            Label("Presets", systemImage: "slider.horizontal.3")
            Spacer()
            Menu {
                ForEach(presets.all) { preset in
                    Button { presets.apply(preset, to: manager.displays) } label: {
                        if preset.id == current?.id { Label(preset.name, systemImage: "checkmark") } else { Text(preset.name) }
                    }
                }
                Divider()
                Button("Edit Presets…", action: editPresets)
            } label: {
                PillLabel(text: current?.name ?? "Choose")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Apply a preset")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(CardBackground())
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
    /// Brightness can start below 0 when dimming below the monitor's minimum is on.
    var range: ClosedRange<Double> = 0...1
    var disabled = false
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Slider(value: Binding(get: { value }, set: onChange), in: range)
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
