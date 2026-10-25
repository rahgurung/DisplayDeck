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
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(manager: manager, keys: keys)))
            window.title = "DisplayDeck"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
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
}

private struct SettingsView: View {
    let manager: DisplayManager
    let keys: MediaKeys

    @AppStorage("settingsTab") private var tab = SettingsTab.general
    @AppStorage("brightnessKeys") private var brightnessKeys = true
    @AppStorage("volumeKeys") private var volumeKeys = false
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

            // Tabs keep the window short enough for a 1440 × 900 screen as settings are added.
            TabView(selection: $tab) {
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
                .tabItem { Text("General") }
                .tag(SettingsTab.general)

                SettingsPage {
                    SwitchRow(title: "Monitors follow the built-in display",
                              detail: "Including auto-brightness. Move a monitor’s slider to keep it brighter or dimmer.",
                              isOn: $followBuiltin)
                        .onChange(of: followBuiltin) { _, _ in manager.updateBrightnessSync(learnOffsets: true) }
                    Divider()
                    SwitchRow(title: "Show refresh rate as a separate menu",
                              detail: "Otherwise it’s shown next to the resolution.", isOn: $separateRefreshMenu)
                }
                .tabItem { Text("Displays") }
                .tag(SettingsTab.displays)

                SettingsPage {
                    SwitchRow(title: "Brightness keys control monitors",
                              detail: "Adjusts the monitor under your pointer.", isOn: $brightnessKeys)
                        .onChange(of: brightnessKeys) { _, on in if on { keys.start() } }
                    Divider()
                    SwitchRow(title: "Volume keys control monitor speakers",
                              detail: "For monitors with built-in speakers.", isOn: $volumeKeys)
                        .onChange(of: volumeKeys) { _, on in if on { keys.start() } }
                    if brightnessKeys || volumeKeys {
                        Divider()
                        AccessibilityRow(trusted: trusted)
                    }
                }
                .tabItem { Text("Keyboard") }
                .tag(SettingsTab.keyboard)

                if Updater.shared.isAvailable {
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
                    .tabItem { Text("Updates") }
                    .tag(SettingsTab.updates)
                }
            }
            .onAppear {
                if tab == .updates && !Updater.shared.isAvailable { tab = .general }
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
        .onReceive(poll) { _ in trusted = AXIsProcessTrusted() }
    }
}

/// The rows of one settings tab, top-aligned so tabs of different lengths line up.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
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
