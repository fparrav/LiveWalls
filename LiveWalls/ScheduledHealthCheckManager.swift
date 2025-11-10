import Foundation
import os.log

/// Actor para programar verificaciones de salud en background sin saturar el main thread
/// Reemplaza las llamadas a DispatchQueue.main.asyncAfter para verificaciones post-arranque
actor ScheduledHealthCheckManager {
    // MARK: - Private Properties
    
    /// Logger para debugging
    private let appLogger = Logger(subsystem: "com.livewalls.app", category: "ScheduledHealthCheckManager")
    
    /// Tarea actual de chequeos programados (para poder cancelarla)
    private var healthCheckTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Programa chequeos de salud a intervalos específicos en background
    /// - Parameters:
    ///   - action: Closure async a ejecutar en cada intervalo (se ejecuta en background)
    ///   - intervals: Array de TimeInterval en segundos para programar los chequeos
    func scheduleHealthChecks(
        action: @Sendable @escaping () async -> Void,
        intervals: [TimeInterval]
    ) async {
        // Cancelar cualquier tarea anterior
        healthCheckTask?.cancel()
        
        // Crear una tarea que se ejecute en background
        let task = Task.detached {
            for interval in intervals {
                if Task.isCancelled { break }
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    // Cancelado durante el sleep
                    break
                }
                if Task.isCancelled { break }
                await action()
            }
        }
        
        // Registrar la tarea para poder cancelarla después
        self.healthCheckTask = task
        
        appLogger.info("📅 Chequeos de salud programados para intervalos: \(intervals.map { String(format: "%.1f", $0) }.joined(separator: ", ")) segundos")
    }
    
    /// Cancela los chequeos de salud programados
    func cancelHealthChecks() async {
        appLogger.info("🛑 Cancelando chequeos de salud programados")
        
        // Cancelar la tarea si existe
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }
}
