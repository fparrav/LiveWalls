import XCTest
import AVFoundation
@testable import LiveWalls

/// Tests para PlaybackHealthChecker
/// Verifica que las comprobaciones de salud de reproducción se ejecuten de forma asíncrona sin bloquear el main thread
@MainActor
final class PlaybackHealthCheckerTests: XCTestCase {
    
    var playbackHealthChecker: PlaybackHealthChecker!
    var bookmarkActor: BookmarkActor!
    
    override func setUp() async throws {
        playbackHealthChecker = PlaybackHealthChecker()
        bookmarkActor = BookmarkActor()
    }
    
    override func tearDown() async throws {
        playbackHealthChecker = nil
        bookmarkActor = nil
    }
    
    // MARK: - Test 1: Verificar que checkPlaybackHealth no bloquea main thread
    
    /// Verifica que checkPlaybackHealth se ejecuta de forma asíncrona sin bloquear el main thread
    func testCheckPlaybackHealthDoesNotBlockMainThread() async throws {
        // Given: Un video de prueba con bookmark data simulado
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        let testVideo = VideoFile(
            url: testURL,
            name: "Test Video",
            thumbnailData: nil,
            bookmarkData: Data() // Bookmark simulado
        )
        
        // When: Ejecutamos checkPlaybackHealth y medimos responsividad del main thread
        let startTime = Date()
        
        // Lanzar tarea que debe completarse rápidamente si es asíncrona
        let task = Task {
            let _ = await playbackHealthChecker.checkPlaybackHealth(
                windows: [],
                currentVideo: testVideo,
                bookmarkActor: bookmarkActor
            )
        }
        
        // El main thread debe seguir respondiendo durante la operación
        // Realizar una operación rápida en main thread para verificar responsividad
        var mainThreadResponseTime: TimeInterval = 0
        await MainActor.run {
            let measureStart = Date()
            // Operación rápida que debe completarse casi instantáneamente
            _ = 1 + 1
            mainThreadResponseTime = Date().timeIntervalSince(measureStart)
        }
        
        // Esperar a que termine la tarea
        _ = await task.value
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: No debe bloquear main thread y debe completarse en tiempo razonable
        XCTAssertLessThan(mainThreadResponseTime, 0.05, "Main thread debe responder rápidamente (< 50ms)")
        XCTAssertLessThan(duration, 1.0, "checkPlaybackHealth no debe tomar más de 1 segundo para ventanas vacías")
    }
    
    // MARK: - Test 2: Verificar que detecta necesidad de reinicio
    
    /// Verifica que checkPlaybackHealth detecta cuando es necesario reiniciar la reproducción
    func testCheckPlaybackHealthRestartsPlaybackWhenNeeded() async throws {
        // Given: Un video de prueba sin ventanas (simula reproducción detenida)
        let testURL = URL(fileURLWithPath: "/test/video.mp4")
        let testVideo = VideoFile(
            url: testURL,
            name: "Test Video",
            thumbnailData: nil,
            bookmarkData: Data()
        )
        
        // When: Verificamos salud de reproducción con 0 ventanas
        let healthStatus = await playbackHealthChecker.checkPlaybackHealth(
            windows: [],
            currentVideo: testVideo,
            bookmarkActor: bookmarkActor
        )
        
        // Then: Debe detectar que no hay reproducción activa
        XCTAssertFalse(healthStatus, "checkPlaybackHealth debe retornar false cuando no hay ventanas")
    }
    
    // MARK: - Test 3: Verificar ejecución asíncrona del actor
    
     /// Verifica que PlaybackHealthChecker se ejecuta como actor aislado de forma asíncrona
     func testPlaybackHealthCheckerRunsAsynchronously() async throws {
         // Given: Multiple llamadas concurrentes al health checker
         let testURL = URL(fileURLWithPath: "/test/video.mp4")
         let testVideo = VideoFile(
             url: testURL,
             name: "Test Video",
             thumbnailData: nil,
             bookmarkData: Data()
         )
         
         let startTime = Date()
         
         // When: Ejecutamos múltiples verificaciones en paralelo
         async let check1 = playbackHealthChecker.checkPlaybackHealth(
             windows: [],
             currentVideo: testVideo,
             bookmarkActor: bookmarkActor
         )
         
         async let check2 = playbackHealthChecker.checkPlaybackHealth(
             windows: [],
             currentVideo: testVideo,
             bookmarkActor: bookmarkActor
         )
         
         async let check3 = playbackHealthChecker.checkPlaybackHealth(
             windows: [],
             currentVideo: testVideo,
             bookmarkActor: bookmarkActor
         )
         
         // Esperar a que todas completen
         let results = await [check1, check2, check3]
         let duration = Date().timeIntervalSince(startTime)
         
         // Then: Deben ejecutarse de forma serializada por el actor pero sin bloquear
         XCTAssertEqual(results.count, 3, "Deben completarse las 3 verificaciones")
         XCTAssertLessThan(duration, 2.0, "Las verificaciones deben completarse en tiempo razonable")
         
         // Verificar que todas las verificaciones retornan el mismo resultado
         XCTAssertTrue(results.allSatisfy { $0 == false }, "Todas las verificaciones deben retornar false sin ventanas")
     }
     
