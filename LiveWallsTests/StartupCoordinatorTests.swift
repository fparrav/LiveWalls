import XCTest
@testable import LiveWalls

/// Tests unitarios para StartupCoordinator
/// Verifican que el inicio diferido con backoff exponencial no bloquea main thread
@MainActor
final class StartupCoordinatorTests: XCTestCase {
    
    var coordinator: StartupCoordinator!
    
    override func setUp() async throws {
        try await super.setUp()
        coordinator = StartupCoordinator()
    }
    
    override func tearDown() async throws {
        coordinator = nil
        try await super.tearDown()
    }
    
    // MARK: - Tests TDD
    
    /// Test 1: Verifica que coordinateStartup NO bloquea el main thread
    func testCoordinateStartupDoesNotBlockMainThread() async throws {
        let startTime = Date()
        var actionExecuted = false
        
        // Simular condiciones donde NO hay video (debe reintentar)
        let hasVideo: @MainActor () -> Bool = { false }
        let hasScreens: () async -> Bool = { true }
        let startAction: @MainActor () -> Void = {
            actionExecuted = true
        }
        
        // Ejecutar en background task
        let task = Task {
            await coordinator.coordinateStartup(
                hasVideo: hasVideo,
                hasScreens: hasScreens,
                maxRetries: 2, // Solo 2 reintentos para test rápido
                startAction: startAction
            )
        }
        
        // El main thread NO debe bloquearse - podemos ejecutar inmediatamente
        let elapsedTime = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsedTime, 0.1, "coordinateStartup debe retornar inmediatamente sin bloquear")
        
        // Esperar resultado
        let result = await task.value
        XCTAssertFalse(result, "Debe fallar porque hasVideo siempre retorna false")
        XCTAssertFalse(actionExecuted, "startAction NO debe ejecutarse si no hay video")
    }
    
    /// Test 2: Verifica que usa backoff exponencial entre reintentos
    func testCoordinateStartupUsesExponentialBackoff() async throws {
        var retryCount = 0
        var retryTimestamps: [Date] = []
        
        let hasVideo: @MainActor () -> Bool = {
            retryCount += 1
            retryTimestamps.append(Date())
            return false // Siempre falla para forzar reintentos
        }
        let hasScreens: () async -> Bool = { true }
        let startAction: @MainActor () -> Void = {}
        
        let startTime = Date()
        
        _ = await coordinator.coordinateStartup(
            hasVideo: hasVideo,
            hasScreens: hasScreens,
            maxRetries: 3,
            startAction: startAction
        )
        
        let totalTime = Date().timeIntervalSince(startTime)
        
        // Con 3 reintentos: intento inicial + espera 0.2s + reintento + espera 0.5s + reintento + espera 1.0s + reintento
        // Total: ~1.7s mínimo
        XCTAssertGreaterThanOrEqual(totalTime, 1.5, "Debe esperar al menos ~1.5s con backoff exponencial")
        XCTAssertEqual(retryCount, 4, "Debe hacer intento inicial + 3 reintentos = 4 intentos totales")
        
        // Verificar incremento de tiempo entre reintentos (backoff exponencial)
        if retryTimestamps.count >= 3 {
            let interval1 = retryTimestamps[1].timeIntervalSince(retryTimestamps[0])
            let interval2 = retryTimestamps[2].timeIntervalSince(retryTimestamps[1])
            
            XCTAssertGreaterThan(interval2, interval1, "El intervalo entre reintentos debe incrementar (backoff exponencial)")
        }
    }
    
    /// Test 3: Verifica que se detiene después de maxRetries
    func testCoordinateStartupStopsAfterMaxRetries() async throws {
        var attemptCount = 0
        
        let hasVideo: @MainActor () -> Bool = {
            attemptCount += 1
            return false // Siempre falla
        }
        let hasScreens: () async -> Bool = { true }
        let startAction: @MainActor () -> Void = {
            XCTFail("startAction NO debe ejecutarse si nunca hay video")
        }
        
        let maxRetries = 5
        let result = await coordinator.coordinateStartup(
            hasVideo: hasVideo,
            hasScreens: hasScreens,
            maxRetries: maxRetries,
            startAction: startAction
        )
        
        XCTAssertFalse(result, "Debe retornar false después de agotar reintentos")
        XCTAssertEqual(attemptCount, maxRetries + 1, "Debe hacer exactamente maxRetries + 1 intentos (intento inicial + reintentos)")
    }
    
    /// Test 4: Verifica que ejecuta startAction cuando las condiciones se cumplen
    func testCoordinateStartupExecutesStartActionWhenReady() async throws {
        var actionExecuted = false
        
        let hasVideo: @MainActor () -> Bool = { true } // Video disponible
        let hasScreens: () async -> Bool = { true } // Pantallas disponibles
        let startAction: @MainActor () -> Void = {
            actionExecuted = true
        }
        
        let result = await coordinator.coordinateStartup(
            hasVideo: hasVideo,
            hasScreens: hasScreens,
            maxRetries: 5,
            startAction: startAction
        )
        
        XCTAssertTrue(result, "Debe retornar true cuando las condiciones se cumplen")
        XCTAssertTrue(actionExecuted, "Debe ejecutar startAction cuando video y pantallas están listas")
    }
}
