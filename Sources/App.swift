import ServiceManagement
import SwiftUI

@main
struct DisplayDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: delegate.manager) { SettingsWindow.shared.show(manager: delegate.manager, keys: delegate.keys, shortcuts: delegate.shortcuts) }
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = DisplayManager()
    lazy var keys = MediaKeys(manager: manager)
    lazy var shortcuts = Shortcuts(manager: manager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ReleaseApp.pause()
        quitOnSIGTERM()
        if keys.brightnessEnabled || keys.volumeEnabled { keys.start() }
        shortcuts.start()
        _ = Updater.shared  // starts scheduled update checks in release builds
        let showWindow = UserDefaults.standard.object(forKey: "showWindowAtLaunch") as? Bool ?? true
        if showWindow && !launchedAsLoginItem { SettingsWindow.shared.show(manager: manager, keys: keys, shortcuts: shortcuts) }

        Telemetry.send("TelemetryDeck.Session.started")
        Telemetry.send("App.launched", payload: [
            "atLogin": "\(launchedAsLoginItem)",
            "launchAtLogin": "\(SMAppService.mainApp.status == .enabled)",
            "brightnessKeys": "\(keys.brightnessEnabled)",
            "volumeKeys": "\(keys.volumeEnabled)",
            "keysControlAllDisplays": "\(keys.controlsAllDisplays)",
            "followBuiltinBrightness": "\(DisplayManager.followsBuiltin)",
            "dimBelowMinimum": "\(Display.dimsBelowMinimum)",
            "shortcuts": "\(shortcuts.combos.count)",
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
        SettingsWindow.shared.show(manager: manager, keys: keys, shortcuts: shortcuts)
        return true
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.displays.forEach { $0.turnOnBeforeQuitting() }
        if GammaDimmer.isActive { GammaDimmer.restoreAll() }
        ReleaseApp.resume()
    }

    private var sigterm: DispatchSourceSignal?

    /// `pkill` and logging out send SIGTERM, which would otherwise end the app without `applicationWillTerminate`.
    private func quitOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm?.setEventHandler { NSApp.terminate(nil) }
        sigterm?.resume()
    }
}

/// The app's name as macOS shows it: "DisplayDeck Dev" for development builds, so they're easy to tell from the release.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "DisplayDeck"

/// Development builds are a separate app ("DisplayDeck Dev", `….dev`) that can be installed next to the release. Two
/// copies talking DDC (or both following the built-in display) fight each other, so while a development build runs,
/// the release is quit, and it's opened again when the development build quits.
private enum ReleaseApp {
    static let bundleID = "com.rahulgurung.DisplayDeck"
    private static var pausedURL: URL?

    static func pause() {
        guard Bundle.main.bundleIdentifier != bundleID else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            pausedURL = app.bundleURL
            app.terminate()
        }
    }

    static func resume() {
        guard let pausedURL else { return }
        // `open` rather than NSWorkspace: this process exits right after, which can drop NSWorkspace's request.
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-g", pausedURL.path])
    }
}
