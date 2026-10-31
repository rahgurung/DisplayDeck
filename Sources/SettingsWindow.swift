import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// Window shown when DisplayDeck is opened from Finder, Spotlight or Launchpad, and from the menu's Settings button.
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show(manager: DisplayManager, keys: MediaKeys, shortcuts: Shortcuts, presets: Presets, schedule: Schedule) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(manager: manager, keys: keys, shortcuts: shortcuts,
                                                                        presets: presets, schedule: schedule))
            let window = NSWindow(contentViewController: controller)
            window.title = appName
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // The window was sized before the style change above; size it to the content again so nothing is cut off.
            window.setContentSize(controller.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Telemetry.send("Settings.opened")
    }
}

private enum SettingsTab: String {
    case general, displays, keyboard, shortcuts, presets

    var title: String { rawValue.capitalized }
}

private struct SettingsView: View {
    let manager: DisplayManager
    let keys: MediaKeys
    let shortcuts: Shortcuts
    let presets: Presets
    let schedule: Schedule

    @AppStorage("settingsTab") private var tab = SettingsTab.general
    @AppStorage("brightnessKeys") private var brightnessKeys = true
    @AppStorage("volumeKeys") private var volumeKeys = false
    @AppStorage("keysControlAllDisplays") private var keysControlAllDisplays = false
    @AppStorage("showWindowAtLaunch") private var showAtLaunch = true
    @AppStorage("shareAnalytics") private var shareAnalytics = true
    @AppStorage("separateRefreshMenu") private var separateRefreshMenu = false
    @AppStorage("followBuiltinBrightness") private var followBuiltin = false
    @AppStorage("dimBelowMinimum") private var dimBelowMinimum = false
    @AppStorage("showTurnOffButton") private var showTurnOffButton = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()
    @State private var autoUpdate = Updater.shared.automaticallyChecksForUpdates

    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(appName)
                    .font(.title2.bold())
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Click \(Text(Image(nsImage: MenuBarIcon.image)).baselineOffset(-3)) in the menu bar to adjust your displays.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            // Tabs keep the window short enough for a 1440 × 900 screen as settings are added. A segmented control
            // rather than TabView, whose tab bar drew blurry labels in this transparent-titlebar window.
            Picker("Settings", selection: $tab) {
                ForEach(tabs, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            GroupBox {
                switch tab {
                case .general: generalTab
                case .displays: displaysTab
                case .keyboard: keyboardTab
                case .shortcuts: shortcutsTab
                case .presets: presetsTab
                }
            }
            .onAppear {
                if !tabs.contains(tab) { tab = .general }
            }

            HStack {
                Link("Source on GitHub", destination: URL(string: "https://github.com/rahgurung/DisplayDeck")!)
                    .font(.callout)
                Spacer()
                Button("Quit \(appName)") { NSApp.terminate(nil) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(width: 460)
        // Ask for the full height, so the window grows to fit each tab rather than squeezing it.
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(poll) { _ in trusted = AXIsProcessTrusted() }
    }

    /// Five fit the window's width; updates are in General.
    private let tabs: [SettingsTab] = [.general, .displays, .keyboard, .shortcuts, .presets]

    private var generalTab: some View {
        SettingsPage {
            SwitchRow(title: "Launch at login", detail: nil, isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Divider()
            SwitchRow(title: "Show this window when DisplayDeck opens",
                      detail: "Otherwise it starts quietly in the menu bar.", isOn: $showAtLaunch)
            if Telemetry.isAvailable {
                Divider()
                SwitchRow(title: "Share anonymous usage stats",
                          detail: "Versions and which features you use. Nothing personal.",
                          isOn: $shareAnalytics)
            }
            // Updates only exist in release builds, which carry a feed URL.
            if Updater.shared.isAvailable {
                Divider()
                SwitchRow(title: "Automatically check for updates",
                          detail: "Checks once a day and asks before installing.", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in Updater.shared.automaticallyChecksForUpdates = on }
                HStack {
                    Spacer()
                    Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                        .controlSize(.small)
                        .disabled(!Updater.shared.canCheckForUpdates)
                }
            }
        }
    }

    private var displaysTab: some View {
        SettingsPage {
            SwitchRow(title: "Monitors follow the built-in display",
                      detail: "Including auto-brightness. Move a monitor’s slider to keep it brighter or dimmer.",
                      isOn: $followBuiltin)
                .onChange(of: followBuiltin) { _, _ in manager.updateBrightnessSync(learnCurves: true) }
            Divider()
            SwitchRow(title: "Dim monitors below their minimum",
                      detail: "Drag a monitor’s brightness below 0, or keep pressing brightness down, to darken it further in software.",
                      isOn: $dimBelowMinimum)
                .onChange(of: dimBelowMinimum) { _, on in if !on { manager.displays.forEach { $0.clampBrightness() } } }
            Divider()
            SwitchRow(title: "Show a turn-off button on each display",
                      detail: "Puts a monitor to sleep, or blacks out a display that can’t sleep. Click it again to turn it back on.",
                      isOn: $showTurnOffButton)
            Divider()
            SwitchRow(title: "Show refresh rate as a separate menu",
                      detail: "Otherwise it’s shown next to the resolution.", isOn: $separateRefreshMenu)
        }
    }

    private var keyboardTab: some View {
        SettingsPage {
            SwitchRow(title: "Brightness keys control monitors",
                      detail: brightnessKeysDetail, isOn: $brightnessKeys)
                .onChange(of: brightnessKeys) { _, on in if on { keys.start() } }
            Divider()
            SwitchRow(title: "Volume keys control monitor speakers",
                      detail: "For monitors with built-in speakers.", isOn: $volumeKeys)
                .onChange(of: volumeKeys) { _, on in if on { keys.start() } }
            if brightnessKeys || volumeKeys {
                Divider()
                SwitchRow(title: "Keys adjust all displays at once",
                          detail: allDisplaysDetail, isOn: $keysControlAllDisplays)
                Divider()
                AccessibilityRow(trusted: trusted)
            }
        }
    }

    /// With following on, a brightness key that changes the built-in display reaches every monitor anyway, so the
    /// all-displays switch only matters over a monitor (and for the volume keys).
    private var brightnessKeysDetail: String {
        switch (followBuiltin, keysControlAllDisplays) {
        case (true, true): "Change the built-in display, and monitors follow it."
        case (true, false): "Over a monitor, adjusts just that one. Elsewhere, monitors follow the built-in display."
        case (false, true): "Adjusts every monitor."
        case (false, false): "Adjusts the monitor under your pointer."
        }
    }

    private var allDisplaysDetail: String {
        followBuiltin
            ? "Otherwise the display under your pointer; monitors follow the built-in display either way. Hold ⌃ Control to do the other for one press."
            : "Otherwise the display under your pointer. Hold ⌃ Control to do the other for one press."
    }

    private var shortcutsTab: some View {
        SettingsPage {
            Text("Shortcuts work on any keyboard and in every app, without Accessibility access. Brightness, contrast and volume change the same displays as the keys (see Keyboard). System shortcuts like ⌘Space can’t be used.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Scrolls once there are many rows (monitors with several inputs, presets), so Settings still fits a
            // 1440 × 900 screen.
            if shortcutRows > 13 {
                ScrollView {
                    shortcutList
                        .padding(.trailing, 14)
                }
                .frame(height: 420)
            } else {
                shortcutList
            }
        }
        .onAppear { shortcuts.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in shortcuts.refresh() }
    }

    private var inputDisplays: [Display] { manager.displays.filter { $0.source == .ddc && !$0.inputs.isEmpty } }

    private var shortcutRows: Int {
        ShortcutAction.levels.count + presets.all.count + inputDisplays.reduce(0) { $0 + $1.inputs.count }
    }

    private var shortcutList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ShortcutAction.levels, id: \.self) { action in
                ShortcutRow(title: action.title, action: action, shortcuts: shortcuts)
            }
            if !presets.all.isEmpty {
                Divider()
                Text("Presets")
                    .font(.callout.weight(.medium))
                ForEach(presets.all) { preset in
                    ShortcutRow(title: preset.name, action: .preset(preset.id), shortcuts: shortcuts)
                }
            }
            ForEach(inputDisplays) { display in
                Divider()
                Text("\(display.name) inputs")
                    .font(.callout.weight(.medium))
                ForEach(display.inputs) { input in
                    ShortcutRow(title: display.label(for: input),
                                action: .input(monitor: display.monitorKey, value: input.value), shortcuts: shortcuts)
                }
            }
        }
    }

    private var presetsTab: some View {
        SettingsPage {
            Text("Save the current brightness, contrast and volume of every display, then apply them all at once from the menu or a shortcut (see Shortcuts).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Scrolls once there are many presets and rules, so Settings still fits a 1440 × 900 screen.
            if presets.all.count + schedule.rules.count > 6 {
                ScrollView {
                    presetsList
                        .padding(.trailing, 14)
                }
                .frame(height: 480)
            } else {
                presetsList
            }
        }
    }

    private var presetsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(presets.all) { preset in
                Divider()
                PresetRow(preset: preset, presets: presets, manager: manager) {
                    shortcuts.set(nil, for: .preset(preset.id))
                    schedule.presetDeleted(preset.id)
                    presets.delete(preset.id)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Save Current Levels as Preset") { presets.saveCurrent(from: manager.displays) }
                    .controlSize(.small)
            }
            Divider()
            Text("Schedule")
                .font(.callout.weight(.medium))
            Text("Apply a preset by itself at a time of day, or at sunrise or sunset. It fades in over two minutes, and stops if you change the brightness meanwhile.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(schedule.rules) { rule in
                ScheduleRuleRow(rule: rule, schedule: schedule, presets: presets)
            }
            if schedule.needsLocation {
                SunLocationRow(schedule: schedule)
            }
            HStack {
                Spacer()
                Button("Add Rule") { schedule.addRule() }
                    .controlSize(.small)
                    .disabled(presets.all.isEmpty)
                    .help(presets.all.isEmpty ? "Save a preset first" : "Apply a preset at a time, or at sunrise or sunset")
            }
        }
    }

}

/// The rows of one settings tab.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SwitchRow: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Wrap instead of truncating when the window is shorter than the tab needs.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// One schedule rule: when (a time, or sunrise or sunset with an offset), and which preset.
private struct ScheduleRuleRow: View {
    let rule: ScheduleRule
    let schedule: Schedule
    let presets: Presets

    private static let offsets = [-60, -30, 0, 30, 60]

    var body: some View {
        HStack(spacing: 6) {
            Picker("When", selection: Binding(get: { rule.trigger }, set: { trigger in
                var changed = rule
                changed.trigger = trigger
                changed.minutes = trigger == .time ? 21 * 60 : 0
                schedule.update(changed)
            })) {
                Text("At").tag(ScheduleRule.Trigger.time)
                Text("Sunrise").tag(ScheduleRule.Trigger.sunrise)
                Text("Sunset").tag(ScheduleRule.Trigger.sunset)
            }
            .labelsHidden()
            .fixedSize()
            if rule.trigger == .time {
                DatePicker("Time", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: rule.minutes / 60, minute: rule.minutes % 60, second: 0, of: Date())!
                }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    var changed = rule
                    changed.minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    schedule.update(changed)
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
            } else {
                Picker("Offset", selection: Binding(get: { rule.minutes }, set: { minutes in
                    var changed = rule
                    changed.minutes = minutes
                    schedule.update(changed)
                })) {
                    ForEach(Self.offsets, id: \.self) { Text(Self.label(offset: $0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Picker("Preset", selection: Binding(get: { rule.preset }, set: { preset in
                var changed = rule
                changed.preset = preset
                schedule.update(changed)
            })) {
                ForEach(presets.all) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button { schedule.delete(rule.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this rule")
        }
        .controlSize(.small)
    }

    private static func label(offset: Int) -> String {
        switch offset {
        case 0: "exactly"
        case let minutes where abs(minutes) >= 60: "\(abs(minutes) / 60) h \(minutes < 0 ? "before" : "after")"
        case let minutes: "\(abs(minutes)) min \(minutes < 0 ? "before" : "after")"
        }
    }
}

/// Where sunrise and sunset are worked out for: today's times once there's a location, and a button to find it.
private struct SunLocationRow: View {
    let schedule: Schedule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                if let sun = schedule.todaysSun {
                    Text("Today: sunrise \(sun.rise, style: .time), sunset \(sun.set, style: .time)")
                } else if schedule.location == nil {
                    Text("Sunrise and sunset need your location.")
                } else {
                    Text("The sun doesn’t rise or set here today.")
                }
                Spacer()
                Button(schedule.location == nil ? "Use My Location" : "Update Location") { schedule.findLocation() }
                    .disabled(schedule.locating)
            }
            .font(.caption)
            .controlSize(.small)
            if let error = schedule.locationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One preset: its name (edited in place), what it sets, and Apply, Update and Delete.
private struct PresetRow: View {
    let preset: Preset
    let presets: Presets
    let manager: DisplayManager
    let delete: () -> Void

    @State private var name = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                Text(presets.summary(of: preset, displays: manager.displays))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Apply") { presets.apply(preset, to: manager.displays) }
                .controlSize(.small)
            Button { presets.update(preset.id, from: manager.displays) } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Save the current levels into this preset")
            Button(action: delete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this preset")
        }
        .onAppear { name = preset.name }
        .onChange(of: name) { _, new in
            let trimmed = new.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed != preset.name { presets.rename(preset.id, to: trimmed) }
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let action: ShortcutAction
    let shortcuts: Shortcuts

    @State private var refusal: Refusal?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                ShortcutRecorder(action: action, shortcuts: shortcuts, refusal: $refusal)
            }
            // Spelled out rather than in a tooltip, which takes a while to appear: why the keys just typed were refused,
            // or why the saved shortcut won't run.
            let recording = shortcuts.recording == action
            if let message = recording ? refusal?.detail : shortcuts.problems[action.id] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Why the recorder refused the keys just typed: shown briefly in its button and in full under the row.
private enum Refusal {
    case needsTwoModifiers, usedByMacOS

    var short: String {
        switch self {
        case .needsTwoModifiers: "Add two of ⌃ ⌥ ⌘"
        case .usedByMacOS: "Used by macOS"
        }
    }

    var detail: String {
        switch self {
        case .needsTwoModifiers:
            "Shortcuts need two of ⌃ ⌥ ⌘ (function keys don’t), so they don’t take keys that other apps use, like ⌘C or ⌥←."
        case .usedByMacOS: Shortcuts.usedByMacOSProblem
        }
    }
}

/// Click to record a shortcut, then type it; Esc cancels and Delete clears it.
private struct ShortcutRecorder: View {
    let action: ShortcutAction
    let shortcuts: Shortcuts
    /// Set after keys that can't be a shortcut, until the next key.
    @Binding var refusal: Refusal?

    @State private var monitor: Any?

    private var isRecording: Bool { shortcuts.recording == action }

    var body: some View {
        HStack(spacing: 4) {
            if let problem = shortcuts.problems[action.id], !isRecording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(problem)
                    .accessibilityLabel(problem)
            }
            Button { isRecording ? stop() : start() } label: {
                Text(isRecording ? refusal?.short ?? "Type shortcut…" : shortcuts.combo(for: action)?.description ?? "Record Shortcut")
                    .foregroundStyle(isRecording || shortcuts.combo(for: action) == nil ? .secondary : .primary)
                    .frame(minWidth: 104)
            }
            .controlSize(.small)
            Button { shortcuts.set(nil, for: action) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .help("Clear")
            // Kept in the layout when there's nothing to clear, so the shortcut buttons line up.
            .opacity(shortcuts.combo(for: action) == nil || isRecording ? 0 : 1)
            .disabled(shortcuts.combo(for: action) == nil || isRecording)
        }
        .onDisappear { stop() }
        // Also when a system shortcut like ⌘Space opens something else.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
        // Another recorder was clicked: this one's key monitor goes, or it would outlive the recording.
        .onChange(of: isRecording) { _, recording in if !recording { removeMonitor() } }
    }

    private func start() {
        removeMonitor()
        refusal = nil
        shortcuts.recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete where modifiers.isEmpty:
                shortcuts.set(nil, for: action)
                stop()
            default:
                guard let combo = KeyCombo(event: event) else {
                    NSSound.beep()
                    refusal = .needsTwoModifiers
                    break
                }
                guard !combo.usedByMacOS else {
                    NSSound.beep()
                    refusal = .usedByMacOS
                    break
                }
                shortcuts.set(combo, for: action)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        removeMonitor()
        if isRecording { shortcuts.recording = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct AccessibilityRow: View {
    let trusted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(trusted ? .green : .orange)
            Text(trusted ? "Accessibility access granted" : "Needs Accessibility access to use the keys")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !trusted {
                Button("Open Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .controlSize(.small)
            }
        }
    }
}
