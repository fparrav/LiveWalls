import XCTest
import Cocoa
@testable import LiveWalls

/// Tests for Phase 5: Window level consistency
/// Verifies that all desktop video windows use consistent window levels
/// and that levels don't change dynamically during operations
@MainActor
final class WindowLevelTests: XCTestCase {
    
    // MARK: - Properties
    
    var testScreen: NSScreen!
    var expectedWindowLevel: NSWindow.Level!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        testScreen = NSScreen.main ?? NSScreen()
        expectedWindowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
    }
    
    override func tearDown() {
        testScreen = nil
        expectedWindowLevel = nil
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    /// Test 1: All windows should use consistent window level
    /// Verifies DesktopVideoWindowMejorada and BackgroundColorWindow use same level
    func testConsistentWindowLevels() {
        // Create video window
        let testVideoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let videoWindow = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testVideoURL)
        
        // Create background window
        let backgroundWindow = BackgroundColorWindow(screen: testScreen)
        
        // Both should use kCGDesktopIconWindowLevel - 1
        XCTAssertEqual(
            videoWindow.level,
            expectedWindowLevel,
            "Video window should use kCGDesktopIconWindowLevel - 1"
        )
        
        XCTAssertEqual(
            backgroundWindow.level,
            expectedWindowLevel,
            "Background window should use kCGDesktopIconWindowLevel - 1"
        )
        
        XCTAssertEqual(
            videoWindow.level,
            backgroundWindow.level,
            "Video and background windows should have same level"
        )
        
        // Cleanup
        videoWindow.close()
        backgroundWindow.close()
    }
    
    /// Test 2: Window level should never change after creation
    /// Verifies updateForSpace() doesn't change the window level
    func testWindowLevelNeverChanges() {
        let testVideoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let videoWindow = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testVideoURL)
        let initialLevel = videoWindow.level
        
        // Verify initial level is correct
        XCTAssertEqual(
            initialLevel,
            expectedWindowLevel,
            "Initial window level should be kCGDesktopIconWindowLevel - 1"
        )
        
        // Call updateForSpace() - should not change window level
        videoWindow.updateForSpace()
        
        XCTAssertEqual(
            videoWindow.level,
            initialLevel,
            "Window level should remain unchanged after updateForSpace()"
        )
        
        // Call updateForSpace() multiple times - level should stay consistent
        videoWindow.updateForSpace()
        videoWindow.updateForSpace()
        
        XCTAssertEqual(
            videoWindow.level,
            initialLevel,
            "Window level should remain unchanged after multiple updateForSpace() calls"
        )
        
        // Cleanup
        videoWindow.close()
    }
    
    /// Test 3: Window levels should not change during transitions
    /// Verifies that transition operations don't manipulate z-ordering
    func testNoZOrderingDuringTransition() {
        let transitionManager = TransitionManager()
        let testVideoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let videoWindow1 = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testVideoURL)
        let videoWindow2 = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testVideoURL)
        
        let initialLevel1 = videoWindow1.level
        let initialLevel2 = videoWindow2.level
        
        // Start transition
        transitionManager.startCrossfadeTransition(
            fromWindow: videoWindow1,
            toWindow: videoWindow2
        )
        
        // Window levels should not change
        XCTAssertEqual(
            videoWindow1.level,
            initialLevel1,
            "Window level should not change during transition"
        )
        
        XCTAssertEqual(
            videoWindow2.level,
            initialLevel2,
            "Window level should not change during transition"
        )
        
        // Both windows should have same level
        XCTAssertEqual(
            videoWindow1.level,
            videoWindow2.level,
            "Both windows should maintain same level during transition"
        )
        
        // Cleanup
        transitionManager.stopCurrentTransition()
        videoWindow1.close()
        videoWindow2.close()
    }
    
    /// Test 4: BackgroundColorWindow uses correct level
    /// Verifies BackgroundColorWindow is at same level as video windows
    func testBackgroundColorWindowLevel() {
        let backgroundWindow = BackgroundColorWindow(screen: testScreen)
        
        // Should use same level as video windows
        XCTAssertEqual(
            backgroundWindow.level,
            expectedWindowLevel,
            "BackgroundColorWindow should use kCGDesktopIconWindowLevel - 1"
        )
        
        // Verify it's above system wallpaper but below icons
        let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        let desktopIconLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        
        XCTAssertGreaterThan(
            backgroundWindow.level.rawValue,
            desktopLevel.rawValue,
            "Window level should be above system wallpaper"
        )
        
        XCTAssertLessThan(
            backgroundWindow.level.rawValue,
            desktopIconLevel.rawValue,
            "Window level should be below desktop icons"
        )
        
        // Cleanup
        backgroundWindow.close()
    }
    
    /// Test 5: Windows maintain visibility on multiple screens
    /// Integration test verifying windows are visible across all screens
    func testWindowsAlwaysVisible() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return // Skip if no screens
        }
        
        // Create windows on all available screens
        let testVideoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let windows = screens.map { screen in
            DesktopVideoWindowMejorada(screen: screen, videoURL: testVideoURL)
        }
        
        defer {
            windows.forEach { $0.close() }
        }
        
        // All windows should have correct level
        for window in windows {
            XCTAssertEqual(
                window.level,
                expectedWindowLevel,
                "All windows should use consistent level regardless of screen"
            )
        }
        
        // Verify windows are not at desktop level (would be hidden)
        let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        for window in windows {
            XCTAssertGreaterThan(
                window.level.rawValue,
                desktopLevel.rawValue,
                "Windows should be above system wallpaper on all screens"
            )
        }
        
        // Verify windows are not at icon level (would appear behind icons)
        let desktopIconLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        for window in windows {
            XCTAssertLessThan(
                window.level.rawValue,
                desktopIconLevel.rawValue,
                "Windows should be below desktop icons on all screens"
            )
        }
    }
    
    /// Test 6: Window level after updateForSpace() is still correct
    /// Explicit regression test for the Phase 5 bug fix
    func testUpdateForSpaceUsesCorrectLevel() {
        let testVideoURL = URL(fileURLWithPath: "/tmp/test.mp4")
        let videoWindow = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testVideoURL)
        
        // Verify initial setup uses correct level
        XCTAssertEqual(
            videoWindow.level,
            expectedWindowLevel,
            "Setup should use kCGDesktopIconWindowLevel - 1"
        )
        
        // The bug was that updateForSpace() used kCGDesktopWindow instead
        let wrongLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        XCTAssertNotEqual(
            videoWindow.level,
            wrongLevel,
            "Window should NOT be at desktop level (that was the bug)"
        )
        
        // After updateForSpace, should still be correct
        videoWindow.updateForSpace()
        XCTAssertEqual(
            videoWindow.level,
            expectedWindowLevel,
            "updateForSpace() should maintain correct window level"
        )
        
        XCTAssertNotEqual(
            videoWindow.level,
            wrongLevel,
            "After updateForSpace(), should still NOT be at desktop level"
        )
        
        // Cleanup
        videoWindow.close()
    }
}
