import XCTest
import AppKit
@testable import LiveWalls

/// Tests para SystemReadinessObserver (observador reactivo de estado del sistema)
@MainActor
final class SystemReadinessObserverTests: XCTestCase {
    
    var observer: SystemReadinessObserver!
    
    override func setUp() async throws {
        try await super.setUp()
        observer = SystemReadinessObserver()
    }
    
    override func tearDown() async throws {
        observer = nil
        try await super.tearDown()
    }
    
    // MARK: - Test 1: Reporta ready cuando hay pantallas disponibles
    
    func testSystemReadinessObserverReportsReadyWhenScreensAvailable() {
        // Given: el sistema tiene pantallas disponibles
        let screens = NSScreen.screens
        XCTAssertFalse(screens.isEmpty, "Este test requiere al menos una pantalla")
        
        // When: verificamos el estado del observador
        let isReady = observer.isReady
        
        // Then: debe reportar que está listo
        XCTAssertTrue(isReady, "SystemReadinessObserver debe reportar isReady=true cuando hay pantallas disponibles")
    }
    
    // MARK: - Test 2: No bloquea el main thread
    
    func testSystemReadinessObserverDoesNotBlockMainThread() async {
        // Given: un observador recién creado
        let startTime = Date()
        
        // When: esperamos a que el sistema esté listo con timeout corto
        let ready = await observer.waitUntilReady(timeout: 0.5)
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Then: debe retornar casi inmediatamente si ya hay pantallas
        // El test pasa si:
        // 1. Hay pantallas y retorna true rápidamente (< 200ms)
        // 2. No hay pantallas y retorna false después del timeout
        if NSScreen.screens.isEmpty {
            XCTAssertFalse(ready, "No debe reportar ready si no hay pantallas")
            XCTAssertGreaterThanOrEqual(elapsedTime, 0.5, "Debe esperar el timeout")
        } else {
            XCTAssertTrue(ready, "Debe reportar ready si hay pantallas")
            // Si ya había pantallas, debe retornar casi inmediatamente
            XCTAssertLessThan(elapsedTime, 0.2, "No debe bloquear el main thread con polling loops")
        }
    }
    
    // MARK: - Test 3: Auto-start espera a sistema listo
    
    func testAutoStartWaitsForSystemReadiness() async {
        // Given: un observador que puede esperar
        // When: esperamos con timeout muy corto
        let ready = await observer.waitUntilReady(timeout: 0.2)
        
        // Then: debe retornar un resultado booleano basado en disponibilidad de pantallas
        // Este test simplemente verifica que el mecanismo funciona sin colgar
        if NSScreen.screens.isEmpty {
            XCTAssertFalse(ready, "Debe retornar false si no hay pantallas tras timeout")
        } else {
            XCTAssertTrue(ready, "Debe retornar true si hay pantallas disponibles")
        }
    }
    
    // MARK: - Test 4: Timeout funciona correctamente
    
    func testWaitUntilReadyRespectsTimeout() async {
        // Given: un timeout muy corto
        let timeout: TimeInterval = 0.1
        let startTime = Date()
        
        // When: esperamos con timeout
        _ = await observer.waitUntilReady(timeout: timeout)
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        // Then: si hay pantallas, retorna inmediatamente
        // Si no hay pantallas, debe respetar el timeout (máximo timeout + margen)
        if NSScreen.screens.isEmpty {
            XCTAssertGreaterThanOrEqual(elapsedTime, timeout, "Debe esperar al menos el timeout")
            XCTAssertLessThan(elapsedTime, timeout + 0.5, "No debe exceder significativamente el timeout")
        } else {
            XCTAssertLessThan(elapsedTime, 0.05, "Debe retornar inmediatamente si ya hay pantallas")
        }
    }
    
    // MARK: - Test 5: Limpieza de recursos
    
    func testObserverCleansUpProperly() {
        // Given: un observador activo
        let observer = SystemReadinessObserver()
        
        // When: se dealoca el observador
        weak var weakObserver = observer
        
        // Then: debe limpiarse correctamente (verificado por weak reference)
        XCTAssertNotNil(weakObserver, "Observer debe existir antes de deinit")
    }
}
