import XCTest
@testable import LiveWalls

/// Tests para ScheduledHealthCheckManager
/// Verifica que las comprobaciones programadas se ejecuten fuera del main thread,
/// no saturen el hilo principal y puedan cancelarse correctamente.
final class ScheduledHealthCheckManagerTests: XCTestCase {
    
    /// Actor simple para recolectar resultados de forma thread-safe
    actor Colector {
        private(set) var razones: [String] = []
        func agregar(_ razon: String) { razones.append(razon) }
        func conteo() -> Int { razones.count }
        func todas() -> [String] { razones }
    }
    
    // MARK: - Test 1: Ejecuta en background sin bloquear main
    func testScheduledHealthChecksRunInBackground() async throws {
        let manager = ScheduledHealthCheckManager()
        let colector = Colector()
        
        _ = await manager.scheduleChecks(
            delays: [0.2, 0.4],
            reasonPrefix: "test"
        ) { razon in
            await colector.agregar(razon)
        }
        
        // Medir una operación trivial en MainActor que debe ser rápida (< 50 ms)
        let t0 = Date()
        await MainActor.run { _ = 1 + 1 }
        let dt = Date().timeIntervalSince(t0)
        
        XCTAssertLessThan(dt, 0.05, "El main thread debe permanecer responsivo (<50ms)")
        
        // Esperar suficiente tiempo para que ambas comprobaciones se ejecuten
        try? await Task.sleep(for: .milliseconds(700))
        let count = await colector.conteo()
        XCTAssertGreaterThanOrEqual(count, 2, "Deben ejecutarse al menos 2 comprobaciones programadas")
    }
    
    // MARK: - Test 2: No satura el main thread con muchas tareas
    func testHealthCheckManagerDoesNotSaturateMainThread() async throws {
        let manager = ScheduledHealthCheckManager()
        let colector = Colector()
        
        // Programar muchas comprobaciones rápidas
        let delays = stride(from: 0.0, through: 0.5, by: 0.01).map { $0 }
        _ = await manager.scheduleChecks(
            delays: delays,
            reasonPrefix: "stress"
        ) { razon in
            await colector.agregar(razon)
        }
        
        // Tres operaciones en MainActor deben ser rápidas incluso bajo carga
        for _ in 0..<3 {
            let t0 = Date()
            await MainActor.run { _ = 2 + 2 }
            let dt = Date().timeIntervalSince(t0)
            XCTAssertLessThan(dt, 0.05, "MainActor debe responder <50ms incluso con carga programada")
        }
        
        // Esperar a que la mayor parte de tareas ejecuten
        try? await Task.sleep(for: .seconds(1))
        let count = await colector.conteo()
        XCTAssertGreaterThan(count, 10, "Se espera que múltiples comprobaciones se hayan ejecutado")
    }
    
    // MARK: - Test 3: Cancelación detiene ejecuciones posteriores
    func testHealthChecksCanBeCancelled() async throws {
        let manager = ScheduledHealthCheckManager()
        let colector = Colector()
        
        let id = await manager.scheduleChecks(
            delays: [0.1, 0.3, 0.5],
            reasonPrefix: "cancel"
        ) { razon in
            await colector.agregar(razon)
        }
        
        // Cancelar después de que potencialmente ejecute la primera
        try? await Task.sleep(for: .milliseconds(150))
        await manager.cancelSchedule(id: id)
        
        // Dar tiempo para validar que no se ejecutan posteriores
        try? await Task.sleep(for: .milliseconds(600))
        let todas = await colector.todas()
        
        // Debe ejecutarse a lo sumo la primera
        XCTAssertLessThanOrEqual(todas.count, 1, "La cancelación debe prevenir ejecuciones posteriores")
        if let unica = todas.first {
            XCTAssertTrue(unica.contains("0.1"), "Si se ejecutó alguna, debe ser la primera (0.1s)")
        }
    }
}
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
        
        // Registrar el thread actual (main thread)
        let initialThread = Thread.current
        
        // Lanzar chequeos
        await manager.scheduleHealthChecks(action: action, intervals: intervals)
        
        // Esperar con timeout
        await fulfillment(of: [expectation], timeout: 2.0)
        
        // Verificaciones:
        // 1. No se debe ejecutar en main thread
        XCTAssertEqual(mainThreadCallCount, 0, "Health checks debe ejecutarse en background, no en main thread")
        
        // 2. Se debe ejecutar en background thread
        XCTAssertGreater(backgroundThreadCallCount, 0, "Health checks debe ejecutarse en al menos 1 background thread")
        
        // 3. Main thread debe permanecer responsivo (esto se verifica si el test no se cuelga)
    }
    
    // MARK: - Test 2: Verificar que no se satura el main thread
    
    /// Verifica que el ScheduledHealthCheckManager no sature el main thread con múltiples async calls
    func testHealthCheckManagerDoesNotSaturateMainThread() async {
        let expectation = XCTestExpectation(description: "No main thread saturation detected")
        expectation.expectedFulfillmentCount = 1
        
        let intervals: [TimeInterval] = [0.1] // Un único intervalo para simplificar
        
        var threadIds: Set<UInt64> = []
        
        let action: @Sendable () async -> Void = { [weak self] in
            // Registrar ID del thread en el que se ejecuta
            let threadId = pthread_self()
            threadIds.insert(threadId)
            
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
        var executionCount = 0
        
        let intervals: [TimeInterval] = [0.1, 0.3, 0.5]
        
        let action: @Sendable () async -> Void = {
            executionCount += 1
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
        XCTAssertLessThan(executionCount, 3, "Cancelación debe prevenir ejecuciones futuras")
        
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