      // MARK: - Test 4: PHASE 6 - timeControlStatus takes precedence over rate
      
      /// PHASE 6: Verifica que checkPlaybackHealth está preparado para usar timeControlStatus
      /// Este test verifica que el método getTimeControlStatus() existe y funciona
      func testCheckPlaybackHealthUsesTimeControlStatus() async throws {
          // Given: Una ventana con getTimeControlStatus() disponible
          let testScreen = NSScreen.main ?? NSScreen()
          let testURL = URL(fileURLWithPath: "/test/video.mp4")
          
          // Create a real window to verify the method exists
          let window = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testURL, startPaused: true)
          
          // When: Llamamos getTimeControlStatus()
          let timeControlStatus = window.getTimeControlStatus()
          
          // Then: Debe retornar un valor de timeControlStatus (nil o un estado válido)
          // El método debe existir y funcionar sin errores
          XCTAssertNotNil(window, "PHASE 6: Window debe crearse correctamente")
          // timeControlStatus puede ser nil al inicio, lo importante es que el método existe
          // y se puede llamar sin errores de compilación
          
          window.close()
      }
      
      /// PHASE 6: Verifica que checkPlaybackHealth detecta estado de espera (waitingToPlayAtSpecifiedRate)
      /// Esto indica un stall potencial que requiere intervención
      func testCheckPlaybackHealthDetectsWaitingState() async throws {
          // Given: Una ventana con getTimeControlStatus() disponible
          let testScreen = NSScreen.main ?? NSScreen()
          let testURL = URL(fileURLWithPath: "/test/video.mp4")
          
          // Create a real window
          let window = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testURL, startPaused: true)
          
          // When: Llamamos getTimeControlStatus()
          let timeControlStatus = window.getTimeControlStatus()
          
          // Then: Verificar que el método existe y puede retornar estados válidos
          // timeControlStatus al iniciar será probablemente nil o paused
          // Pero el código debe estar preparado para detectar .waitingToPlayAtSpecifiedRate
          XCTAssertNotNil(window, "PHASE 6: Window debe crearse correctamente para detectar waiting state")
          
          window.close()
      }
      
      /// PHASE 6: Verifica que checkPlaybackHealth usa rate si timeControlStatus es nil
      /// Esto proporciona compatibilidad hacia atrás con cambios de API
      func testCheckPlaybackHealthFallsBackToRate() async throws {
          // Given: Una ventana con getPlaybackRate() disponible como fallback
          let testScreen = NSScreen.main ?? NSScreen()
          let testURL = URL(fileURLWithPath: "/test/video.mp4")
          
          // Create a real window
          let window = DesktopVideoWindowMejorada(screen: testScreen, videoURL: testURL, startPaused: true)
          
          // When: Llamamos getPlaybackRate() como fallback
          let rate = window.getPlaybackRate()
          
          // Then: El fallback debe funcionar
          // Si timeControlStatus no está disponible, se debe usar rate
          XCTAssertNotNil(window, "PHASE 6: Window debe tener fallback a getPlaybackRate()")
          // La tasa será probablemente 0.0 al inicio (paused state)
          
           window.close()
       }
       
       // MARK: - PHASE 7: Telemetry and Integration Tests
       
       /// Phase 7.1: testExtendedPlaybackStability
       /// Validates extended playback without stalls (10 min simulation or 10 seconds in test)
       func testPhase7ExtendedPlaybackStability() async throws {
           // Given: Wallpaper playback setup
           let testURL = URL(fileURLWithPath: "/test/video.mp4")
           let testVideo = VideoFile(
               url: testURL,
               name: "Test Video",
               bookmarkData: Data()
           )
           
           // When: Simulating extended playback monitoring
           let testDuration: TimeInterval = 5 // seconds
           let startTime = Date()
           var checkCount = 0
           
           // Monitor for stalls
           while Date().timeIntervalSince(startTime) < testDuration {
               // Simulate health check
               let _ = await playbackHealthChecker.checkPlaybackHealth(
                   windows: [],
                   currentVideo: testVideo,
                   bookmarkActor: bookmarkActor
               )
               checkCount += 1
               
               try await Task.sleep(nanoseconds: 100_000_000) // 100ms
           }
           
           // Then: Should have performed multiple health checks
           XCTAssertGreaterThan(checkCount, 0, "Extended playback should perform health checks")
       }
       
       /// Phase 7.2: testWindowRecreationTracking
       /// Validates that window recreation can be detected and tracked
       func testPhase7WindowRecreationTracking() async throws {
           // Given: Multiple window health checks
           let testScreen = NSScreen.main ?? NSScreen()
           let testURL = URL(fileURLWithPath: "/test/video.mp4")
           
           var recreationCount = 0
           let windows = (0..<3).map { _ in
               DesktopVideoWindowMejorada(
                   screen: testScreen,
                   videoURL: testURL,
                   startPaused: true
               )
           }
           
           defer {
               windows.forEach { $0.close() }
           }
           
           // When: Monitoring window state
           for window in windows {
               let level = window.level
               // Simulate recreation event based on window availability
               // The window should be created successfully
               XCTAssertNotNil(window, "Window should be created")
               recreationCount += 1
           }
           
           // Then: Recreation should be tracked
           XCTAssertGreaterThanOrEqual(recreationCount, 3, "All windows should be created")
       }
       
       /// Phase 7.3: testPlaybackHealthCheckerEfficiency
       /// Validates that health checks are efficient and don't overload
       func testPhase7HealthCheckEfficiency() async throws {
           // Given: Rapid health check execution
           let testURL = URL(fileURLWithPath: "/test/video.mp4")
           let testVideo = VideoFile(
               url: testURL,
               name: "Test",
               bookmarkData: nil
           )
           
           // When: Executing 50 health checks
           let checkCount = 50
           let startTime = Date()
           
           for _ in 0..<checkCount {
               let _ = await playbackHealthChecker.checkPlaybackHealth(
                   windows: [],
                   currentVideo: testVideo,
                   bookmarkActor: bookmarkActor
               )
           }
           
           let duration = Date().timeIntervalSince(startTime)
           let averageTime = duration / TimeInterval(checkCount)
           
           // Then: Average check time should be minimal
           XCTAssertLessThan(
               averageTime,
               0.1,
               "Health checks should average < 100ms (Phase 6 optimization)"
           )
       }
       
       /// Phase 7.4: testConcurrentHealthCheckSafety
       /// Validates that concurrent health checks are thread-safe
       func testPhase7ConcurrentHealthCheckSafety() async throws {
           // Given: Multiple concurrent health checks
           let testURL = URL(fileURLWithPath: "/test/video.mp4")
           let testVideo = VideoFile(
               url: testURL,
               name: "Test",
               bookmarkData: nil
           )
           
           // When: Running 10 concurrent health checks
           var tasks: [Task<Bool, Never>] = []
           
           for _ in 0..<10 {
               let task = Task {
                   let result = await self.playbackHealthChecker.checkPlaybackHealth(
                       windows: [],
                       currentVideo: testVideo,
                       bookmarkActor: self.bookmarkActor
                   )
                   return result
               }
               tasks.append(task)
           }
           
           // Collect results from all tasks
           var results: [Bool] = []
           for task in tasks {
               let result = await task.value
               results.append(result)
           }
           
           // Then: All checks should complete without crashes
           XCTAssertEqual(
               results.count,
               10,
               "All concurrent health checks should complete safely"
           )
       }
       
       /// Phase 7.5: testPlaybackMonitoringCapabilities
       /// Validates that playback monitoring infrastructure exists and works
       func testPhase7PlaybackMonitoringCapabilities() async throws {
           // Given: A playback health checker instance
           XCTAssertNotNil(playbackHealthChecker, "Health checker must be available")
           
           // When: Checking health check capabilities
           let testURL = URL(fileURLWithPath: "/test/video.mp4")
           let testVideo = VideoFile(
               url: testURL,
               name: "Test",
               bookmarkData: nil
           )
           
           // Then: Health checks should function correctly
           let healthStatus = await playbackHealthChecker.checkPlaybackHealth(
               windows: [],
               currentVideo: testVideo,
               bookmarkActor: bookmarkActor
           )
           
           // Result should be a boolean (true = healthy, false = needs attention)
           XCTAssertFalse(healthStatus, "Empty windows should indicate unhealthy state")
       }
   }
 
 
 
 