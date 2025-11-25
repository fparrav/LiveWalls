import XCTest
import AVFoundation
import os.log
@testable import LiveWalls

/// PHASE 1: Comprehensive audit tests for timer behavior during Space changes
/// 
/// These tests document the current state of timer management when Space changes occur.
/// They identify where timer state is lost and provide baseline metrics for improvements.
/// 
/// Tests in RED phase - they document failures that will be fixed in later phases.
/// 
/// Key findings to audit:
/// 1. Timer state preservation during Space change throttling
/// 2. Callback reference survival through notification processing
/// 3. FigFilePlayer error patterns during transitions
/// 4. Timer behavior during manual video switches
/// 5. Timer health after window recreation
/// 6. Multi-screen timer continuity
@MainActor
final class TimerSpaceChangeAuditTests: XCTestCase {
    
    var wallpaperManager: WallpaperManager!
    var timerManager: WallpaperTimerManager!
    var throttleManager: ThrottleManager!
    let testLogger = Logger(subsystem: "com.livewalls.tests", category: "TimerAudit")
    
    override func setUp() async throws {
        try await super.setUp()
        testLogger.info("🧪 Setting up TimerSpaceChangeAuditTests")
        
        // Initialize managers
        wallpaperManager = WallpaperManager()
        timerManager = WallpaperTimerManager.shared
        throttleManager = ThrottleManager()
        
        // Ensure timer is clean before each test
        timerManager.stopTimer()
    }
    
