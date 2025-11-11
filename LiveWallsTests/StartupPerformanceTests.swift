import XCTest
@testable import LiveWalls

final class StartupPerformanceTests: XCTestCase {

    // Verifica que la coordinación de arranque no bloquee el main thread
    func testFullStartupDoesNotBlockMainThread() async {
        let coordinator = StartupCoordinator()
        let ready = XCTestExpectation(description: "coordinateStartup finished")
        
        // Simular condiciones listas y acción ligera
        Task {
            let ok = await coordinator.coordinateStartup(
                hasVideo: { true },
                hasScreens: { true },
                maxRetries: 1,
                startAction: { /* no-op */ }
            )
            XCTAssertTrue(ok)
            ready.fulfill()
        }
        
        // Mientras corre, el main thread debe responder rápidamente
        let t0 = Date()
        await MainActor.run { _ = 1 + 1 }
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, 0.05, "Main thread debe permanecer responsivo (<50ms)")
        
        await fulfillment(of: [ready], timeout: 1.0)
    }

    // Verifica que el tiempo del "arranque" coordinado esté bajo 200ms en condiciones ideales
    func testStartupTimeUnder200ms() async {
        let coordinator = StartupCoordinator()
        let t0 = Date()
        let ok = await coordinator.coordinateStartup(
            hasVideo: { true },
            hasScreens: { true },
            maxRetries: 1,
            startAction: { /* no-op */ }
        )
        XCTAssertTrue(ok)
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, 0.2, "La coordinación de arranque debería ser <200ms en condiciones ideales")
    }

    // Verifica que no se bloquee el main thread durante reintentos con backoff
    func testNoMainThreadBlockingDuringAutoStart() async {
        let coordinator = StartupCoordinator()
        let ready = XCTestExpectation(description: "coordinateStartup finished with retries")
        
        // Actor para encapsular el contador mutable y evitar warning de captura mutable en closure @Sendable
        actor RetryTracker {
            private var count = 0
            func increment() {
                count += 1
            }
            func shouldRetry() -> Bool {
                count > 1
            }
        }
        
        // Simular que pantallas no listas al inicio y listas luego
        let tracker = RetryTracker()
        Task {
            let ok = await coordinator.coordinateStartup(
                hasVideo: { true },
                hasScreens: {
                    await tracker.increment()
                    // Falla la primera vez, luego true
                    return await tracker.shouldRetry()
                },
                maxRetries: 3,
                startAction: { /* no-op */ }
            )
            XCTAssertTrue(ok)
            ready.fulfill()
        }
        
        // Comprobar que main responde durante reintentos
        for _ in 0..<3 {
            let t0 = Date()
            await MainActor.run { _ = 2 + 2 }
            let dt = Date().timeIntervalSince(t0)
            XCTAssertLessThan(dt, 0.05)
        }
        
        await fulfillment(of: [ready], timeout: 3.0)
    }

    // Verifica que tareas de background completen dentro de un timeout razonable
    func testBackgroundTasksCompleteWithinTimeout() async {
        let manager = ScheduledHealthCheckManager()
        let exp = expectation(description: "Scheduled checks executed")
        exp.expectedFulfillmentCount = 2
        
        await manager.scheduleHealthChecks(action: {
            exp.fulfill()
        }, intervals: [0.05, 0.1])
        
        // El main debe seguir responsivo
        await MainActor.run { _ = 3 + 3 }
        
        await fulfillment(of: [exp], timeout: 1.0)
    }
}
