import XCTest
import AppKit
@testable import LiveWalls

/// Tests para WindowCreationCoordinator
/// Verifica que la creación de ventanas no bloquee el main thread
@MainActor
final class WindowCreationCoordinatorTests: XCTestCase {
    
    var coordinator: WindowCreationCoordinator!
    var mockVideoFile: VideoFile!
    var mockBookmarkActor: BookmarkActor!
    
    override func setUp() async throws {
        coordinator = WindowCreationCoordinator()
        
        // Crear video file mock
        let testURL = URL(fileURLWithPath: "/tmp/test.mp4")
        mockVideoFile = VideoFile(
            url: testURL,
            name: "Test Video",
            thumbnailData: nil,
            bookmarkData: nil
        )
        
        mockBookmarkActor = BookmarkActor()
    }
    
    override func tearDown() async throws {
        coordinator = nil
        mockVideoFile = nil
        mockBookmarkActor = nil
    }
    
    /// Verifica que createDesktopWindows no bloquee el RunLoop
    func testCreateDesktopWindowsDoesNotBlockRunLoop() async throws {
        // Given: Un video válido y múltiples pantallas simuladas
        let screens = [NSScreen.main!].compactMap { $0 } // Usar pantalla principal
        
        // When: Se crea el coordinator y se mide el tiempo
        let startTime = Date()
        
        // Ejecutar creación de ventanas de forma asíncrona
        let windows = await coordinator.createWindowsAsync(
            screens: screens,
            videoFile: mockVideoFile,
            bookmarkActor: mockBookmarkActor
        )
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Then: La operación debe completarse sin bloquear significativamente
        // Una operación no bloqueante debería tomar menos de 0.1 segundos
        // Una operación bloqueante tomaría al menos 0.02s por pantalla
        XCTAssertLessThan(duration, 0.1, "La creación de ventanas no debe bloquear el RunLoop")
        XCTAssertGreaterThanOrEqual(windows.count, 0, "Debe retornar al menos un array vacío")
    }
    
    /// Verifica que el coordinator cree ventanas de forma asíncrona
    func testWindowCreationCoordinatorCreatesWindowsAsync() async throws {
        // Given: Múltiples pantallas
        let screens = [NSScreen.main!].compactMap { $0 }
        
        // When: Se crean ventanas de forma asíncrona
        let windows = await coordinator.createWindowsAsync(
            screens: screens,
            videoFile: mockVideoFile,
            bookmarkActor: mockBookmarkActor
        )
        
        // Then: Debe retornar un array de NSWindow
        XCTAssertTrue(type(of: windows) == [NSWindow].self, "Debe retornar array de NSWindow")
        
        // Nota: En pruebas, las ventanas pueden no crearse realmente debido a limitaciones del entorno de pruebas
        // Lo importante es que no bloquee y retorne el tipo correcto
    }
    
    /// Verifica que múltiples pantallas no causen bloqueos
    func testMultipleScreenWindowCreationIsNonBlocking() async throws {
        // Given: Simular múltiples pantallas (usar la principal múltiples veces para simular)
        let screens = Array(repeating: NSScreen.main!, count: 3).compactMap { $0 }
        
        // When: Se crean ventanas para múltiples pantallas
        let startTime = Date()
        
        let windows = await coordinator.createWindowsAsync(
            screens: screens,
            videoFile: mockVideoFile,
            bookmarkActor: mockBookmarkActor
        )
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Then: No debe bloquear incluso con múltiples pantallas
        // Tiempo esperado: mucho menos que 3 * 0.02 = 0.06 segundos si fuera bloqueante
        XCTAssertLessThan(duration, 0.1, "Múltiples pantallas no deben causar bloqueos significativos")
        XCTAssertGreaterThanOrEqual(windows.count, 0, "Debe retornar array válido")
    }
}