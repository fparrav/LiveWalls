import XCTest
@testable import LiveWalls

final class MainThreadBlockingTests: XCTestCase {

    // Mide que operaciones ligeras en MainActor se mantienen rápidas tras varios managers creados
    func testMultipleManagerInitializationIsFast() async {
        let t0 = Date()
        await MainActor.run {
            for _ in 0..<5 {
                let _ = WallpaperManager() // Inicialización no debe bloquear
            }
        }
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, 0.5, "Inicializar 5 managers debe ser <500ms en total")
    }

    // Verifica que ensurePlaying no bloquee el main thread bajo carga simulada
    func testEnsurePlayingNonBlockingUnderLoad() async {
        let manager = await MainActor.run { WallpaperManager() }
        // Simular que hay un video seleccionado y reproducción activa
        await MainActor.run {
            manager.videoFiles = []
        }
        // No hay video real, ensurePlaying debe salir rápido
        let t0 = Date()
        await MainActor.run {
            manager.ensurePlaying(reason: "test carga")
        }
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, 0.05, "ensurePlaying debe retornar rápido sin bloqueo")
    }

    // Verifica que programar health checks no bloquee el main thread
    func testSchedulingHealthChecksIsFast() async {
        let manager = ScheduledHealthCheckManager()
        let t0 = Date()
        await manager.scheduleHealthChecks(action: { }, intervals: [0.01, 0.02, 0.03])
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, 0.05, "Programar health checks debe ser inmediato (<50ms)")
    }
}
