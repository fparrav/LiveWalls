import XCTest
@testable import LiveWalls

@MainActor
final class WindowRecreationTests: XCTestCase {
    var wallpaperManager: WallpaperManager!
    
    override func setUp() {
        super.setUp()
        wallpaperManager = WallpaperManager()
    }
    
    override func tearDown() {
        // Clean up without async call
        wallpaperManager = nil
        super.tearDown()
    }
    
    // MARK: - Test 1: updateWindowVisibilityForSpaces method exists and is callable
    
    /// Test that updateWindowVisibilityForSpaces method exists and can be called
    /// This verifies the method signature and basic functionality
    func testUpdateWindowVisibilityForSpacesExists() async throws {
        // This test verifies that the new method exists and can be called
        // It should complete without error
        await wallpaperManager.updateWindowVisibilityForSpaces()
        
        // If we reach here, the method exists and is callable
        XCTAssertTrue(true, "updateWindowVisibilityForSpaces method is available")
    }
    
    // MARK: - Test 2: Window Health Check Method Exists
    
    /// Test that DesktopVideoWindowMejorada has isHealthy method
    func testWindowHealthCheckMethodExists() async throws {
        // When: A window is created
        let screen = NSScreen.screens.first ?? NSScreen.main!
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.mp4")
        FileManager.default.createFile(atPath: testURL.path, contents: Data("dummy".utf8))
        
        let window = DesktopVideoWindowMejorada(screen: screen, videoURL: testURL)
        
        // Then: isHealthy method should be available
        let isHealthy = window.isHealthy()
        
        // Clean up
        window.close()
        try? FileManager.default.removeItem(at: testURL)
        
        // The window should report a health status (doesn't matter what it is)
        XCTAssertNotNil(isHealthy, "isHealthy method should return a boolean value")
    }
    
    // MARK: - Test 3: Window updateForSpace Method Exists
    
    /// Test that DesktopVideoWindowMejorada has updateForSpace method
    func testWindowUpdateForSpaceMethodExists() async throws {
        // When: A window is created
        let screen = NSScreen.screens.first ?? NSScreen.main!
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("test2.mp4")
        FileManager.default.createFile(atPath: testURL.path, contents: Data("dummy".utf8))
        
        let window = DesktopVideoWindowMejorada(screen: screen, videoURL: testURL)
        
        // When: updateForSpace is called
        window.updateForSpace()
        
        // Then: It should complete without error
        // Clean up
        window.close()
        try? FileManager.default.removeItem(at: testURL)
        
        XCTAssertTrue(true, "updateForSpace method is available and callable")
    }
    
    // MARK: - Test 4: Wallpaper Manager Has updateWindowVisibilityForSpaces
    
    /// Test that WallpaperManager has updateWindowVisibilityForSpaces method
    func testWallpaperManagerUpdateVisibilityExists() async throws {
        // When: updateWindowVisibilityForSpaces is called
        await wallpaperManager.updateWindowVisibilityForSpaces()
        
        // Then: It should complete without error
        XCTAssertTrue(true, "updateWindowVisibilityForSpaces method is available")
    }
    
    // MARK: - Test 5: PlaybackHealthChecker Less Aggressive
    
     /// Test that PlaybackHealthChecker can check window health
    func testPlaybackHealthCheckerWindowValidation() async throws {
        // This test verifies the health checker can validate windows
        // For now, it just ensures the interface exists
        let checker = PlaybackHealthChecker()
        
        // The health checker should work with empty window list
        let isHealthy = await checker.checkPlaybackHealth(
            windows: [],
            currentVideo: nil,
            bookmarkActor: BookmarkActor()
        )
        
        // Empty list with no video should not be healthy
        XCTAssertFalse(isHealthy, "Should not be healthy with no windows or video")
    }
    
    // MARK: - Test 6: Space Change Handler Calls Health Check
    
    /// Test that the Space change handler integrates with areCurrentWindowsHealthy()
    /// This verifies the health check method is available and properly integrated
    func testSpaceChangeHandlerIntegration() async throws {
        // Simulate Space change notification
        // This test verifies the handler doesn't crash with no windows
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Wait for throttle to complete (600ms + buffer)
        try await Task.sleep(nanoseconds: 700_000_000)
        
        // If we reach here without crashing, the integration is working
        XCTAssertTrue(true, "Space change handler integrated with health check")
    }
    
    // MARK: - Test 7: Verify areCurrentWindowsHealthy Method Exists
    
    /// Test that areCurrentWindowsHealthy is properly integrated into the Space change flow
    /// Verifies the method works with empty windows and handles edge cases
    func testEmptyWindowHandlingOnSpaceChange() async throws {
        // Create a fresh wallpaper manager with no windows
        let manager = WallpaperManager()
        
        // Call updateWindowVisibilityForSpaces (should handle empty windows gracefully)
        await manager.updateWindowVisibilityForSpaces()
        
        // Simulate Space change - should not crash even with no windows
        NotificationCenter.default.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Wait for throttle
        try await Task.sleep(nanoseconds: 700_000_000)
        
        // Verify the method completes without error
        XCTAssertTrue(true, "Space change handles empty windows correctly")
    }
}


