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
        _ = Updater.shared  // starts scheduled update checks in release builds
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
