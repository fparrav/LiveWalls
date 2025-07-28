import XCTest
@testable import LiveWalls

@MainActor
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
    
    func testAddVideoFiles() async {
        // Given
        let videoURL = URL(fileURLWithPath: "/test/video.mp4")
        let videoName = "video"
        
        // When
        await wallpaperManager.addVideoFiles(urls: [videoURL])
        
        // Then
        XCTAssertEqual(wallpaperManager.videoFiles.count, 1)
        XCTAssertEqual(wallpaperManager.videoFiles.first?.name, videoName)
        XCTAssertTrue(wallpaperManager.videoFiles.first?.isEnabledForRandomPlay ?? false)
    }
    
    func testSetActiveVideo() async {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil,
                            isEnabledForRandomPlay: true)
        
        // When
        await wallpaperManager.setActiveVideo(video)
        
        // Then
        XCTAssertEqual(wallpaperManager.currentVideo?.name, video.name)
    }
    
    func testRemoveVideo() async {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil,
                            isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        
        // When
        await wallpaperManager.removeVideo(video)
        
        // Then
        XCTAssertTrue(wallpaperManager.videoFiles.isEmpty)
    }
    
    // MARK: - Wallpaper Control Tests
    
    func testStartWallpaper() async {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil,
                            isEnabledForRandomPlay: true)
        wallpaperManager.currentVideo = video
        
        // When
        await wallpaperManager.startWallpaperSafe()
        
        // Then
        XCTAssertTrue(wallpaperManager.isPlayingWallpaper)
    }
    
    func testStopWallpaper() async {
        // Given
        wallpaperManager.isPlayingWallpaper = true
        
        // When
        await wallpaperManager.stopWallpaper()
        
        // Then
        XCTAssertFalse(wallpaperManager.isPlayingWallpaper)
    }
    
    // MARK: - Bookmark Resolution Tests
    
    func testResolveBookmark() async {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil,
                            isEnabledForRandomPlay: true)
        
        // When
        let resolvedURL = await wallpaperManager.resolveBookmark(for: video)
        
        // Then
        XCTAssertNil(resolvedURL) // Debería ser nil porque no hay bookmark data
    }
    
    // MARK: - Nueva Funcionalidad Tests
    
    func testToggleVideoRandomPlayEnabled() async {
        // Given
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil,
                            isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        
        // When
        await wallpaperManager.toggleVideoRandomPlayEnabled(video)
        
        // Then
        XCTAssertFalse(wallpaperManager.videoFiles.first?.isEnabledForRandomPlay ?? true)
        
        // When - toggle again
        await wallpaperManager.toggleVideoRandomPlayEnabled(video)
        
        // Then
        XCTAssertTrue(wallpaperManager.videoFiles.first?.isEnabledForRandomPlay ?? false)
    }
    
    func testCanGoToNextWallpaper() {
        // Given - videos with different random play settings
        let enabledVideo = VideoFile(url: URL(fileURLWithPath: "/test/video1.mp4"),
                                   name: "Enabled Video",
                                   bookmarkData: nil,
                                   isEnabledForRandomPlay: true)
        let disabledVideo = VideoFile(url: URL(fileURLWithPath: "/test/video2.mp4"),
                                    name: "Disabled Video",
                                    bookmarkData: nil,
                                    isEnabledForRandomPlay: false)
        wallpaperManager.videoFiles = [enabledVideo, disabledVideo]
        
        // Then - should have at least one video available for next wallpaper
        XCTAssertTrue(wallpaperManager.canGoToNextWallpaper)
        
        // Given - no videos enabled for random play
        wallpaperManager.videoFiles = [disabledVideo]
        
        // Then - should not be able to go to next wallpaper
        XCTAssertFalse(wallpaperManager.canGoToNextWallpaper)
    }
    
    func testNextWallpaper() async {
        // Given
        let video1 = VideoFile(url: URL(fileURLWithPath: "/test/video1.mp4"),
                             name: "Video 1",
                             bookmarkData: nil,
                             isEnabledForRandomPlay: true)
        let video2 = VideoFile(url: URL(fileURLWithPath: "/test/video2.mp4"),
                             name: "Video 2",
                             bookmarkData: nil,
                             isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video1, video2]
        wallpaperManager.currentVideo = video1
        
        // When
        await wallpaperManager.nextWallpaper()
        
        // Then - current video should still be set (might be same due to randomness)
        XCTAssertNotNil(wallpaperManager.currentVideo)
        XCTAssertTrue([video1.id, video2.id].contains(wallpaperManager.currentVideo?.id))
    }
    
    // MARK: - New Fullscreen and Timer Tests
    
    func testFullscreenDetection() async {
        // Test que el detector de fullscreen se inicializa correctamente
        // Nota: Esto requerirá que FullscreenDetector esté agregado al proyecto
        XCTAssertNotNil(wallpaperManager)
        
        // Por ahora, test básico de que el WallpaperManager inicializa sin errores
        XCTAssertFalse(wallpaperManager.isPlayingWallpaper)
    }
    
    func testTimerManagement() async {
        // Test básico de configuración de timer
        wallpaperManager.isAutoChangeEnabled = true
        wallpaperManager.autoChangeInterval = 60.0 // 1 minuto
        
        // Agregar algunos videos de prueba
        let video1 = VideoFile(url: URL(fileURLWithPath: "/test/video1.mp4"),
                             name: "Video 1",
                             bookmarkData: nil,
                             isEnabledForRandomPlay: true)
        let video2 = VideoFile(url: URL(fileURLWithPath: "/test/video2.mp4"),
                             name: "Video 2", 
                             bookmarkData: nil,
                             isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video1, video2]
        
        // Guardar configuración (esto debería configurar el timer)
        wallpaperManager.saveAutoChangeSettings()
        
        // Verificar que la configuración se guardó
        XCTAssertTrue(wallpaperManager.isAutoChangeEnabled)
        XCTAssertEqual(wallpaperManager.autoChangeInterval, 60.0)
    }
    
    func testVideoRandomPlayControl() async {
        // Test del control de reproducción aleatoria individual
        let video = VideoFile(url: URL(fileURLWithPath: "/test/video.mp4"),
                            name: "Test Video",
                            bookmarkData: nil,
                            isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [video]
        
        // Verificar estado inicial
        XCTAssertTrue(video.isEnabledForRandomPlay)
        
        // Toggle estado
        await wallpaperManager.toggleVideoRandomPlayEnabled(video)
        
        // Verificar que cambió
        XCTAssertFalse(wallpaperManager.videoFiles.first?.isEnabledForRandomPlay ?? true)
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
                        bookmarkData: nil,
                        isEnabledForRandomPlay: true)
    }
} 