import AppKit
import Sparkle

/// Thin wrapper around Sparkle's standard updater.
///
/// `SPUStandardUpdaterController` wires up the full Sparkle UI (update-available
/// prompt, progress, install-and-relaunch) and drives background checks per the
/// `SUEnableAutomaticChecks` / `SUScheduledCheckInterval` keys in Info.plist.
/// The update feed and the EdDSA public key that authenticates it also come
/// from Info.plist (`SUFeedURL`, `SUPublicEDKey`).
///
/// Auto-update only functions in a proper signed `.app` bundle; when running
/// unbundled (`swift run`) Sparkle has no bundle to update, so we no-op.
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        // Bundle identifier is nil when running unbundled — skip Sparkle then.
        guard Bundle.main.bundleIdentifier != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Whether a manual check can run right now (drives the menu item's state).
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// User-initiated check ("Check for Updates…"): always shows UI, even when
    /// already up to date.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
