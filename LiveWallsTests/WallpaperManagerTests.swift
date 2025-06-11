import XCTest
@testable import LiveWalls

final class WallpaperManagerTests: XCTestCase {
    var wallpaperManager: WallpaperManager!
    
    override func setUp() {
        super.setUp()
        wallpaperManager = WallpaperManager()
    }
    
    override func tearDown() {
        wallpaperManager = nil
        super.tearDown()
    }
    
    // MARK: - Video Management Tests
    
    func testAddVideoFiles() {
        // Given
        let videoURL = URL(fileURLWithPath: "/test/video.mp4")
        let videoName = "Test Video"
        
        // When
        wallpaperManager.addVideoFiles(urls: [videoURL])
        
        // Then
        XCTAssertEqual(wallpaperManager.videoFiles.count, 1)
        XCTAssertEqual(wallpaperManager.videoFiles.first?.name, videoName)
    }
    
    func testSetActiveVideo() {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil)
        
        // When
        wallpaperManager.setActiveVideo(video)
        
        // Then
        XCTAssertEqual(wallpaperManager.currentVideo?.name, video.name)
    }
    
    func testRemoveVideo() {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil)
        wallpaperManager.videoFiles = [video]
        
        // When
        wallpaperManager.removeVideo(video)
        
        // Then
        XCTAssertTrue(wallpaperManager.videoFiles.isEmpty)
    }
    
    // MARK: - Wallpaper Control Tests
    
    func testStartWallpaper() {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil)
        wallpaperManager.currentVideo = video
        
        // When
        wallpaperManager.startWallpaper()
        
        // Then
        XCTAssertTrue(wallpaperManager.isPlayingWallpaper)
    }
    
    func testStopWallpaper() {
        // Given
        wallpaperManager.isPlayingWallpaper = true
        
        // When
        wallpaperManager.stopWallpaper()
        
        // Then
        XCTAssertFalse(wallpaperManager.isPlayingWallpaper)
    }
    
    // MARK: - Bookmark Resolution Tests
    
    func testResolveBookmark() {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil)
        
        // When
        let resolvedURL = wallpaperManager.resolveBookmark(for: video)
        
        // Then
        XCTAssertNil(resolvedURL) // Debería ser nil porque no hay bookmark data
    }
}

// MARK: - Mock Objects

class MockNotificationManager: NotificationManager {
    var lastError: String?
    
    override func showError(message: String) {
        lastError = message
    }
}

// MARK: - Test Helpers

extension WallpaperManagerTests {
    func createTestVideoFile() -> VideoFile {
        return VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                        name: "Test Video",
                        bookmarkData: nil)
    }
} 