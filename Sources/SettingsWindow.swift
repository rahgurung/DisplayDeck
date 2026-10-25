import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

/// Window shown when DisplayDeck is opened from Finder, Spotlight or Launchpad, and from the menu's Settings button.
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show(manager: DisplayManager, keys: MediaKeys) {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(manager: manager, keys: keys))
            let window = NSWindow(contentViewController: controller)
            window.title = "DisplayDeck"
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
    case general, displays, keyboard, updates

    var title: String { rawValue.capitalized }
}

private struct SettingsView: View {
    let manager: DisplayManager
    let keys: MediaKeys

    @AppStorage("settingsTab") private var tab = SettingsTab.general
    @AppStorage("brightnessKeys") private var brightnessKeys = true
    @AppStorage("volumeKeys") private var volumeKeys = false
    @AppStorage("keysControlAllDisplays") private var keysControlAllDisplays = false
    @AppStorage("showWindowAtLaunch") private var showAtLaunch = true
    @AppStorage("shareAnalytics") private var shareAnalytics = true
    @AppStorage("separateRefreshMenu") private var separateRefreshMenu = false
    @AppStorage("followBuiltinBrightness") private var followBuiltin = false
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
                Text("DisplayDeck")
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
                case .updates: updatesTab
                }
            }
            .onAppear {
                if !tabs.contains(tab) { tab = .general }
            }

            HStack {
                Link("Source on GitHub", destination: URL(string: "https://github.com/rahgurung/DisplayDeck")!)
                    .font(.callout)
                Spacer()
                Button("Quit DisplayDeck") { NSApp.terminate(nil) }
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

    /// Updates only exist in release builds, which carry a feed URL.
    private var tabs: [SettingsTab] {
        Updater.shared.isAvailable ? [.general, .displays, .keyboard, .updates] : [.general, .displays, .keyboard]
    }

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
        }
    }

    private var displaysTab: some View {
        SettingsPage {
            SwitchRow(title: "Monitors follow the built-in display",
                      detail: "Including auto-brightness. Move a monitor’s slider to keep it brighter or dimmer.",
                      isOn: $followBuiltin)
                .onChange(of: followBuiltin) { _, _ in manager.updateBrightnessSync(learnCurves: true) }
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

    private var updatesTab: some View {
        SettingsPage {
            SwitchRow(title: "Automatically check for updates",
                      detail: "Checks once a day and asks before installing.", isOn: $autoUpdate)
                .onChange(of: autoUpdate) { _, on in Updater.shared.automaticallyChecksForUpdates = on }
            Divider()
            HStack {
                Spacer()
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .controlSize(.small)
                    .disabled(!Updater.shared.canCheckForUpdates)
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
