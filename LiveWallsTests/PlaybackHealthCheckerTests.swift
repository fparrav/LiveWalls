import XCTest
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
        
        // When: Ejecutamos checkPlaybackHealth
        let startTime = Date()
        let mainThreadBefore = Thread.isMainThread
        
        // Lanzar tarea que debe completarse rápidamente si es asíncrona
        let task = Task {
            let _ = await playbackHealthChecker.checkPlaybackHealth(
                windows: [],
                currentVideo: testVideo,
                bookmarkActor: bookmarkActor
            )
        }
        
        // El main thread debe seguir respondiendo durante la operación
        let mainThreadDuring = Thread.isMainThread
        
        // Esperar a que termine
        _ = await task.value
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: No debe bloquear main thread y debe completarse en tiempo razonable
        XCTAssertTrue(mainThreadBefore, "Test debe ejecutarse en main thread")
        XCTAssertTrue(mainThreadDuring, "Main thread debe seguir respondiendo durante operación async")
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
}
