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