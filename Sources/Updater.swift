import AppKit
import Observation
import Sparkle

/// In-app updates through Sparkle (https://sparkle-project.org).
/// Only builds that carry a feed URL can update; development builds don't, so they never replace themselves with a
/// release (which is signed differently and would lose the Accessibility permission).
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    let isAvailable = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private override init() {
        super.init()
        guard isAvailable else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheckForUpdates = canCheck }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
        Telemetry.send("Updates.checked")
    }

    // MARK: SPUStandardUserDriverDelegate

    // DisplayDeck lives in the menu bar with no Dock icon. Let Sparkle show scheduled updates itself, and bring the
    // app forward when it does so the alert isn't hidden behind other windows.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate && !state.userInitiated {
            NSApp.activate()
        }
    }
}
