import XCTest
import AVFoundation
@testable import LiveWalls

/// PHASE 2: Timer Space Change Integration Tests
/// Tests for timer preservation during WallpaperManager Space changes with window operations
/// These tests SIMULATE THE ACTUAL ISSUE #25 BUG SCENARIO:
/// 1. Space change triggers activeSpaceDidChange()
/// 2. Windows are unhealthy → ensurePlaying() is called
/// 3. ensurePlaying() recreates windows
/// 4. During recreation, timer callback reference may be lost or invalidated
/// 5. Timer state becomes inconsistent → timer stops firing
@MainActor
class TimerSpaceChangeAuditTests: XCTestCase {
    
    var wallpaperManager: WallpaperManager!
    var timerManager: WallpaperTimerManager!
    var throttleManager: ThrottleManager!
    
    override func setUp() async throws {
        try await super.setUp()
        wallpaperManager = WallpaperManager()
        timerManager = WallpaperTimerManager.shared
        throttleManager = ThrottleManager()
        
        // Clean up timer state
        timerManager.stopTimer()
    }
    
    override func tearDown() async throws {
        // Clean up wallpaper state
        await wallpaperManager.stopWallpaper()
        
        // Clean up timer state
        timerManager.stopTimer()
        
        wallpaperManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Phase 2 Test 1: Timer Survives Healthy Space Change
    /// Integration test: Timer continues after Space change with healthy windows (window reuse)
    /// This tests the optimal path in activeSpaceDidChange (line 1775-1777)
    func testTimerSurvivesHealthySpaceChangeWithWallpaperManager() async throws {
        // GIVEN: WallpaperManager initialized with test video
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("timer-test-healthy.mp4")
        FileManager.default.createFile(atPath: tempVideoURL.path, contents: Data("mock video".utf8))
        
        let video = VideoFile(url: tempVideoURL, name: "Test Video", bookmarkData: nil, isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        wallpaperManager.currentVideo = video
        
        // AND: Timer started with callback counter
        var callbackFireCount = 0
        let timerInterval: TimeInterval = 1.0
        
        let timerCallback: () async -> Void = { [weak self] in
            callbackFireCount += 1
        }
        
        timerManager.startTimer(interval: timerInterval, callback: timerCallback)
        XCTAssertTrue(timerManager.isTimerActive, "Timer should be active before Space change")
        let callbackBefore = callbackFireCount
        
        // WHEN: Simulate Space change notification (triggers activeSpaceDidChange)
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        
        // Wait for throttle (0.5s) + operations (0.2s buffer)
        try await Task.sleep(for: .milliseconds(800))
        
        // THEN: Timer should still be active with intact callback
        XCTAssertTrue(timerManager.isTimerActive, "Timer should remain active after healthy Space change")
        XCTAssertTrue(timerManager.validateState(), "Timer state should be valid after Space change")
        XCTAssertNotNil(timerManager.nextChangeTime, "nextChangeTime should be set")
        
        // Wait for timer to fire (interval is 1.0s, we gave it 0.8s already)
        try await Task.sleep(for: .milliseconds(500))
        
        // Verify timer actually fired after Space change
        XCTAssertGreaterThan(callbackFireCount, callbackBefore, 
                           "Timer callback should execute after Space change (fire count: \(callbackFireCount) vs before: \(callbackBefore))")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempVideoURL)
    }
    
    // MARK: - Phase 2 Test 2: Timer Survives Window Recreation
    /// Integration test: Timer continues after Space change triggering window recreation
    /// This tests the problematic path in activeSpaceDidChange (line 1779-1791)
    /// This is where the bug likely occurs - during ensurePlaying() recreation
    func testTimerSurvivesWindowRecreationOnSpaceChange() async throws {
        // GIVEN: WallpaperManager initialized with test video
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("timer-test-recreation.mp4")
        FileManager.default.createFile(atPath: tempVideoURL.path, contents: Data("mock video".utf8))
        
        let video = VideoFile(url: tempVideoURL, name: "Test Video", bookmarkData: nil, isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        wallpaperManager.currentVideo = video
        
        // AND: Timer started with callback counter
        var callbackFireCount = 0
        let timerInterval: TimeInterval = 1.0
        
        let timerCallback: () async -> Void = { [weak self] in
            callbackFireCount += 1
        }
        
        timerManager.startTimer(interval: timerInterval, callback: timerCallback)
        XCTAssertTrue(timerManager.isTimerActive, "Timer should be active before Space change")
        let callbackBefore = callbackFireCount
        
        // Simulate starting wallpaper (would create windows)
        await wallpaperManager.startWallpaperSafe()
        try await Task.sleep(for: .milliseconds(100))
        
        // WHEN: Simulate Space change notification
        // This triggers activeSpaceDidChange which calls ensurePlaying() for window recreation
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        
        // Wait for throttle (0.5s) + ensurePlaying operations (may take longer for recreation)
        try await Task.sleep(for: .milliseconds(1500))
        
        // THEN: Timer should still be active with intact callback
        XCTAssertTrue(timerManager.isTimerActive, 
                     "Timer should remain active after window recreation during Space change")
        XCTAssertTrue(timerManager.validateState(), 
                     "Timer state should be valid after recreation: \(timerManager.getDebugInfo())")
        XCTAssertNotNil(timerManager.nextChangeTime, "nextChangeTime should be set after recreation")
        
        // Wait additional time for timer to fire
        try await Task.sleep(for: .milliseconds(800))
        
        // Verify timer actually fired despite window recreation
        XCTAssertGreaterThan(callbackFireCount, callbackBefore, 
                           "Timer callback should execute even during window recreation (fire count: \(callbackFireCount) vs before: \(callbackBefore))")
        
        // Cleanup
        await wallpaperManager.stopWallpaper()
        try? FileManager.default.removeItem(at: tempVideoURL)
    }
    
    // MARK: - Phase 2 Test 3: Timer Callback Executes After Throttled Operations
    /// Integration test: Timer callback continues executing after throttled Space change operations
    /// Validates that the throttle in activeSpaceDidChange doesn't interfere with timer firing
    func testTimerCallbackExecutesAfterThrottledSpaceChange() async throws {
        // GIVEN: WallpaperManager with timer
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("timer-test-throttle.mp4")
        FileManager.default.createFile(atPath: tempVideoURL.path, contents: Data("mock video".utf8))
        
        let video = VideoFile(url: tempVideoURL, name: "Test Video", bookmarkData: nil, isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        wallpaperManager.currentVideo = video
        
        // AND: Timer with callback counter
        var callbackExecutionCount = 0
        let timerInterval: TimeInterval = 0.8  // Short interval to see multiple fires
        
        let timerCallback: () async -> Void = { [weak self] in
            callbackExecutionCount += 1
        }
        
        timerManager.startTimer(interval: timerInterval, callback: timerCallback)
        
        // WHEN: Post Space change notification (triggers throttled operation)
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        
        // Wait for throttle (0.5s) + operations (0.2s) + timer fires
        try await Task.sleep(for: .milliseconds(3000))  // Wait 3 seconds total
        
        // THEN: Verify callback executed multiple times despite throttling
        XCTAssertGreaterThanOrEqual(callbackExecutionCount, 2, 
                                   "Timer should fire at least 2-3 times in 3 seconds (actual: \(callbackExecutionCount))")
        
        // Verify timer is still healthy
        XCTAssertTrue(timerManager.isTimerActive, "Timer should still be active")
        XCTAssertTrue(timerManager.validateState(), "Timer state should be valid")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempVideoURL)
    }
    
    // MARK: - Phase 2 Test 4: Timer Callback Survives Rapid Space Changes
    /// Integration test: Timer survives multiple rapid Space changes without state corruption
    /// This simulates user switching between Spaces quickly
    func testTimerSurvivesRapidSpaceChanges() async throws {
        // GIVEN: WallpaperManager with running timer
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("timer-test-rapid.mp4")
        FileManager.default.createFile(atPath: tempVideoURL.path, contents: Data("mock video".utf8))
        
        let video = VideoFile(url: tempVideoURL, name: "Test Video", bookmarkData: nil, isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        wallpaperManager.currentVideo = video
        
        var callbackFireCount = 0
        let timerCallback: () async -> Void = { [weak self] in
            callbackFireCount += 1
        }
        
        timerManager.startTimer(interval: 1.0, callback: timerCallback)
        let fireCountBefore = callbackFireCount
        
        // WHEN: Simulate rapid Space changes
        for i in 0..<5 {
            NotificationCenter.default.post(
                name: NSWorkspace.activeSpaceDidChangeNotification,
                object: NSWorkspace.shared
            )
            try await Task.sleep(for: .milliseconds(100))
        }
        
        // Wait for throttle and timer fires
        try await Task.sleep(for: .milliseconds(2000))
        
        // THEN: Timer should survive rapid changes without corruption
        XCTAssertTrue(timerManager.isTimerActive, "Timer should be active after rapid Space changes")
        XCTAssertTrue(timerManager.validateState(), "Timer state should remain valid after rapid changes")
        XCTAssertGreaterThan(callbackFireCount, fireCountBefore, "Timer should continue firing despite rapid Space changes")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempVideoURL)
    }
    
    // MARK: - Phase 2 Test 5: Timer State Validation Works
    /// Integration test: Timer's validateState() detects state corruption
    /// If the bug corrupts timer state, this test should fail (expected in RED phase)
    func testTimerStateValidationDetectsCorruption() async throws {
        // GIVEN: Timer running and Space change occurring
        var callbackExecuted = false
        timerManager.startTimer(interval: 1.0, callback: { [weak self] in
            callbackExecuted = true
        })
        
        // WHEN: Space change triggers
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        
        try await Task.sleep(for: .milliseconds(800))
        
        // THEN: State validation should pass (if bug present, this may fail)
        XCTAssertTrue(timerManager.validateState(), 
                     "Timer state validation should pass. Debug info:\n\(timerManager.getDebugInfo())")
        
        // If we got here, timer survived
        XCTAssertTrue(timerManager.isTimerActive, "Timer should still be active")
    }
    
    // MARK: - Phase 2 Test 6: Timer Restart After Space Changes
    /// Integration test: Timer can be restarted after Space change cycle completes
    /// Validates recovery/restart capability after potential state issues
    func testTimerCanRestartAfterSpaceChangeCompletes() async throws {
        // GIVEN: Timer that experiences a Space change
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("timer-test-restart.mp4")
        FileManager.default.createFile(atPath: tempVideoURL.path, contents: Data("mock video".utf8))
        
        let video = VideoFile(url: tempVideoURL, name: "Test Video", bookmarkData: nil, isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        wallpaperManager.currentVideo = video
        
        timerManager.startTimer(interval: 1.0, callback: { @MainActor in })
        XCTAssertTrue(timerManager.isTimerActive)
        
        // WHEN: Space change occurs
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        
        try await Task.sleep(for: .milliseconds(1000))
        
        // AND: Timer is stopped
        timerManager.stopTimer()
        XCTAssertFalse(timerManager.isTimerActive)
        
        // THEN: Timer can be restarted with new settings
        var newCallbackExecuted = false
        timerManager.startTimer(interval: 2.0, callback: { [weak self] in
            newCallbackExecuted = true
        })
        
        XCTAssertTrue(timerManager.isTimerActive, "Timer should be active after restart")
        XCTAssertEqual(timerManager.currentInterval, 2.0, "Timer should have new interval")
        XCTAssertTrue(timerManager.validateState(), "Timer state should be valid after restart")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempVideoURL)
    }
}
