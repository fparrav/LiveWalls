import Foundation
import os.log

/// Off-by-default debug flags for the recovery machinery.
/// - All flags default to `false` (inert).
/// - Flags are UserDefaults-backed so tests / a debug session can enable them without recompiling.
/// - These flags are *test-only* / debug — no UI in normal use flips them.
/// - The per-increment kill-switches for task 2.8 will live here too.
struct RecoveryDebugFlags {
    private static let logger = Logger(subsystem: "com.livewalls.app", category: "RecoveryDebugFlags")

    private static let simulateStallKey = "RecoveryDebug.SimulateStall"

    /// When `true`, `DesktopVideoWindowMejorada.getCurrentTime()` returns a frozen CMTime
    /// (captured at the moment of enabling), making the render-advance probe see "no advance,
    /// no wrap" → `.stalled`, while the underlying AVPlayer keeps running normally.
    /// Reproduces the post-wake render-stall state on demand.
    static var simulateStall: Bool {
        get { UserDefaults.standard.bool(forKey: simulateStallKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: simulateStallKey)
            logger.warning("🧪 RecoveryDebugFlags.simulateStall → \(newValue ? "ENABLED" : "DISABLED")")
        }
    }

    /// Enables the stall simulation. Captures the current player time (per-window) as the
    /// frozen value the probe will see.
    static func enableStallSimulation() {
        simulateStall = true
        // Notify windows to capture their current time
        RecoveryDebugNotificationCenter.postCaptureTime()
    }

    /// Disables the stall simulation. Probe returns to real time.
    static func disableStallSimulation() {
        simulateStall = false
        RecoveryDebugNotificationCenter.postClearTime()
    }

    /// Alias for `disableStallSimulation()` (spec calls it "clear").
    static func clearStallSimulation() {
        disableStallSimulation()
    }

    /// Whether the stall simulation is currently active.
    static var isSimulatingStall: Bool {
        return simulateStall
    }

    // MARK: - Task 2.8: per-increment kill-switches (design D9)
    // Each flag defaults to TRUE (fix active). Setting to false via UserDefaults
    // restores the legacy behavior for that increment without recompile/relaunch.

    private static let probeBasedHealthJudgmentKey = "RecoveryDebug.ProbeBasedHealthJudgment"

    /// Incremento 2.4: probe-based health judgment (design D2).
    /// ON (true) = probe .advancing/.stalled decide health; OFF = fallback to bookmark/timeControlStatus.
    static var probeBasedHealthJudgment: Bool {
        get {
            let obj = UserDefaults.standard.object(forKey: probeBasedHealthJudgmentKey)
            return obj == nil ? true : UserDefaults.standard.bool(forKey: probeBasedHealthJudgmentKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: probeBasedHealthJudgmentKey)
            logger.warning("🧪 RecoveryDebugFlags.probeBasedHealthJudgment → \(newValue ? "ENABLED (fix)" : "DISABLED (legacy fallback)")")
        }
    }

    private static let fullFreshRebuildKey = "RecoveryDebug.FullFreshRebuild"

    /// Incremento 2.5: full fresh rebuild with first-frame probe (design D3).
    /// ON (true) = performFreshRebuild with orderFront/orderBack + first-frame probe; OFF = legacy rebuild.
    static var fullFreshRebuild: Bool {
        get {
            let obj = UserDefaults.standard.object(forKey: fullFreshRebuildKey)
            return obj == nil ? true : UserDefaults.standard.bool(forKey: fullFreshRebuildKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: fullFreshRebuildKey)
            logger.warning("🧪 RecoveryDebugFlags.fullFreshRebuild → \(newValue ? "ENABLED (fix)" : "DISABLED (legacy rebuild)")")
        }
    }

    private static let bookmarkRefCountKey = "RecoveryDebug.BookmarkRefCount"

    /// Incremento 2.6: BookmarkActor ref-count + reconcile (design D6).
    /// ON (true) = ref-count per URL, reconcile() drains to zero; OFF = legacy Set semantics.
    static var bookmarkRefCount: Bool {
        get {
            let obj = UserDefaults.standard.object(forKey: bookmarkRefCountKey)
            return obj == nil ? true : UserDefaults.standard.bool(forKey: bookmarkRefCountKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: bookmarkRefCountKey)
            logger.warning("🧪 RecoveryDebugFlags.bookmarkRefCount → \(newValue ? "ENABLED (fix)" : "DISABLED (legacy Set)")")
        }
    }

    private static let staticApplyOffMainKey = "RecoveryDebug.StaticApplyOffMain"

    /// Incremento 2.7: static-image apply off-main (design D7).
    /// ON (true) = setDesktopImageURL runs in Task.detached; OFF = legacy synchronous main-queue.
    static var staticApplyOffMain: Bool {
        get {
            let obj = UserDefaults.standard.object(forKey: staticApplyOffMainKey)
            return obj == nil ? true : UserDefaults.standard.bool(forKey: staticApplyOffMainKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: staticApplyOffMainKey)
            logger.warning("🧪 RecoveryDebugFlags.staticApplyOffMain → \(newValue ? "ENABLED (fix)" : "DISABLED (legacy main-queue)")")
        }
    }

    /// Resets all 2.8 kill-switches to their defaults (ON). Useful for tests.
    static func resetAllKillSwitches() {
        UserDefaults.standard.removeObject(forKey: probeBasedHealthJudgmentKey)
        UserDefaults.standard.removeObject(forKey: fullFreshRebuildKey)
        UserDefaults.standard.removeObject(forKey: bookmarkRefCountKey)
        UserDefaults.standard.removeObject(forKey: staticApplyOffMainKey)
        logger.warning("🧪 RecoveryDebugFlags: all kill-switches reset to defaults (ON)")
    }
}

/// Internal notification bus for the freeze mechanism. Windows observe `captureTimeNotification`
/// to record the pinned CMTime when simulation is enabled, and `clearTimeNotification` to clear it.
enum RecoveryDebugNotificationCenter {
    static let captureTimeNotification = Notification.Name("RecoveryDebug.CaptureTime")
    static let clearTimeNotification = Notification.Name("RecoveryDebug.ClearTime")

    static func postCaptureTime() {
        NotificationCenter.default.post(name: captureTimeNotification, object: nil)
    }

    static func postClearTime() {
        NotificationCenter.default.post(name: clearTimeNotification, object: nil)
    }
}