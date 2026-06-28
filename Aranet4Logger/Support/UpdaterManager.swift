import AppKit
import Observation
import Sparkle

/// Owns the Sparkle updater. Created once for the app's lifetime. Starting the updater enables
/// the scheduled background checks configured in Info.plist (SUEnableAutomaticChecks /
/// SUScheduledCheckInterval / SUAutomaticallyUpdate); `checkForUpdates()` backs the manual
/// "Check for Updates…" menu item.
@MainActor
@Observable
final class UpdaterManager {
    private let controller: SPUStandardUpdaterController

    /// Whether a manual check is currently allowed (false while a check is already in flight).
    /// Drives the enabled state of the menu item.
    var canCheckForUpdates = false

    @ObservationIgnored private var observation: NSKeyValueObservation?

    private let driverDelegate = GentleReminderDelegate()

    init() {
        // Don't start the updater in Debug builds. Debug builds carry the placeholder
        // CFBundleVersion ("1" from project.yml), so the live appcast always looks newer — with
        // SUAutomaticallyUpdate a running dev build would silently replace itself with the
        // published Release app. Only Release builds (whose version is stamped from the tag)
        // participate in updates; in Debug the "Check for Updates…" item stays disabled.
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: start,
            updaterDelegate: nil,
            userDriverDelegate: driverDelegate
        )
        // Mirror the updater's readiness into our observable property for the menu. Sparkle
        // delivers KVO changes on the main thread; hop through MainActor to satisfy isolation.
        observation = controller.updater.observe(
            \.canCheckForUpdates, options: [.initial, .new]
        ) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    /// Trigger a user-initiated update check. Activates the app first so Sparkle's update window
    /// comes to the front (the app is an LSUIElement menu bar agent with no regular windows).
    func checkForUpdates() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }
}

/// Opts the background (LSUIElement) app into Sparkle's "gentle reminder" behavior and brings
/// the app to the front when an update prompt is about to be shown, so a scheduled-update alert
/// isn't lost behind other apps.
private final class GentleReminderDelegate: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
