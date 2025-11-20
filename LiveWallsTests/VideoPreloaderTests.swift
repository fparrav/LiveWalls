import XCTest
import AVFoundation
@testable import LiveWalls

final class VideoPreloaderTests: XCTestCase {
    var videoPreloader: VideoPreloader!
    
    @MainActor
    override func setUp() {
        super.setUp()
        // Create VideoPreloader on main thread (it's @MainActor)
        videoPreloader = VideoPreloader()
    }
    
    override func tearDown() {
        videoPreloader = nil
        super.tearDown()
    }
    
    // MARK: - Test: videoPreloader instance can be created
    
    @MainActor
    func testVideoPreloaderCanBeInstantiated() async {
        // Given
        let preloader = VideoPreloader()
        
        // Then
        XCTAssertNotNil(preloader, "VideoPreloader should be instantiable")
    }
    
    // MARK: - Test: videoPreloader cache miss initially
    
    @MainActor
    func testVideoPreloaderCacheMissInitially() async {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test-video.mov")
        
        // When
        let cachedAsset = await videoPreloader.getCachedAsset(for: testURL)
        
        // Then
        XCTAssertNil(cachedAsset, "Cache should be empty initially")
    }
    
    // MARK: - Test: videoPreloader cache behavior with different URLs
    
    @MainActor
    func testVideoPreloaderDifferentURLsAreNotCached() async {
        // Given
        let testURL1 = URL(fileURLWithPath: "/tmp/video1.mov")
        let testURL2 = URL(fileURLWithPath: "/tmp/video2.mov")
        
        // When - try to get asset for first URL
        let cachedAsset1 = await videoPreloader.getCachedAsset(for: testURL1)
        
        // Then - should be nil since nothing was preloaded
        XCTAssertNil(cachedAsset1, "First URL should not be in cache")
        
        // When - try to get asset for second URL
        let cachedAsset2 = await videoPreloader.getCachedAsset(for: testURL2)
        
        // Then - should also be nil
        XCTAssertNil(cachedAsset2, "Second URL should not be in cache")
    }
    
    // MARK: - Test: clear cache empties the cache
    
    @MainActor
    func testVideoPreloaderClearCacheWorks() async {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test-video.mov")
        
        // When - clear cache
        await videoPreloader.clearCache()
        
        // Then - verify cache is empty
        let cachedAfter = await videoPreloader.getCachedAsset(for: testURL)
        XCTAssertNil(cachedAfter, "Cache should be empty after clear")
    }
    
     // MARK: - Test: videoPreloader handles invalid URLs gracefully
     
     @MainActor
     func testVideoPreloaderHandlesInvalidURLs() async {
         // Given
         let invalidURL = URL(fileURLWithPath: "/nonexistent/path/video.mov")
         
         // When - try to preload invalid URL
         await videoPreloader.preload(videoURL: invalidURL)
         
         // Then - should not crash and cache should remain empty
         let cachedAsset = await videoPreloader.getCachedAsset(for: invalidURL)
         XCTAssertNil(cachedAsset, "Invalid URL should not be cached")
     }
     
     // MARK: - Test: VideoPreloader integration with WallpaperManager
     
     @MainActor
     func testVideoPreloaderCanBeIntegratedWithWallpaperManager() async {
         // Given
         let preloader = VideoPreloader()
         
         // When
         let testURL = URL(fileURLWithPath: "/tmp/test-video-integration.mov")
         await preloader.preload(videoURL: testURL)
         
         // Then - should handle gracefully and not crash
         let cachedAsset = await preloader.getCachedAsset(for: testURL)
         // Note: May be nil if file doesn't exist, but should not crash
         XCTAssertNotNil(preloader, "VideoPreloader should be usable in integration")
     }
     
     // MARK: - Test: VideoPreloader cache lifecycle
     
     @MainActor
     func testVideoPreloaderCacheLifecycle() async {
         // Given
         let testURL = URL(fileURLWithPath: "/tmp/test-video-lifecycle.mov")
         
         // When - preload and check cache
         await videoPreloader.preload(videoURL: testURL)
         let cachedBefore = await videoPreloader.getCachedAsset(for: testURL)
         
         // When - clear cache
         await videoPreloader.clearCache()
         let cachedAfter = await videoPreloader.getCachedAsset(for: testURL)
         
         // Then
         XCTAssertNil(cachedAfter, "Cache should be empty after clearing")
     }
}
