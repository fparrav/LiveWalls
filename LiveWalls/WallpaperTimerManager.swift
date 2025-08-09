import Foundation
import AppKit
import os.log

/// Robust timer manager for automatic wallpaper rotation
/// Implements singleton pattern to prevent multiple instances and ensure consistent behavior
@MainActor
class WallpaperTimerManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = WallpaperTimerManager()
    
    // MARK: - Published Properties
    
    @Published var isTimerActive: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentInterval: TimeInterval = 0
    @Published var nextChangeTime: Date? = nil
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "WallpaperTimerManager")
    private var activeTimer: Timer? = nil
    private var pausedRemainingTime: TimeInterval = 0
    private var pausedAt: Date? = nil
    private var timerID: UUID? = nil
    
    // Callback for when the timer fires
    private var timerCallback: (() async -> Void)? = nil
    
    // Mutex for thread safety
    private let timerLock = NSLock()
    
    // MARK: - Timer Statistics (For debugging)
    
    private var timerStartTime: Date? = nil
    private var timerFireCount: Int = 0
    private var lastFireTime: Date? = nil
    
    // MARK: - Initialization
    
    private init() {
        logger.info("⏰ Initializing WallpaperTimerManager (Singleton)")
    }
    
    deinit {
        logger.info("⏰ Deinitializing WallpaperTimerManager")
        Task { @MainActor in
            stopTimer()
        }
    }
    
    // MARK: - Public Interface
    
    /// Starts the timer with the specified interval
    /// - Parameters:
    ///   - interval: Interval in seconds between changes
    ///   - callback: Function that executes each time the timer fires
    func startTimer(interval: TimeInterval, callback: @escaping () async -> Void) {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        guard interval > 0 else {
            logger.error("❌ Invalid interval: \(interval). Must be greater than 0")
            return
        }
        
        // Stop existing timer if any
        stopTimerInternal()
        
        // Configure new timer
        currentInterval = interval
        timerCallback = callback
        timerID = UUID()
        
        // Create and configure timer
        let currentTimerID = timerID!
        activeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                await self?.handleTimerFire(timerID: currentTimerID, timer: timer)
            }
        }
        
        // Update state
        isTimerActive = true
        isPaused = false
        timerStartTime = Date()
        timerFireCount = 0
        nextChangeTime = Date().addingTimeInterval(interval)
        
        logger.info("⏰ Timer started: \(Int(interval))s, ID: \(currentTimerID)")
    }
    
    /// Pauses the timer maintaining remaining time
    func pauseTimer() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        guard isTimerActive && !isPaused else {
            logger.warning("⚠️ Cannot pause: timer not active or already paused")
            return
        }
        
        guard let nextChange = nextChangeTime else {
            logger.error("❌ Cannot pause: no next change scheduled")
            return
        }
        
        // Calculate remaining time
        let now = Date()
        pausedRemainingTime = max(0, nextChange.timeIntervalSince(now))
        pausedAt = now
        
        // Stop current timer
        activeTimer?.invalidate()
        activeTimer = nil
        
        // Update state
        isPaused = true
        nextChangeTime = nil
        
        logger.info("⏸️ Timer paused. Remaining time: \(Int(self.pausedRemainingTime))s")
    }
    
    /// Resumes the timer from where it was paused
    func resumeTimer() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        guard isTimerActive && isPaused else {
            logger.warning("⚠️ Cannot resume: timer not paused")
            return
        }
        
        guard let callback = timerCallback, let currentTimerID = timerID else {
            logger.error("❌ Cannot resume: missing callback or timer ID")
            return
        }
        
        // If remaining time is very small, fire immediately
        if pausedRemainingTime <= 1.0 {
            logger.info("⏰ Remaining time very small, firing immediately")
            Task {
                await callback()
                // Restart with full interval
                startTimer(interval: currentInterval, callback: callback)
            }
            return
        }
        
        // Create timer with remaining time
        activeTimer = Timer.scheduledTimer(withTimeInterval: pausedRemainingTime, repeats: false) { [weak self] timer in
            Task { @MainActor [weak self] in
                await self?.handleTimerFire(timerID: currentTimerID, timer: timer)
                
                // After first fire, create normal timer with full interval
                if let self = self, let callback = self.timerCallback {
                    self.startTimer(interval: self.currentInterval, callback: callback)
                }
            }
        }
        
        // Update state
        isPaused = false
        nextChangeTime = Date().addingTimeInterval(pausedRemainingTime)
        
        logger.info("▶️ Timer resumed. Next change in: \(Int(self.pausedRemainingTime))s")
    }
    
    /// Completely stops the timer
    func stopTimer() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        stopTimerInternal()
    }
    
    /// Restarts the timer with new interval (equivalent to stop + start)
    func restartTimer(interval: TimeInterval, callback: @escaping () async -> Void) {
        logger.info("🔄 Restarting timer with interval: \(Int(interval))s")
        stopTimer()
        startTimer(interval: interval, callback: callback)
    }
    
    // MARK: - Private Methods
    
    private func stopTimerInternal() {
        activeTimer?.invalidate()
        activeTimer = nil
        timerCallback = nil
        timerID = nil
        
        // Reset state
        isTimerActive = false
        isPaused = false
        pausedRemainingTime = 0
        pausedAt = nil
        nextChangeTime = nil
        
        // Reset statistics
        timerStartTime = nil
        timerFireCount = 0
        lastFireTime = nil
        
        logger.info("⏹️ Timer stopped completely")
    }
    
    private func handleTimerFire(timerID: UUID, timer: Timer) async {
        // Verify this is the correct timer (prevent race conditions)
        guard self.timerID == timerID else {
            logger.warning("⚠️ Obsolete timer fired, ignoring")
            return
        }
        
        // Update statistics
        timerFireCount += 1
        lastFireTime = Date()
        
        logger.info("🔥 Timer fired (fire #\(self.timerFireCount))")
        
        // Execute callback
        if let callback = timerCallback {
            await callback()
        }
        
        // If not repetitive, schedule next fire
        if !timer.isValid || !(activeTimer?.isValid ?? false) {
            // Timer was invalidated, don't update next change time
            return
        }
        
        // Update next change
        nextChangeTime = Date().addingTimeInterval(currentInterval)
        
        logger.debug("⏭️ Next change scheduled: \(self.nextChangeTime?.formatted() ?? "None")")
    }
    
    // MARK: - State Validation
    
    /// Validates that the timer state is consistent
    func validateState() -> Bool {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        let isValid = validateStateInternal()
        
        if !isValid {
            logger.error("❌ Inconsistent timer state detected")
            logDebugInfo()
        }
        
        return isValid
    }
    
    private func validateStateInternal() -> Bool {
        // Validate that Published state matches internal state
        if isTimerActive {
            // If active, must have timer or be paused
            if activeTimer == nil && !isPaused {
                return false
            }
            
            // If paused, should not have active timer
            if isPaused && activeTimer != nil {
                return false
            }
            
            // Must have callback and timer ID
            if timerCallback == nil || timerID == nil {
                return false
            }
        } else {
            // If not active, should not have timer or be paused
            if activeTimer != nil || isPaused || timerCallback != nil {
                return false
            }
        }
        
        return true
    }
    
    /// Automatically recovers from inconsistent states
    func recoverFromInconsistentState() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        logger.warning("🔧 Starting recovery from inconsistent state")
        
        // Stop everything and clean state
        stopTimerInternal()
        
        logger.info("✅ Recovery completed, timer reset")
    }
    
    // MARK: - Debug Information
    
    func getDebugInfo() -> String {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        var info = "=== WallpaperTimerManager Debug Info ===\n"
        info += "Is Timer Active: \(isTimerActive)\n"
        info += "Is Paused: \(isPaused)\n"
        info += "Current Interval: \(Int(currentInterval))s\n"
        info += "Timer ID: \(timerID?.uuidString ?? "None")\n"
        info += "Active Timer: \(activeTimer != nil ? "Yes" : "No")\n"
        info += "Timer Valid: \(activeTimer?.isValid ?? false)\n"
        info += "Next Change Time: \(nextChangeTime?.formatted() ?? "None")\n"
        info += "Paused Remaining Time: \(Int(pausedRemainingTime))s\n"
        info += "Paused At: \(pausedAt?.formatted() ?? "None")\n"
        info += "Fire Count: \(timerFireCount)\n"
        info += "Last Fire Time: \(lastFireTime?.formatted() ?? "None")\n"
        
        if let startTime = timerStartTime {
            let uptime = Date().timeIntervalSince(startTime)
            info += "Timer Uptime: \(Int(uptime))s\n"
        }
        
        info += "State Valid: \(validateStateInternal())\n"
        
        return info
    }
    
    private func logDebugInfo() {
        let debugInfo = getDebugInfo()
        logger.info("🐛 Debug Info:\n\(debugInfo)")
    }
}

// MARK: - Timer Health Check

extension WallpaperTimerManager {
    
    /// Checks timer health and automatically corrects problems
    func performHealthCheck() -> Bool {
        logger.info("🏥 Performing timer health check")
        
        let isHealthy = validateState()
        
        if !isHealthy {
            logger.warning("⚠️ Timer unhealthy, starting auto-correction")
            recoverFromInconsistentState()
            return false
        }
        
        // Check if timer should have fired already
        if let nextChange = nextChangeTime, !isPaused {
            let now = Date()
            if now > nextChange.addingTimeInterval(5) { // 5 seconds tolerance
                logger.warning("⚠️ Timer seems to be delayed, there may be a problem")
                return false
            }
        }
        
        logger.info("✅ Timer healthy")
        return true
    }
}