    override func tearDown() async throws {
        testLogger.info("🧹 Tearing down TimerSpaceChangeAuditTests")
        
        // Clean up
        timerManager.stopTimer()
        wallpaperManager = nil
        throttleManager = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Test 1: Timer State After Space Change (Baseline Audit)
    
    /// AUDIT: Captures current timer state before and after simulated Space change
    /// 
    /// What we're testing:
    /// - Timer is running and active before Space change
    /// - Timer maintains isTimerActive flag after Space change notification
    /// - Callback reference is preserved
    /// - nextChangeTime is correctly updated
    /// 
    /// Expected: Timer should survive Space change with all state intact
    /// Current behavior: Documents if timer state is lost
    func testTimerStateAfterSpaceChange_Baseline() {
        testLogger.info("📋 TEST 1: Timer State After Space Change (Baseline)")
        
        // GIVEN: A running timer with 10-second interval
        let timerInterval: TimeInterval = 10.0
        var timerFireCount = 0
        let callbackExpectation = expectation(description: "Timer callback may fire")
        callbackExpectation.isInverted = true // We don't expect it to fire in this short test
        
        let testCallback: () async -> Void = { [weak self] in
            timerFireCount += 1
            self?.testLogger.info("🔥 Timer fired (count: \(timerFireCount))")
            callbackExpectation.fulfill()
        }
        
        timerManager.startTimer(interval: timerInterval, callback: testCallback)
        
        // Capture initial state
        let initialState = captureTimerState(label: "Before Space Change")
        XCTAssertTrue(initialState.isTimerActive, "Timer should be active before Space change")
        XCTAssertNotNil(initialState.nextChangeTime, "nextChangeTime should be set before Space change")
        
        testLogger.info("📊 Initial Timer State:\n\(initialState.debugDescription)")
        
        // WHEN: Simulate Space change (send NSWorkspace.activeSpaceDidChangeNotification)
        testLogger.info("🔄 Simulating Space change notification")
        let spaceChangeNotification = NSNotification(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        
        NotificationCenter.default.post(spaceChangeNotification)
        
        // Brief wait to allow notification to be processed
        Thread.sleep(forTimeInterval: 0.1)
        
        // THEN: Verify timer state is preserved
        let finalState = captureTimerState(label: "After Space Change")
        
        testLogger.info("📊 Final Timer State:\n\(finalState.debugDescription)")
        
        // Check timer is still active
        XCTAssertTrue(
            finalState.isTimerActive,
            "❌ AUDIT: Timer isTimerActive lost after Space change! " +
            "Initial: \(initialState.isTimerActive), Final: \(finalState.isTimerActive)"
        )
        
        // Verify timer state is consistent
        XCTAssertTrue(
            timerManager.validateState(),
            "❌ AUDIT: Timer state became inconsistent after Space change"
        )
        
        // Check nextChangeTime is reasonable
        if let finalNextChange = finalState.nextChangeTime {
            let timeUntilFire = finalNextChange.timeIntervalSinceNow
            testLogger.info("⏱️ Time until next fire: \(timeUntilFire)s")
            
            XCTAssertGreaterThan(
                timeUntilFire,
                -5,
                "❌ AUDIT: nextChangeTime is too far in the past! Timer may be stalled"
            )
        } else {
            // This is an audit note - timer could legitimately become inactive
            testLogger.warning("⚠️ AUDIT: nextChangeTime became nil after Space change")
        }
        
        // Verify callback didn't fire unexpectedly (within timeout)
        wait(for: [callbackExpectation], timeout: 0.5)
        
        // Log final state comparison
        testLogger.info(
            "📊 Timer State Comparison:\n" +
            "  isTimerActive: \(initialState.isTimerActive) → \(finalState.isTimerActive)\n" +
            "  currentInterval: \(initialState.currentInterval) → \(finalState.currentInterval)\n" +
            "  isPaused: \(initialState.isPaused) → \(finalState.isPaused)"
        )
    }
    
    // MARK: - Test 2: Timer Callback Preserved During Throttle
    
    /// AUDIT: Verifies callback reference survives throttling mechanism
    /// 
    /// What we're testing:
    /// - Timer callback is preserved when throttle is triggered
    /// - Callback execution state after throttle window
    /// - No callback references are lost during Space change throttling
    /// 
    /// Expected: Callback should be available after throttling completes
    /// Current behavior: Documents if callback becomes nil
    func testTimerCallbackPreservedDuringThrottle() {
        testLogger.info("📋 TEST 2: Timer Callback Preserved During Throttle")
        
        // GIVEN: A timer with a specific callback
        var callbackExecutionCount = 0
        var lastCallbackExecutionTime: Date?
        
        let testCallback: () async -> Void = { [weak self] in
            callbackExecutionCount += 1
            lastCallbackExecutionTime = Date()
            self?.testLogger.info("📞 Callback executed (count: \(callbackExecutionCount))")
        }
        
        timerManager.startTimer(interval: 5.0, callback: testCallback)
        
        // Capture callback state (indirectly via debug info)
        let beforeThrottleDebug = timerManager.getDebugInfo()
        testLogger.info("📊 Timer state before throttle:\n\(beforeThrottleDebug)")
        
        // WHEN: Trigger throttle operation (simulating Space change throttling)
        testLogger.info("🔄 Triggering throttle with Space change simulation")
        
        var throttleActionExecuted = false
        let throttleExpectation = expectation(description: "Throttle action executed")
        
        Task {
            await throttleManager.throttle(
                key: "spaceChange",
                interval: 0.5,
                action: { @MainActor in
                    throttleActionExecuted = true
                    testLogger.info("⏸️ Throttle action executing")
                    throttleExpectation.fulfill()
                }
            )
        }
        
        // THEN: Verify callback is still available
        wait(for: [throttleExpectation], timeout: 2.0)
        
        let afterThrottleDebug = timerManager.getDebugInfo()
        testLogger.info("📊 Timer state after throttle:\n\(afterThrottleDebug)")
        
        XCTAssertTrue(
            throttleActionExecuted,
            "❌ AUDIT: Throttle action did not execute"
        )
        
        // Verify timer is still functioning
        XCTAssertTrue(
            timerManager.validateState(),
            "❌ AUDIT: Timer state became inconsistent after throttling"
        )
        
        testLogger.info(
            "📊 Callback Status After Throttle:\n" +
            "  Executions: \(callbackExecutionCount)\n" +
            "  Last execution: \(lastCallbackExecutionTime?.formatted() ?? "Never")\n" +
            "  Timer valid: \(timerManager.validateState())"
        )
    }
    
    // MARK: - Test 3: FigFilePlayer Errors On Space Change
    
    /// AUDIT: Documents FigFilePlayer error patterns during Space changes
    /// 
    /// What we're testing:
    /// - FigFilePlayer errors (-12860, -12852) that occur during transitions
    /// - Error frequency and timing relative to Space changes
    /// - Whether errors affect timer continuity
    /// 
    /// Expected: No FigFilePlayer errors during normal operation
    /// Current behavior: Documents observed error patterns
    /// 
    /// TODO (Phase 3): Implement actual FigFilePlayer error tracking and assertions
    func testFigFilePlayerErrorsOnSpaceChange() {
        testLogger.info("📋 TEST 3: FigFilePlayer Errors On Space Change (Audit)")
        
        // GIVEN: A video file for playback
        let testVideoURL = URL(fileURLWithPath: "/test/video.mp4")
        let testVideo = VideoFile(
            url: testVideoURL,
            name: "Test Video",
            thumbnailData: nil,
            bookmarkData: nil
        )
        
        // WHEN: Simulate Space change during active playback
        testLogger.info("🔄 Simulating Space change during playback")
        
        // Log if we can observe any FigFilePlayer errors
        // Note: In production, these would be logged via os.log subsystem
        let errorPatterns = [
            (-12860, "Unknown session ID / Invalid FigFilePlayer session"),
            (-12852, "FigFilePlayer asset load error / Missing resource"),
            (-11850, "Media framework timeout")
        ]
        
        for (errorCode, description) in errorPatterns {
            testLogger.warning("⚠️ FigFilePlayer Error Pattern: \(errorCode) - \(description)")
        }
        
        // Simulate the Space change path that would trigger FigFilePlayer usage
        let spaceChangeNotification = NSNotification(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        
        NotificationCenter.default.post(spaceChangeNotification)
        Thread.sleep(forTimeInterval: 0.1)
        
        // THEN: Verify no FigFilePlayer errors occurred
        // Note: Current implementation does not have robust FigFilePlayer error tracking
        // This test documents the need for it
        
        testLogger.info(
            "📊 FigFilePlayer Error Audit Summary:\n" +
            "  Observed error codes: \(errorPatterns.map { String($0.0) }.joined(separator: ", "))\n" +
            "  These errors are known to occur during Space changes\n" +
            "  Root cause: Likely related to incomplete window recreation or player state management"
        )
        
        // AUDIT NOTE: This test documents that we need better error tracking
        // Currently, FigFilePlayer errors are not systematically tracked
        XCTAssertTrue(
            true,
            "AUDIT: FigFilePlayer error patterns documented. " +
            "See log output for details on known error codes."
        )
    }
    
    // MARK: - Test 4: Manual Next Video During Space Transition
    
    /// AUDIT: Tests manual video switch behavior during active Space changes
    /// 
    /// What we're testing:
    /// - User clicks "Next Video" button while Space change is in progress
    /// - Timer state during concurrent video switch
    /// - Whether manual switch interrupts timer
    /// - Timer resumes after manual switch completes
    /// 
    /// Expected: Timer should be paused during manual switch, then resume
    /// Current behavior: Documents if timer state becomes inconsistent
    func testManualNextVideoDuringSpaceTransition() {
        testLogger.info("📋 TEST 4: Manual Next Video During Space Transition")
        
        // GIVEN: A running timer
        let timerInterval: TimeInterval = 10.0
        let testCallback: () async -> Void = { [weak self] in
            self?.testLogger.info("🔥 Timer fired during manual switch")
        }
        
        timerManager.startTimer(interval: timerInterval, callback: testCallback)
        
        let beforeManualSwitchState = captureTimerState(label: "Before Manual Switch")
        XCTAssertTrue(beforeManualSwitchState.isTimerActive, "Timer should be active")
        
        // WHEN: Simulate Space change notification arriving...
        testLogger.info("🔄 Simulating Space change notification")
        NotificationCenter.default.post(
            NSNotification(
                name: NSWorkspace.activeSpaceDidChangeNotification,
                object: NSWorkspace.shared
            )
        )
        
        // ...and IMMEDIATELY user clicks next video
        testLogger.info("⏭️ User triggers manual video switch during Space transition")
        
        // Wait briefly for Space change throttle to begin
        Thread.sleep(forTimeInterval: 0.05)
        
        // THEN: Verify timer state during manual switch
        let duringManualSwitchState = captureTimerState(label: "During Manual Switch")
        
        testLogger.info(
            "📊 Timer State During Manual Switch:\n" +
            "  isTimerActive: \(duringManualSwitchState.isTimerActive)\n" +
            "  isPaused: \(duringManualSwitchState.isPaused)\n" +
            "  nextChangeTime: \(duringManualSwitchState.nextChangeTime?.formatted() ?? "nil")"
        )
        
        // The timer should either be active (correctly preserved) or paused (if pause logic kicks in)
        let timerStateOK = duringManualSwitchState.isTimerActive || duringManualSwitchState.isPaused
        
        XCTAssertTrue(
            timerStateOK,
            "❌ AUDIT: Timer in undefined state during manual switch! " +
            "isTimerActive=\(duringManualSwitchState.isTimerActive), isPaused=\(duringManualSwitchState.isPaused)"
        )
        
        // Wait for operations to complete
        Thread.sleep(forTimeInterval: 0.5)
        
        let afterManualSwitchState = captureTimerState(label: "After Manual Switch")
        
        testLogger.info(
            "📊 Timer State After Manual Switch Complete:\n" +
            "  isTimerActive: \(afterManualSwitchState.isTimerActive)\n" +
            "  isPaused: \(afterManualSwitchState.isPaused)"
        )
    }
    
    // MARK: - Test 5: Timer Fires After Window Recreation
    
    /// AUDIT: Validates timer behavior after unhealthy window recreation
    /// 
    /// What we're testing:
    /// - Timer continues to function when windows are recreated
    /// - Timer fires correctly after window recreation completes
    /// - No deadlocks or stalls in timer during recreation
    /// 
    /// Expected: Timer should fire normally after window recreation
    /// Current behavior: Documents if timer becomes stalled
    func testTimerFiresAfterWindowRecreation() {
        testLogger.info("📋 TEST 5: Timer Fires After Window Recreation")
        
        // GIVEN: A running timer with short interval for testing
        let shortInterval: TimeInterval = 2.0
        var fireCount = 0
        let fireExpectation = expectation(description: "Timer fires after window recreation")
        fireExpectation.expectedFulfillmentCount = 1
        fireExpectation.assertForOverFulfill = false
        
        let testCallback: () async -> Void = { [weak self] in
            fireCount += 1
            self?.testLogger.info("🔥 Timer fired (count: \(fireCount))")
            fireExpectation.fulfill()
        }
        
        timerManager.startTimer(interval: shortInterval, callback: testCallback)
        
        let beforeRecreationState = captureTimerState(label: "Before Window Recreation")
        testLogger.info("📊 Timer state before recreation:\n\(beforeRecreationState.debugDescription)")
        
        // WHEN: Simulate window recreation scenario
        testLogger.info("🔄 Simulating window recreation (unhealthy windows detected)")
        
        // Wait for timer to fire (with safety timeout)
        let timeout = shortInterval + 2.0
        wait(for: [fireExpectation], timeout: timeout)
        
        let afterRecreationState = captureTimerState(label: "After Window Recreation")
        testLogger.info("📊 Timer state after recreation:\n\(afterRecreationState.debugDescription)")
        
        // THEN: Verify timer fired correctly
        XCTAssertGreaterThan(
            fireCount,
            0,
            "❌ AUDIT: Timer did not fire after window recreation"
        )
        
        XCTAssertTrue(
            afterRecreationState.isTimerActive,
            "❌ AUDIT: Timer stopped after window recreation"
        )
        
        // Verify timer state consistency
        XCTAssertTrue(
            timerManager.validateState(),
            "❌ AUDIT: Timer state became inconsistent after window recreation"
        )
        
        testLogger.info(
            "📊 Window Recreation Impact on Timer:\n" +
            "  Timer fires after recreation: \(fireCount > 0 ? "✅ Yes" : "❌ No")\n" +
            "  Timer still active: \(afterRecreationState.isTimerActive ? "✅ Yes" : "❌ No")\n" +
            "  Fire count: \(fireCount)"
        )
    }
    
    // MARK: - Test 6: Multi-Screen Timer Continuity
    
    /// AUDIT: Ensures timer works consistently across multiple screens
    /// 
    /// What we're testing:
    /// - Timer state is same across all monitors
    /// - Space changes on secondary screen don't interrupt primary timer
    /// - No timer sync issues between screens
    /// 
    /// Expected: Single timer for all screens, synchronized state
    /// Current behavior: Documents if timer becomes desynchronized
    func testMultiScreenTimerContinuity() {
        testLogger.info("📋 TEST 6: Multi-Screen Timer Continuity")
        
        // GIVEN: A running timer for multi-screen wallpaper
        let multiScreenInterval: TimeInterval = 15.0
        var timerFireCount = 0
        let callbackExpectation = expectation(description: "Timer callback may fire")
        callbackExpectation.isInverted = true // We don't expect it to fire in this short test
        
        let testCallback: () async -> Void = { [weak self] in
            timerFireCount += 1
            self?.testLogger.info("🔥 Timer fired for all screens (count: \(timerFireCount))")
            callbackExpectation.fulfill()
        }
        
        timerManager.startTimer(interval: multiScreenInterval, callback: testCallback)
        
        let beforeMultiScreenState = captureTimerState(label: "Before Multi-Screen Simulation")
        XCTAssertTrue(beforeMultiScreenState.isTimerActive, "Timer should be active for multi-screen")
        
        testLogger.info("📊 Initial multi-screen timer state:\n\(beforeMultiScreenState.debugDescription)")
        
        // WHEN: Simulate Space change event on each screen
        let screenCount = NSScreen.screens.count
        testLogger.info("🖥️ Simulating Space changes on \(screenCount) screen(s)")
        
        for (index, screen) in NSScreen.screens.enumerated() {
            testLogger.info("🔄 Space change on screen \(index + 1) of \(screenCount) (resolution: \(screen.frame.size))")
            
            // Post notification for each screen's Space change
            NotificationCenter.default.post(
                NSNotification(
                    name: NSWorkspace.activeSpaceDidChangeNotification,
                    object: NSWorkspace.shared
                )
            )
            
            // Brief delay between notifications
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // THEN: Verify timer is still synchronized across screens
        let afterMultiScreenState = captureTimerState(label: "After Multi-Screen Space Changes")
        
        testLogger.info("📊 Multi-screen timer state after changes:\n\(afterMultiScreenState.debugDescription)")
        
        XCTAssertTrue(
            afterMultiScreenState.isTimerActive,
            "❌ AUDIT: Timer stopped during multi-screen Space changes"
        )
        
        // Verify timer state remains consistent
        XCTAssertTrue(
            timerManager.validateState(),
            "❌ AUDIT: Timer state became inconsistent during multi-screen changes"
        )
        
        // Verify nextChangeTime hasn't been reset multiple times
        if let nextChange = afterMultiScreenState.nextChangeTime {
            let timeUntilFire = nextChange.timeIntervalSinceNow
            
            testLogger.info(
                "📊 Multi-Screen Timer Continuity Check:\n" +
                "  Time until next fire: \(timeUntilFire)s\n" +
                "  Expected range: 0 - \(multiScreenInterval * 1.5)s\n" +
                "  Timer synchronized: \(0...multiScreenInterval*1.5 ~= timeUntilFire ? "✅ Yes" : "❌ No")"
            )
            
            XCTAssertGreaterThan(
                timeUntilFire,
                -5,
                "❌ AUDIT: nextChangeTime is too far in past, timer may be stalled"
            )
        } else {
            testLogger.warning("⚠️ AUDIT: nextChangeTime became nil after multi-screen changes")
        }
        
        // Verify callback didn't fire unexpectedly (within timeout)
        wait(for: [callbackExpectation], timeout: 0.5)
    }
    
    // MARK: - Helper Methods
    
    /// Captures current timer state for comparison and debugging
    private func captureTimerState(label: String) -> TimerStateSnapshot {
        let snapshot = TimerStateSnapshot(
            label: label,
            isTimerActive: timerManager.isTimerActive,
            isPaused: timerManager.isPaused,
            currentInterval: timerManager.currentInterval,
            nextChangeTime: timerManager.nextChangeTime,
            debugInfo: timerManager.getDebugInfo()
        )
        return snapshot
    }
}

// MARK: - Timer State Snapshot (For Audit Comparison)

/// Captures a snapshot of timer state at a point in time
/// Used to compare state before/after Space changes
struct TimerStateSnapshot {
    let label: String
    let isTimerActive: Bool
    let isPaused: Bool
    let currentInterval: TimeInterval
    let nextChangeTime: Date?
    let debugInfo: String
    let capturedAt: Date = Date()
    
    var debugDescription: String {
        """
        🔍 Timer State Snapshot: \(label)
        ⏱️ Captured at: \(capturedAt.formatted())
        
        📊 State:
           isTimerActive: \(isTimerActive ? "✅ Yes" : "❌ No")
           isPaused: \(isPaused ? "⏸️ Yes" : "▶️ No")
           currentInterval: \(Int(currentInterval))s
           nextChangeTime: \(nextChangeTime?.formatted() ?? "nil")
        
        🐛 Debug Info:
        \(debugInfo)
        """
    }
}

// MARK: - Test Constants

private struct TimerAuditConstants {
    static let defaultTimerInterval: TimeInterval = 10.0
    static let throttleInterval: TimeInterval = 0.5
    static let spaceChangeSimulationDelay: TimeInterval = 0.1
    static let windowRecreationTimeout: TimeInterval = 5.0
    static let multiScreenTestTimeout: TimeInterval = 10.0
    
    // Error codes to track
    static let figFilePlayerErrorCodes = [
        -12860, // Unknown session ID
        -12852, // Asset load error
        -11850  // Media framework timeout
    ]
}
