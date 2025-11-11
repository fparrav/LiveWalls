
import XCTest
@testable import LiveWalls

final class ScheduledHealthCheckManagerTests: XCTestCase {
    
    var manager: ScheduledHealthCheckManager!
    var mainThreadCallCount: Int = 0
    var backgroundThreadCallCount: Int = 0
    let mainThread = Thread.main
    
    override func setUp() {
        super.setUp()
        manager = ScheduledHealthCheckManager()
        mainThreadCallCount = 0
        backgroundThreadCallCount = 0
    }
    
    override func tearDown() {
        super.tearDown()
        // Cancelar cualquier tarea pendiente
        Task {
            await manager.cancelHealthChecks()
        }
    }
    
    // MARK: - Test 1: Verificar que los chequeos de salud no bloquean el main thread
    
    /// Verifica que los chequeos de salud se ejecuten en background y no bloqueen el main thread
    func testScheduledHealthChecksRunInBackground() async {
        let expectation = XCTestExpectation(description: "Health checks completed on background thread")
        expectation.expectedFulfillmentCount = 2 // Esperamos 2 ejecuciones (1s y 3s)
        
        let intervals: [TimeInterval] = [0.1, 0.2] // Usar intervalos cortos para tests
        
        let action: @Sendable () async -> Void = { [weak self] in
            // Registrar en qué thread se ejecuta
            if Thread.isMainThread {
                self?.mainThreadCallCount += 1
            } else {
                self?.backgroundThreadCallCount += 1
            }
            expectation.fulfill()
        }
        
        // Lanzar chequeos
        await manager.scheduleHealthChecks(action: action, intervals: intervals)
        
        // Esperar con timeout
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Verificaciones:
        // 1. No se debe ejecutar en main thread
        XCTAssertEqual(mainThreadCallCount, 0, "Health checks debe ejecutarse en background, no en main thread")
        
        // 2. Se debe ejecutar en background thread
        XCTAssertTrue(backgroundThreadCallCount > 0, "Health checks debe ejecutarse en al menos 1 background thread")
        
        // 3. Main thread debe permanecer responsivo (esto se verifica si el test no se cuelga)
    }
    
    // MARK: - Test 2: Verificar que no se satura el main thread
    
    /// Verifica que el ScheduledHealthCheckManager no sature el main thread con múltiples async calls
    func testHealthCheckManagerDoesNotSaturateMainThread() async {
        let expectation = XCTestExpectation(description: "No main thread saturation detected")
        expectation.expectedFulfillmentCount = 1
        
        let intervals: [TimeInterval] = [0.1] // Un único intervalo para simplificar
        
        let action: @Sendable () async -> Void = { [weak self] in
            
            // Simular algo de trabajo
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            
            if Thread.isMainThread {
                self?.mainThreadCallCount += 1
            }
            expectation.fulfill()
        }
        
        // Medir tiempo en main thread antes
        let startTime = Date()
        
        // Lanzar chequeos programados
        await manager.scheduleHealthChecks(action: action, intervals: intervals)
        
        // El main thread debe ser responsivo (no bloqueado)
        // Hacemos una operación rápida en main thread y verificamos que sea rápida
        await MainActor.run {
            let elapsed = Date().timeIntervalSince(startTime)
            // Si el main thread fue bloqueado por más de 500ms, esto fallará
            XCTAssertLessThan(elapsed, 0.5, "Main thread fue bloqueado durante demasiado tiempo")
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Main thread no debe tener carga de los chequeos
        XCTAssertEqual(mainThreadCallCount, 0, "Health checks no debe ejecutar en main thread")
    }
    
    // MARK: - Test 3: Verificar que los chequeos pueden ser cancelados
    
    /// Verifica que los chequeos programados pueden ser cancelados correctamente
    func testHealthChecksCanBeCancelled() async {
        let expectation = XCTestExpectation(description: "Health checks cancelled")
        
        // Actor para encapsular el contador mutable y evitar warning de captura mutable en closure @Sendable
        actor ExecutionCounter {
            private var count = 0
            func increment() {
                count += 1
            }
            func getCount() -> Int {
                count
            }
        }
        
        let intervals: [TimeInterval] = [0.1, 0.3, 0.5]
        let counter = ExecutionCounter()
        
        let action: @Sendable () async -> Void = {
            await counter.increment()
        }
        
        // Lanzar chequeos
        await manager.scheduleHealthChecks(action: action, intervals: intervals)
        
        // Esperar un poco (menos que el primer intervalo)
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Cancelar los chequeos
        await manager.cancelHealthChecks()
        
        // Esperar para verificar que no hay más ejecuciones
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Verificar que se ejecutó al menos una vez (probablemente solo 1)
        // pero no todas las programadas
        let executionCount = await counter.getCount()
        XCTAssertLessThan(executionCount, 3, "Cancelación debe prevenir ejecuciones futuras")
        
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
