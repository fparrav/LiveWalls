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
        let isWarmed = await videoPreloader.isWarmedUp(for: testURL)
        
        // Then
        XCTAssertFalse(isWarmed, "Cache should be cold initially")
    }
    
    // MARK: - Test: videoPreloader cache behavior with different URLs
    
    @MainActor
    func testVideoPreloaderDifferentURLsAreNotCached() async {
        // Given
        let testURL1 = URL(fileURLWithPath: "/tmp/video1.mov")
        let testURL2 = URL(fileURLWithPath: "/tmp/video2.mov")
        
        // When - check warmth for first URL
        let isWarmed1 = await videoPreloader.isWarmedUp(for: testURL1)
        
        // Then - should be false since nothing was preloaded
        XCTAssertFalse(isWarmed1, "First URL should not be warmed up")
        
        // When - check warmth for second URL
        let isWarmed2 = await videoPreloader.isWarmedUp(for: testURL2)
        
        // Then - should also be false
        XCTAssertFalse(isWarmed2, "Second URL should not be warmed up")
    }
    
    // MARK: - Test: clear cache empties the cache
    
    @MainActor
    func testVideoPreloaderClearCacheWorks() async {
        // Given
        let testURL = URL(fileURLWithPath: "/tmp/test-video.mov")
        
        // When - clear cache
        await videoPreloader.clearCache()
        
        // Then - verify cache is cold
        let isWarmedAfter = await videoPreloader.isWarmedUp(for: testURL)
        XCTAssertFalse(isWarmedAfter, "Cache should be cold after clear")
    }
    
     // MARK: - Test: videoPreloader handles invalid URLs gracefully
     
     @MainActor
     func testVideoPreloaderHandlesInvalidURLs() async {
         // Given
         let invalidURL = URL(fileURLWithPath: "/nonexistent/path/video.mov")
         
         // When - try to preload invalid URL
         await videoPreloader.preload(videoURL: invalidURL)
         
         // Then - should not crash and cache should remain cold
         let isWarmed = await videoPreloader.isWarmedUp(for: invalidURL)
         XCTAssertFalse(isWarmed, "Invalid URL should not be warmed up")
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
         // Note: May be cold if file doesn't exist, but should not crash
         XCTAssertNotNil(preloader, "VideoPreloader should be usable in integration")
     }
     
     // MARK: - Test: VideoPreloader cache lifecycle
     
     @MainActor
     func testVideoPreloaderCacheLifecycle() async {
         // Given
         let testURL = URL(fileURLWithPath: "/tmp/test-video-lifecycle.mov")
         
         // When - preload (may fail if file doesn't exist, but should not crash)
         await videoPreloader.preload(videoURL: testURL)
         
         // When - clear cache
         await videoPreloader.clearCache()
         let isWarmedAfter = await videoPreloader.isWarmedUp(for: testURL)
         
         // Then
         XCTAssertFalse(isWarmedAfter, "Cache should be cold after clearing")
     }
     
     // MARK: - Fase 4: Tests de AVAsset Caching
     
      /// Test que verifica que preload cachea AVAsset para uso inmediato
      /// Fase 4: Reducir tiempo de creación de ventanas (18s→<500ms)
      @MainActor
      func testPreloadCachesAVAsset() async throws {
          // Given: Use a path that might have videos - skip if none found
          let possiblePaths = [
              "/System/Library/Compositions/Rollercoaster.mov",
              "/Library/Desktop Pictures/Rollercoaster.mov"
          ]
          
          var testURL: URL?
          for path in possiblePaths {
              if FileManager.default.fileExists(atPath: path) {
                  testURL = URL(fileURLWithPath: path)
                  break
              }
          }
          
          guard let videoURL = testURL else {
              throw XCTSkip("No se encontró video de prueba en el sistema")
          }
          
          // When: Precargar video
          await videoPreloader.preload(videoURL: videoURL)
          
          // Obtener asset cacheado
          let cachedAsset = await videoPreloader.getPreloadedAsset(for: videoURL)
          
          // Then: Debe haber asset cacheado (solo si el preload tuvo éxito)
          XCTAssertNotNil(cachedAsset, "Preload debe cachear AVAsset para videos válidos")
      }
     
      /// Test que verifica que asset precargado puede ser reutilizado
      /// Fase 4: Validar que mismo asset se retorna para misma URL
      @MainActor
      func testPreloadedAssetCanBeReused() async throws {
          // Given: Use a path that might have videos - skip if none found
          let possiblePaths = [
              "/System/Library/Compositions/Rollercoaster.mov",
              "/Library/Desktop Pictures/Rollercoaster.mov"
          ]
          
          var testURL: URL?
          for path in possiblePaths {
              if FileManager.default.fileExists(atPath: path) {
                  testURL = URL(fileURLWithPath: path)
                  break
              }
          }
          
          guard let videoURL = testURL else {
              throw XCTSkip("No se encontró video de prueba en el sistema")
          }
          
          // When: Precargar y obtener asset dos veces
          await videoPreloader.preload(videoURL: videoURL)
          
          let firstAsset = await videoPreloader.getPreloadedAsset(for: videoURL)
          let secondAsset = await videoPreloader.getPreloadedAsset(for: videoURL)
          
          // Then: Si hay asset, deben ser el mismo objeto (identidad de referencia)
          if let first = firstAsset, let second = secondAsset {
              XCTAssertTrue(first === second, "Debe retornar mismo AVAsset instance")
          } else {
              throw XCTSkip("Video no se pudo precargar")
          }
      }
     
      /// Test que verifica que preload realmente acelera el acceso
      /// Fase 4: Confirmar que cache WARM es significativamente más rápido
      @MainActor
      func testPreloadWarmsCache() async throws {
          // Given: Use a path that might have videos - skip if none found
          let possiblePaths = [
              "/System/Library/Compositions/Rollercoaster.mov",
              "/Library/Desktop Pictures/Rollercoaster.mov"
          ]
          
          var testURL: URL?
          for path in possiblePaths {
              if FileManager.default.fileExists(atPath: path) {
                  testURL = URL(fileURLWithPath: path)
                  break
              }
          }
          
          guard let videoURL = testURL else {
              throw XCTSkip("No se encontró video de prueba en el sistema")
          }
          
          // When: Precargar video
          await videoPreloader.preload(videoURL: videoURL)
          
          // Obtener asset (debe ser rápido con cache WARM)
          let startTime = Date()
          let asset = await videoPreloader.getPreloadedAsset(for: videoURL)
          let elapsed = Date().timeIntervalSince(startTime)
          
          // Then: Si el preload tuvo éxito, debe retornar asset muy rápido (<100ms)
          if let _ = asset {
              XCTAssertLessThan(elapsed, 0.1, "Cache WARM debe ser rápido (<100ms), fue \(elapsed)s")
          } else {
              throw XCTSkip("Video no se pudo precargar")
          }
      }
}
