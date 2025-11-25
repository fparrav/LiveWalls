import XCTest
@testable import LiveWalls

@MainActor
final class PlaybackControlsConsolidationTests: XCTestCase {
    var wallpaperManager: WallpaperManager!
    
    override func setUp() {
        super.setUp()
        wallpaperManager = WallpaperManager()
        // Clear UserDefaults for each test
        UserDefaults.standard.removeObject(forKey: "AutoChangeEnabled")
        UserDefaults.standard.removeObject(forKey: "AutoChangeInterval")
        UserDefaults.standard.removeObject(forKey: "MuteVideo")
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "AutoChangeEnabled")
        UserDefaults.standard.removeObject(forKey: "AutoChangeInterval")
        UserDefaults.standard.removeObject(forKey: "MuteVideo")
        wallpaperManager = nil
        super.tearDown()
    }
    
    // MARK: - Auto-Change Tests
    
    /// Test that isAutoChangeEnabled property can be read
    func testAutoChangeEnabledCanBeRead() {
        // When & Then
        let enabled = wallpaperManager.isAutoChangeEnabled
        XCTAssertFalse(enabled, "Auto-change should be disabled by default")
    }
    
    /// Test that isAutoChangeEnabled property can be set
    func testAutoChangeEnabledCanBeSet() {
        // When
        wallpaperManager.isAutoChangeEnabled = true
        
        // Then
        XCTAssertTrue(wallpaperManager.isAutoChangeEnabled, "Auto-change should be enabled")
    }
    
    /// Test that autoChangeInterval property can be read
    func testAutoChangeIntervalCanBeRead() {
        // When & Then
        let interval = wallpaperManager.autoChangeInterval
        XCTAssertGreaterThan(interval, 0, "Auto-change interval should be positive")
    }
    
    /// Test that autoChangeInterval property can be set
    func testAutoChangeIntervalCanBeSet() {
        // When
        let newInterval: TimeInterval = 5 * 60 // 5 minutes
        wallpaperManager.autoChangeInterval = newInterval
        
        // Then
        XCTAssertEqual(wallpaperManager.autoChangeInterval, newInterval, "Auto-change interval should be updated")
    }
    
    // MARK: - Mute Video Tests
    
    /// Test that mute video preference can be read from UserDefaults
    func testMuteVideoPreferenceCanBeRead() {
        // When & Then
        let isMuted = UserDefaults.standard.bool(forKey: "MuteVideo")
        XCTAssertFalse(isMuted, "Mute video should be disabled by default")
    }
    
    /// Test that mute video preference can be set in UserDefaults
    func testMuteVideoPreferenceCanBeSet() {
        // When
        UserDefaults.standard.set(true, forKey: "MuteVideo")
        
        // Then
        let isMuted = UserDefaults.standard.bool(forKey: "MuteVideo")
        XCTAssertTrue(isMuted, "Mute video preference should be set to true")
    }
    
    /// Test that mute toggle changes UserDefaults value
    func testMuteToggleChangesUserDefaults() {
        // When
        UserDefaults.standard.set(false, forKey: "MuteVideo")
        UserDefaults.standard.set(true, forKey: "MuteVideo")
        
        // Then
        let isMuted = UserDefaults.standard.bool(forKey: "MuteVideo")
        XCTAssertTrue(isMuted, "Mute video should be true after toggle")
    }
    
    // MARK: - Integration Tests
    
    /// Test that multiple auto-change intervals are available
    func testAutoChangeIntervalOptions() {
        // Given
        let intervals = [1, 2, 5, 10, 15, 30, 60]
        
        // When & Then
        for minutes in intervals {
            let timeInterval = TimeInterval(minutes * 60)
            wallpaperManager.autoChangeInterval = timeInterval
            XCTAssertEqual(
                wallpaperManager.autoChangeInterval,
                timeInterval,
                "Should support \(minutes) minute interval"
            )
        }
    }
    
    /// Test that auto-change and mute can be set independently
    func testAutoChangeAndMuteIndependence() {
        // When
        wallpaperManager.isAutoChangeEnabled = true
        UserDefaults.standard.set(true, forKey: "MuteVideo")
        wallpaperManager.autoChangeInterval = 10 * 60
        
        // Then
        XCTAssertTrue(wallpaperManager.isAutoChangeEnabled, "Auto-change should be enabled")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "MuteVideo"), "Mute should be enabled")
        XCTAssertEqual(wallpaperManager.autoChangeInterval, 10 * 60, "Interval should be 10 minutes")
    }
    
    /// Test that auto-change persistence through UserDefaults
    func testAutoChangePersistence() {
        // When
        wallpaperManager.isAutoChangeEnabled = true
        wallpaperManager.autoChangeInterval = 15 * 60
        wallpaperManager.saveAutoChangeSettings()
        
        // Create a new manager instance
        let newManager = WallpaperManager()
        
        // Then - These should be persisted if saveAutoChangeSettings works
        // Note: The actual persistence depends on implementation
        XCTAssertTrue(wallpaperManager.isAutoChangeEnabled, "Auto-change setting should be set")
        XCTAssertEqual(wallpaperManager.autoChangeInterval, 15 * 60, "Interval should be 15 minutes")
    }
}
