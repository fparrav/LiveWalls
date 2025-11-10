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
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("video-test.mp4")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy".utf8))
        let videoURL = tmp
        let videoName = "video"
        
        // When
        await wallpaperManager.addVideoFiles(urls: [videoURL])
        
        // Then
        XCTAssertEqual(wallpaperManager.videoFiles.count, 1, "Debe agregarse un video")
        XCTAssertEqual(wallpaperManager.videoFiles.first?.name, "video-test", "Nombre basado en filename sin extensión")
        XCTAssertTrue(wallpaperManager.videoFiles.first?.isEnabledForRandomPlay ?? false, "Por defecto habilitado para reproducción aleatoria")
    }
    
    func testSetActiveVideo() async {
        // Given
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("video-active.mp4")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy".utf8))
        let video = VideoFile(url: tmp,
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
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("video-remove.mp4")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy".utf8))
        let video = VideoFile(url: tmp,
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
    
    func testStartWallpaper() async throws {
        // Given
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("video-static.mp4")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy".utf8))
        let video = VideoFile(url: tmp,
                            name: "Test Video",
                            bookmarkData: nil,
                            isEnabledForRandomPlay: true)
        wallpaperManager.currentVideo = video
        
        // When
        await wallpaperManager.startWallpaperSafe()
        
        throw XCTSkip("Start wallpaper requiere bookmark y acceso a pantalla; se omite en unit tests")
    }
    
    func testStopWallpaper() async throws {
        // Given
        wallpaperManager.isPlayingWallpaper = true
        
        // When
        await wallpaperManager.stopWallpaper()
        
        throw XCTSkip("Stop wallpaper depende de ventanas y player; se omite en unit tests")
    }
    
    // MARK: - Bookmark Resolution Tests
    
    func testResolveBookmark() async {
        // Given
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("video-toggle.mp4")
        FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy".utf8))
        let video = VideoFile(url: tmp,
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
        var videoA = VideoFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("video-enabled1.mp4"),
                       name: "Enabled Video",
                       bookmarkData: nil,
                       isEnabledForRandomPlay: true)
        var videoB = VideoFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("video-enabled2.mp4"),
                        name: "Enabled Video 2",
                        bookmarkData: nil,
                        isEnabledForRandomPlay: true)
        wallpaperManager.videoFiles = [videoA, videoB]
        
        // Then - con auto-change ON y 2 habilitados debe permitir siguiente
        wallpaperManager.isAutoChangeEnabled = true
        XCTAssertTrue(wallpaperManager.canGoToNextWallpaper)
        
        // Given - no videos enabled for random play
        videoB.isEnabledForRandomPlay = false
        wallpaperManager.videoFiles = [videoB]
        
        // Then - should not be able to go to next wallpaper
        XCTAssertFalse(wallpaperManager.canGoToNextWallpaper)
    }
    
    func testNextWallpaper() async {
        // Given
        let video1 = VideoFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("video-next1.mp4"),
                             name: "Video 1",
                             bookmarkData: nil,
                             isEnabledForRandomPlay: true)
        let video2 = VideoFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("video-next2.mp4"),
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
        let video1 = VideoFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("video-timer1.mp4"),
                             name: "Video 1",
                             bookmarkData: nil,
                             isEnabledForRandomPlay: true)
        let video2 = VideoFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("video-timer2.mp4"),
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
        let video = VideoFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("video-random.mp4"),
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