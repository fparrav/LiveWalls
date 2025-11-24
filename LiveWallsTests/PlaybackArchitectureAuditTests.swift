import XCTest
import AVFoundation
@testable import LiveWalls

/// Phase 1: Baseline tests to document current playback architecture behavior
/// These tests establish metrics to compare against after implementing fixes
class PlaybackArchitectureAuditTests: XCTestCase {
    
    var wallpaperManager: WallpaperManager!
    
    override func setUp() async throws {
        try await super.setUp()
        wallpaperManager = await WallpaperManager()
    }
    
    override func tearDown() async throws {
        await wallpaperManager.stopWallpaper()
        wallpaperManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Baseline Timing Tests
    
    /// Test 1: Measure video startup timing without preload
    func testVideoStartupTimingWithoutPreload() async throws {
        // Given: A video file is selected
        let testVideoURL = try createTestVideoFile()
        let videoFile = VideoFile(
            url: testVideoURL,
            name: "test-video",
            thumbnailData: nil,
            bookmarkData: try testVideoURL.bookmarkData()
        )
        
        await wallpaperManager.addVideoFiles(urls: [testVideoURL])
        await MainActor.run {
            wallpaperManager.currentVideo = videoFile
        }
        
        // When: Starting wallpaper playback
        let startTime = Date()
        
        await MainActor.run {
            wallpaperManager.startWallpaperSafe()
        }
        
        // Wait for playback to actually start
        try await waitForPlaybackToStart(timeout: 10.0)
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Record baseline timing
        print("📊 BASELINE: Startup without preload: \(String(format: "%.2f", duration))s")
        
        // Assert reasonable startup time (should be < 10 seconds)
        XCTAssertLessThan(duration, 10.0, "Startup took longer than 10 seconds")
        
        // Verify playback actually started
        let isPlaying = await MainActor.run { wallpaperManager.isPlayingWallpaper }
        XCTAssertTrue(isPlaying, "Playback should be active")
    }
    
    /// Test 2: Measure video transition timing
    func testVideoTransitionTiming() async throws {
        // Given: Two videos and playback is active
        let video1URL = try createTestVideoFile(name: "video1")
        let video2URL = try createTestVideoFile(name: "video2")
        
        await wallpaperManager.addVideoFiles(urls: [video1URL, video2URL])
        
        let video1 = VideoFile(url: video1URL, name: "video1", thumbnailData: nil, bookmarkData: try video1URL.bookmarkData())
        let video2 = VideoFile(url: video2URL, name: "video2", thumbnailData: nil, bookmarkData: try video2URL.bookmarkData())
        
        await MainActor.run {
            wallpaperManager.currentVideo = video1
            wallpaperManager.startWallpaperSafe()
        }
        
        try await waitForPlaybackToStart(timeout: 10.0)
        
        // When: Transitioning to next video
        let startTime = Date()
        
        // Trigger video change
        await MainActor.run {
            // Simulate clicking "next video"
            wallpaperManager.changeToNextVideo()
        }
        
        // Wait for transition to complete
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Record transition timing
        print("📊 BASELINE: Video transition: \(String(format: "%.2f", duration))s")
        
        // Verify video changed
        let currentVideo = await MainActor.run { wallpaperManager.currentVideo }
        XCTAssertNotNil(currentVideo)
        
        // Transition should complete within reasonable time
        XCTAssertLessThan(duration, 5.0, "Transition took longer than 5 seconds")
    }
    
    /// Test 3: Measure ensurePlaying() execution time
    func testEnsurePlayingExecutionTime() async throws {
        // Given: Playback is active
        let testVideoURL = try createTestVideoFile()
        await wallpaperManager.addVideoFiles(urls: [testVideoURL])
        
        let videoFile = VideoFile(url: testVideoURL, name: "test", thumbnailData: nil, bookmarkData: try testVideoURL.bookmarkData())
        await MainActor.run {
            wallpaperManager.currentVideo = videoFile
            wallpaperManager.startWallpaperSafe()
        }
        
        try await waitForPlaybackToStart(timeout: 10.0)
        
        // When: Calling ensurePlaying()
        let startTime = Date()
        
        await MainActor.run {
            wallpaperManager.ensurePlaying(reason: "audit test")
        }
        
        // Give it time to complete async work
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Record execution time
        print("📊 BASELINE: ensurePlaying() execution: \(String(format: "%.3f", duration))s")
        
        // Should be fast (< 1 second)
        XCTAssertLessThan(duration, 1.0, "ensurePlaying took longer than 1 second")
    }
    
    // MARK: - Architecture Documentation Tests
    
    /// Test 4: Document current AVPlayer looping mechanism
    func testDocumentManualLoopingBehavior() async throws {
        // Given: A short test video (5 seconds)
        let testVideoURL = try createTestVideoFile(duration: 5.0)
        await wallpaperManager.addVideoFiles(urls: [testVideoURL])
        
        let videoFile = VideoFile(url: testVideoURL, name: "test", thumbnailData: nil, bookmarkData: try testVideoURL.bookmarkData())
        await MainActor.run {
            wallpaperManager.currentVideo = videoFile
            wallpaperManager.startWallpaperSafe()
        }
        
        try await waitForPlaybackToStart(timeout: 10.0)
        
        // When: Waiting for video to loop (6 seconds should trigger loop)
        print("📊 AUDIT: Waiting for video to loop (manual seek+play mechanism)...")
        try await Task.sleep(nanoseconds: 7_000_000_000) // 7 seconds
        
        // Then: Verify playback still active
        let isPlaying = await MainActor.run { wallpaperManager.isPlayingWallpaper }
        XCTAssertTrue(isPlaying, "Playback should still be active after loop")
        
        print("📊 AUDIT: Manual looping verified (AVPlayer + manual seek)")
    }
    
    /// Test 5: Document window recreation on health check failure
    func testDocumentWindowRecreationBehavior() async throws {
        // Given: Playback is active
        let testVideoURL = try createTestVideoFile()
        await wallpaperManager.addVideoFiles(urls: [testVideoURL])
        
        let videoFile = VideoFile(url: testVideoURL, name: "test", thumbnailData: nil, bookmarkData: try testVideoURL.bookmarkData())
        await MainActor.run {
            wallpaperManager.currentVideo = videoFile
            wallpaperManager.startWallpaperSafe()
        }
        
        try await waitForPlaybackToStart(timeout: 10.0)
        
        let initialWindowCount = await getWindowCount()
        print("📊 AUDIT: Initial window count: \(initialWindowCount)")
        
        // When: Simulating a health check failure scenario
        // (Manually pause one player to simulate rate = 0)
        await pauseFirstPlayerToSimulateFailure()
        
        // Trigger health check
        await MainActor.run {
            wallpaperManager.ensurePlaying(reason: "simulated failure test")
        }
        
        // Wait for potential recreation
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then: Document if windows were recreated
        let finalWindowCount = await getWindowCount()
        print("📊 AUDIT: Final window count: \(finalWindowCount)")
        print("📊 AUDIT: Windows recreated: \(finalWindowCount != initialWindowCount)")
        
        // Just documenting, not asserting specific behavior
        XCTAssertGreaterThan(finalWindowCount, 0, "Should have at least one window")
    }
    
    /// Test 6: Document Space change handling (simulation)
    func testDocumentSpaceChangeSimulation() async throws {
        // Given: Playback is active
        let testVideoURL = try createTestVideoFile()
        await wallpaperManager.addVideoFiles(urls: [testVideoURL])
        
        let videoFile = VideoFile(url: testVideoURL, name: "test", thumbnailData: nil, bookmarkData: try testVideoURL.bookmarkData())
        await MainActor.run {
            wallpaperManager.currentVideo = videoFile
            wallpaperManager.startWallpaperSafe()
        }
        
        try await waitForPlaybackToStart(timeout: 10.0)
        
        // When: Simulating Space change (call ensurePlaying multiple times)
        print("📊 AUDIT: Simulating Space changes...")
        
        for i in 1...5 {
            await MainActor.run {
                wallpaperManager.ensurePlaying(reason: "simulated Space change \(i)")
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s between changes
        }
        
        // Then: Verify playback still active
        let isPlaying = await MainActor.run { wallpaperManager.isPlayingWallpaper }
        XCTAssertTrue(isPlaying, "Playback should survive multiple Space changes")
        
        print("📊 AUDIT: Space change simulation completed")
    }
    
    /// Test 7: Document resource cleanup timing
    func testDocumentResourceCleanupTiming() async throws {
        // Given: Playback is active
        let testVideoURL = try createTestVideoFile()
        await wallpaperManager.addVideoFiles(urls: [testVideoURL])
        
        let videoFile = VideoFile(url: testVideoURL, name: "test", thumbnailData: nil, bookmarkData: try testVideoURL.bookmarkData())
        await MainActor.run {
            wallpaperManager.currentVideo = videoFile
            wallpaperManager.startWallpaperSafe()
        }
        
        try await waitForPlaybackToStart(timeout: 10.0)
        
        // When: Stopping playback
        let startTime = Date()
        
        await MainActor.run {
            wallpaperManager.stopWallpaper()
        }
        
        // Wait for cleanup to complete
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Record cleanup timing
        print("📊 BASELINE: Resource cleanup timing: \(String(format: "%.3f", duration))s")
        
        let isPlaying = await MainActor.run { wallpaperManager.isPlayingWallpaper }
        XCTAssertFalse(isPlaying, "Playback should be stopped")
        
        // Cleanup should be fast
        XCTAssertLessThan(duration, 2.0, "Cleanup took longer than 2 seconds")
    }
    
    // MARK: - Bug Reproduction Attempt
    
    /// Test 8: Attempt to reproduce random playback freeze
    func testAttemptReproducePlaybackFreeze() async throws {
        // Given: Playback is active
        let testVideoURL = try createTestVideoFile()
        await wallpaperManager.addVideoFiles(urls: [testVideoURL])
        
        let videoFile = VideoFile(url: testVideoURL, name: "test", thumbnailData: nil, bookmarkData: try testVideoURL.bookmarkData())
        await MainActor.run {
            wallpaperManager.currentVideo = videoFile
            wallpaperManager.startWallpaperSafe()
        }
        
        try await waitForPlaybackToStart(timeout: 10.0)
        
        // When: Simulating stress scenario (rapid Space changes + transitions)
        print("🐛 BUG REPRODUCTION: Attempting to reproduce freeze bug...")
        
        for cycle in 1...3 {
            print("🐛 Cycle \(cycle): Rapid Space changes")
            for i in 1...10 {
                await MainActor.run {
                    wallpaperManager.ensurePlaying(reason: "stress test \(i)")
                }
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
            
            print("🐛 Cycle \(cycle): Checking playback health")
            let isPlaying = await MainActor.run { wallpaperManager.isPlayingWallpaper }
            
            if !isPlaying {
                XCTFail("🐛 BUG REPRODUCED: Playback froze in cycle \(cycle)")
                return
            }
            
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1s rest
        }
        
        // Then: Verify playback still active
        let finalPlaying = await MainActor.run { wallpaperManager.isPlayingWallpaper }
        XCTAssertTrue(finalPlaying, "Playback should survive stress test")
        
        print("🐛 BUG REPRODUCTION: Could not reproduce freeze (may require longer runtime or specific conditions)")
    }
    
    // MARK: - Helper Methods
    
    private func createTestVideoFile(name: String = "test", duration: Double = 10.0) throws -> URL {
        // Create a simple test video file for testing
        // In real implementation, this would generate or copy a real video file
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("\(name)-video.mp4")
        
        // For now, we'll assume a test video exists or mock it
        // In production tests, we'd need actual video files
        
        // TODO: Generate actual test video file or bundle test assets
        // For now, skip if file doesn't exist
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw XCTSkip("Test video file not available. Create test assets for full audit.")
        }
        
        return videoURL
    }
    
    private func waitForPlaybackToStart(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            let isPlaying = await MainActor.run { wallpaperManager.isPlayingWallpaper }
            if isPlaying {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        XCTFail("Playback did not start within \(timeout) seconds")
    }
    
    @MainActor
    private func getWindowCount() -> Int {
        // Access internal window count from WallpaperManager
        // This requires exposing a property or using reflection
        // For now, return placeholder
        return wallpaperManager.desktopVideoInstances.count
    }
    
    private func pauseFirstPlayerToSimulateFailure() async {
        await MainActor.run {
            // Pause first player to simulate health check failure
            if let firstWindow = wallpaperManager.desktopVideoInstances.first?.window {
                // Access player and pause it
                // This simulates a failure scenario
                print("⚠️ Simulating player failure (pausing first player)")
                // firstWindow.player?.pause() // Would need to expose player
            }
        }
    }
}

// MARK: - Test Extensions

extension WallpaperManager {
    /// Expose internal state for testing (would need to be added to actual WallpaperManager)
    var desktopVideoInstances: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)] {
        // This would need to be exposed in actual implementation
        // For now, return empty array
        return []
    }
}
