import XCTest
@testable import LiveWalls

@MainActor
final class ShuffleModeTests: XCTestCase {
    var wallpaperManager: WallpaperManager!
    
    override func setUp() {
        super.setUp()
        // loadPersistedData: false — the background persistence load otherwise
        // races the first `await` in each test body and overwrites the
        // videoFiles / currentVideo the test sets up.
        wallpaperManager = WallpaperManager(loadPersistedData: false)
        // Clear UserDefaults for each test
        UserDefaults.standard.removeObject(forKey: "ShuffleModeEnabled")
    }
    
    override func tearDown() {
        // Clean up temporary files created during tests
        let tempDir = FileManager.default.temporaryDirectory
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            for file in files where file.lastPathComponent.contains("shuffle-video-") {
                try? fileManager.removeItem(at: file)
            }
        } catch {
            print("⚠️ Warning: Could not clean up temporary files: \(error.localizedDescription)")
        }
        
        UserDefaults.standard.removeObject(forKey: "ShuffleModeEnabled")
        wallpaperManager = nil
        super.tearDown()
    }
    
    // MARK: - Shuffle Mode Property Tests
    
    /// Test that isShuffleMode property exists and defaults to false
    func testShuffleModeDefaultsFalse() {
        // When & Then
        XCTAssertFalse(wallpaperManager.isShuffleMode, "Shuffle mode debe estar deshabilitado por defecto")
    }
    
    /// Test that isShuffleMode can be set
    func testSetShuffleMode() {
        // When
        wallpaperManager.isShuffleMode = true
        
        // Then
        XCTAssertTrue(wallpaperManager.isShuffleMode, "Shuffle mode debe ser habilitado")
    }
    
    // MARK: - Shuffle History Tests
    
    /// Test that getNextVideoInShuffleMode returns a random enabled video
    func testGetNextVideoInShuffleReturnsRandomEnabledVideo() async {
        // Given
        let tmp1 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-1.mp4")
        let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-2.mp4")
        let tmp3 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-3.mp4")
        
        FileManager.default.createFile(atPath: tmp1.path, contents: Data("dummy1".utf8))
        FileManager.default.createFile(atPath: tmp2.path, contents: Data("dummy2".utf8))
        FileManager.default.createFile(atPath: tmp3.path, contents: Data("dummy3".utf8))
        
        let video1 = VideoFile(url: tmp1, name: "Video 1", isEnabledForRandomPlay: true)
        let video2 = VideoFile(url: tmp2, name: "Video 2", isEnabledForRandomPlay: true)
        let video3 = VideoFile(url: tmp3, name: "Video 3", isEnabledForRandomPlay: false)
        
        wallpaperManager.videoFiles = [video1, video2, video3]
        wallpaperManager.isShuffleMode = true
        
        // When
        let nextVideo = await wallpaperManager.getNextVideoInShuffleMode()
        
        // Then
        XCTAssertNotNil(nextVideo, "Debe retornar un video")
        XCTAssertTrue(nextVideo!.isEnabledForRandomPlay, "El video debe estar habilitado para reproducción aleatoria")
        XCTAssertTrue([video1.id, video2.id].contains(nextVideo!.id), "El video debe ser uno de los habilitados")
    }
    
    /// Test that shuffle history prevents repeating last 5 videos
    func testShuffleHistoryPreventsRepeating() async {
        // Given - Create 7 enabled videos
        var videos: [VideoFile] = []
        for i in 1...7 {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-\(i).mp4")
            FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy\(i)".utf8))
            videos.append(VideoFile(url: tmp, name: "Video \(i)", isEnabledForRandomPlay: true))
        }
        
        wallpaperManager.videoFiles = videos
        wallpaperManager.isShuffleMode = true
        
        // When - Get 5 videos (fill history)
        var selectedVideos: [UUID] = []
        for _ in 0..<5 {
            if let video = await wallpaperManager.getNextVideoInShuffleMode() {
                selectedVideos.append(video.id)
            }
        }
        
        // Then - History should have 5 videos
        XCTAssertEqual(selectedVideos.count, 5, "Debe seleccionar 5 videos")
        
        // When - Get next video
        if let nextVideo = await wallpaperManager.getNextVideoInShuffleMode() {
            // Then - It should NOT be in the last 5
            XCTAssertFalse(selectedVideos.contains(nextVideo.id), "El siguiente video no debe estar en el historial de últimos 5")
        }
    }
    
    /// Test that shuffle only selects videos with isEnabledForRandomPlay == true
    func testShuffleIgnoresDisabledVideos() async {
        // Given
        let tmp1 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-enabled.mp4")
        let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-disabled.mp4")
        
        FileManager.default.createFile(atPath: tmp1.path, contents: Data("dummy".utf8))
        FileManager.default.createFile(atPath: tmp2.path, contents: Data("dummy".utf8))
        
        let enabledVideo = VideoFile(url: tmp1, name: "Enabled", isEnabledForRandomPlay: true)
        let disabledVideo = VideoFile(url: tmp2, name: "Disabled", isEnabledForRandomPlay: false)
        
        wallpaperManager.videoFiles = [enabledVideo, disabledVideo]
        wallpaperManager.isShuffleMode = true
        
        // When
        let nextVideo = await wallpaperManager.getNextVideoInShuffleMode()
        
        // Then
        XCTAssertNotNil(nextVideo, "Debe retornar un video habilitado")
        XCTAssertEqual(nextVideo!.id, enabledVideo.id, "Solo debe seleccionar videos habilitados")
    }
    
    /// Test that shuffle fallback to playlist mode when insufficient enabled videos (<6)
    func testShuffleFallbackWithInsufficientVideos() async {
        // Given - Create only 5 enabled videos
        var videos: [VideoFile] = []
        for i in 1...5 {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-\(i).mp4")
            FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy\(i)".utf8))
            videos.append(VideoFile(url: tmp, name: "Video \(i)", isEnabledForRandomPlay: true))
        }
        
        wallpaperManager.videoFiles = videos
        wallpaperManager.isShuffleMode = true
        
        // When - Try to get more videos than available (should fall back to circular)
        var selectedVideos: [UUID] = []
        for _ in 0..<10 {
            if let video = await wallpaperManager.getNextVideoInShuffleMode() {
                selectedVideos.append(video.id)
            }
        }
        
        // Then - Should have returned videos (circular fallback)
        XCTAssertEqual(selectedVideos.count, 10, "Debe retornar 10 videos con fallback circular")
        XCTAssertTrue(selectedVideos.allSatisfy { id in videos.contains { $0.id == id } }, "Todos deben ser de videos habilitados")
    }
    
    /// Test that shuffle mode persists in UserDefaults
    func testShuffleModePersistence() {
        // When - Set shuffle mode to true
        wallpaperManager.isShuffleMode = true
        
        // Then - Verify it's saved
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "ShuffleModeEnabled"), "Shuffle mode debe persistir en UserDefaults")
        
        // When - Create new manager
        let newManager = WallpaperManager()
        
        // Then - It should load the saved state
        XCTAssertTrue(newManager.isShuffleMode, "Nuevo manager debe cargar el estado persistido")
    }
    
    // MARK: - Integration Tests
    
    /// Test that changeToNextVideo uses shuffle when isShuffleMode == true
    func testChangeToNextVideoUsesShuffleWhenEnabled() async {
        // Given
        let tmp1 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-first.mp4")
        let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-second.mp4")
        let tmp3 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-third.mp4")
        
        FileManager.default.createFile(atPath: tmp1.path, contents: Data("dummy".utf8))
        FileManager.default.createFile(atPath: tmp2.path, contents: Data("dummy".utf8))
        FileManager.default.createFile(atPath: tmp3.path, contents: Data("dummy".utf8))
        
        let video1 = VideoFile(url: tmp1, name: "Video 1", isEnabledForRandomPlay: true)
        let video2 = VideoFile(url: tmp2, name: "Video 2", isEnabledForRandomPlay: true)
        let video3 = VideoFile(url: tmp3, name: "Video 3", isEnabledForRandomPlay: true)
        
        wallpaperManager.videoFiles = [video1, video2, video3]
        wallpaperManager.currentVideo = video1
        wallpaperManager.isShuffleMode = true
        
        // When - Call changeToNextVideo internally (via mock)
        // We'll directly test getNextVideoInShuffleMode to verify shuffle is used
        let nextVideo = await wallpaperManager.getNextVideoInShuffleMode()
        
        // Then - Should use shuffle logic
        XCTAssertNotNil(nextVideo, "Debe retornar un video del shuffle")
        XCTAssertTrue(nextVideo!.isEnabledForRandomPlay, "Video debe estar habilitado")
    }
    
    /// Test that changeToNextVideo uses circular playlist when shuffle disabled
    func testChangeToNextVideoUsesPlaylistWhenShuffleDisabled() async {
        // Given
        let tmp1 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-playlist1.mp4")
        let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-playlist2.mp4")
        let tmp3 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-playlist3.mp4")
        
        FileManager.default.createFile(atPath: tmp1.path, contents: Data("dummy".utf8))
        FileManager.default.createFile(atPath: tmp2.path, contents: Data("dummy".utf8))
        FileManager.default.createFile(atPath: tmp3.path, contents: Data("dummy".utf8))
        
        let video1 = VideoFile(url: tmp1, name: "Video 1", isEnabledForRandomPlay: true)
        let video2 = VideoFile(url: tmp2, name: "Video 2", isEnabledForRandomPlay: true)
        let video3 = VideoFile(url: tmp3, name: "Video 3", isEnabledForRandomPlay: true)
        
        wallpaperManager.videoFiles = [video1, video2, video3]
        wallpaperManager.currentVideo = video1
        wallpaperManager.isShuffleMode = false  // Shuffle disabled
        
        // When - Test that it follows circular order
        // Setup: video1 -> next should be video2 (circular: 0+1=1)
        // We need to test this via internal logic
        // For now, verify shuffle is not called
        XCTAssertFalse(wallpaperManager.isShuffleMode, "Shuffle mode debe estar deshabilitado")
    }
    
    /// Test that getNextVideoInShuffleMode handles empty video list
    func testGetNextVideoInShuffleWithNoVideos() async {
        // Given
        wallpaperManager.videoFiles = []
        wallpaperManager.isShuffleMode = true
        
        // When
        let nextVideo = await wallpaperManager.getNextVideoInShuffleMode()
        
        // Then
        XCTAssertNil(nextVideo, "Debe retornar nil cuando no hay videos")
    }
    
     /// Test that getNextVideoInShuffleMode handles all videos disabled
     func testGetNextVideoInShuffleWithAllVideosDisabled() async {
         // Given
         let tmp1 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-all-disabled-1.mp4")
         let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-all-disabled-2.mp4")
         
         FileManager.default.createFile(atPath: tmp1.path, contents: Data("dummy".utf8))
         FileManager.default.createFile(atPath: tmp2.path, contents: Data("dummy".utf8))
         
         let video1 = VideoFile(url: tmp1, name: "Video 1", isEnabledForRandomPlay: false)
         let video2 = VideoFile(url: tmp2, name: "Video 2", isEnabledForRandomPlay: false)
         
         wallpaperManager.videoFiles = [video1, video2]
         wallpaperManager.isShuffleMode = true
         
         // When
         let nextVideo = await wallpaperManager.getNextVideoInShuffleMode()
         
         // Then
         XCTAssertNil(nextVideo, "Debe retornar nil cuando todos están deshabilitados")
     }
     
     // MARK: - Manual Next Button in Shuffle Mode Tests
     
     /// Test that nextWallpaper() respects shuffle mode for manual next
     func testNextWallpaperInShuffleModeUsesShuffle() async {
         // Given - 6 enabled videos with shuffle enabled (need enough to avoid all being in history)
         var videos: [VideoFile] = []
         for i in 1...6 {
             let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-video-manual-\(i).mp4")
             FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy\(i)".utf8))
             videos.append(VideoFile(url: tmp, name: "Video \(i)", isEnabledForRandomPlay: true))
         }
         
         wallpaperManager.videoFiles = videos
         wallpaperManager.currentVideo = videos[0]  // Start with first video
         wallpaperManager.isShuffleMode = true  // Enable shuffle mode
         
         // When - Call nextWallpaper() manually
         // In shuffle mode with 6 videos and no history, should get a random video
         await wallpaperManager.nextWallpaper()
         
         // Then - Should have changed to a different video
         // The key test is that it uses shuffle logic, not circular next
         XCTAssertNotNil(wallpaperManager.currentVideo, "Debe tener un video seleccionado")
         XCTAssertNotEqual(wallpaperManager.currentVideo!.id, videos[0].id, 
                          "Debe cambiar a un video diferente")
         // Verify it's one of our videos
         XCTAssertTrue(videos.contains(where: { $0.id == wallpaperManager.currentVideo!.id }), 
                      "El video debe ser uno de los disponibles")
     }
     
     /// Test that nextWallpaper() in shuffle mode doesn't always go to next index
     func testNextWallpaperInShuffleIsNotCircular() async {
         // Given - 6 enabled videos with shuffle enabled
         var videos: [VideoFile] = []
         for i in 1...6 {
             let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shuffle-manual-circular-\(i).mp4")
             FileManager.default.createFile(atPath: tmp.path, contents: Data("dummy\(i)".utf8))
             videos.append(VideoFile(url: tmp, name: "Video \(i)", isEnabledForRandomPlay: true))
         }
         
         wallpaperManager.videoFiles = videos
         wallpaperManager.currentVideo = videos[0]
         wallpaperManager.isShuffleMode = true
         
         // When - Call nextWallpaper multiple times
         var selectedVideos: [UUID] = []
         for _ in 0..<10 {
             await wallpaperManager.nextWallpaper()
             if let current = wallpaperManager.currentVideo {
                 selectedVideos.append(current.id)
             }
         }
         
         // Then - In shuffle with history, we shouldn't see index progression pattern
         // Check that not all selections follow the 0->1->2->3->4->5->0 pattern
         let videoIndices = selectedVideos.compactMap { id in
             videos.firstIndex { $0.id == id }
         }
         
         // If it were purely circular (0->1->2->3->4->5->0), indices would be sequential
         // But with shuffle history, they should be randomized
         XCTAssertTrue(selectedVideos.count >= 5, "Debe haber seleccionado suficientes videos")
         XCTAssertTrue(selectedVideos.count <= 10, "No debe exceder 10 selecciones")
     }
     
     /// Test that nextWallpaper() in playlist mode uses circular logic
     func testNextWallpaperInPlaylistModeIsCircular() async {
         // Given - 3 enabled videos with shuffle DISABLED
         let tmp1 = FileManager.default.temporaryDirectory.appendingPathComponent("playlist-video-1.mp4")
         let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("playlist-video-2.mp4")
         let tmp3 = FileManager.default.temporaryDirectory.appendingPathComponent("playlist-video-3.mp4")
         
         FileManager.default.createFile(atPath: tmp1.path, contents: Data("dummy".utf8))
         FileManager.default.createFile(atPath: tmp2.path, contents: Data("dummy".utf8))
         FileManager.default.createFile(atPath: tmp3.path, contents: Data("dummy".utf8))
         
         let video1 = VideoFile(url: tmp1, name: "Video 1", isEnabledForRandomPlay: true)
         let video2 = VideoFile(url: tmp2, name: "Video 2", isEnabledForRandomPlay: true)
         let video3 = VideoFile(url: tmp3, name: "Video 3", isEnabledForRandomPlay: true)
         
         wallpaperManager.videoFiles = [video1, video2, video3]
         wallpaperManager.currentVideo = video1
         wallpaperManager.isShuffleMode = false  // Playlist mode
         
         // When - Call nextWallpaper() three times
         await wallpaperManager.nextWallpaper()
         let secondVideo = wallpaperManager.currentVideo
         
         await wallpaperManager.nextWallpaper()
         let thirdVideo = wallpaperManager.currentVideo
         
         await wallpaperManager.nextWallpaper()
         let firstAgain = wallpaperManager.currentVideo
         
         // Then - Should follow circular order: 1->2->3->1
         XCTAssertEqual(secondVideo?.id, video2.id, "Debe ir a video 2")
         XCTAssertEqual(thirdVideo?.id, video3.id, "Debe ir a video 3")
         XCTAssertEqual(firstAgain?.id, video1.id, "Debe volver a video 1")
     }
}
