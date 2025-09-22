import Foundation
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Thin wrapper that prefers Sparkle (when available)
/// and falls back to the existing GitHub-based notifier.
@MainActor
final class InAppUpdater: ObservableObject {
    static let shared = InAppUpdater()

    private init() {}

    // MARK: - Public API

    /// Triggers a user-initiated update flow.
    /// - If Sparkle is available, shows its update UI where the user can install, cancel, or skip.
    /// - Otherwise, shows a simple alert and opens the Releases page for manual update.
    func checkForUpdates() {
        #if canImport(Sparkle)
        sparkleCheckForUpdates()
        #else
        basicFallbackCheck()
        #endif
    }

    /// Checks for updates on app launch and, if available, shows UI to let the
    /// user decide: install, cancel (remind later), or skip this version.
    func checkOnLaunchAndNotify() {
        #if canImport(Sparkle)
        sparkleBackgroundCheck()
        #else
        basicFallbackBackgroundCheck()
        #endif
    }

    // MARK: - Sparkle integration (compiled only if Sparkle is available in the project)
    #if canImport(Sparkle)
    private lazy var sparkleController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private func sparkleCheckForUpdates() {
        // Show Sparkle's standard UI where user can choose Install / Later / Skip
        sparkleController.checkForUpdates(nil)
    }

    private func sparkleBackgroundCheck() {
        // Configure to respect user's choice (no silent auto-install)
        let updater = sparkleController.updater
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = false
        // Check silently; UI appears only if an update exists
        updater.checkForUpdatesInBackground()
    }
    #endif

    // MARK: - Fallback using the existing GitHub notifier
    private func basicFallbackCheck() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("check_for_updates", comment: "Check for updates")
        alert.informativeText = String(
            format: NSLocalizedString("no_updates_message", comment: "No updates message"),
            currentVersion
        ) + "\n\n" + "Releases: https://github.com/fparrav/LiveWalls/releases"
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("ok_button", comment: "OK button"))
        alert.addButton(withTitle: "Abrir Releases")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn, let url = URL(string: "https://github.com/fparrav/LiveWalls/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    private func basicFallbackBackgroundCheck() {
        // Throttle to once per 24 hours
        let defaults = UserDefaults.standard
        let lastCheckKey = "LastUpdateCheckAt"
        if let last = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        defaults.set(Date(), forKey: lastCheckKey)
        // Without Sparkle we won't auto-prompt; user can use manual check.
    }
}
