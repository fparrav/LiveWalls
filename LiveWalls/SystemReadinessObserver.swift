import Foundation
import AppKit
import OSLog

/// Observador reactivo del estado de disponibilidad del sistema (pantallas)
/// Reemplaza el polling síncrono con observación de notificaciones para evitar bloqueos del main thread
@MainActor
final class SystemReadinessObserver {
    
    // MARK: - Properties
    
    /// Logger para tracking de eventos de disponibilidad del sistema
    private let logger = Logger(subsystem: "com.livewalls.app", category: "SystemReadiness")
    
    /// Estado actual de disponibilidad: true si hay pantallas disponibles
    var isReady: Bool {
        !NSScreen.screens.isEmpty
    }
    
    // MARK: - Initialization
    
    init() {
        logger.debug("📱 SystemReadinessObserver inicializado")
    }
    
    deinit {
        logger.debug("🗑️ SystemReadinessObserver deallocado")
    }
    
    // MARK: - Public API
    
    /// Espera de forma asíncrona y reactiva a que el sistema esté listo (pantallas disponibles)
    /// - Parameter timeout: Tiempo máximo de espera en segundos
    /// - Returns: true si el sistema está listo, false si se excedió el timeout
    func waitUntilReady(timeout: TimeInterval) async -> Bool {
        // Si ya está listo, retornar inmediatamente sin esperar
        if isReady {
            logger.debug("✅ Sistema ya listo (pantallas disponibles)")
            return true
        }
        
        logger.info("⏳ Esperando disponibilidad de pantallas (timeout: \(timeout, format: .fixed(precision: 1))s)")
        
        // Usar AsyncStream para observar cambios de pantallas sin polling bloqueante
        return await withCheckedContinuation { continuation in
            var observer: NSObjectProtocol?
            var timeoutTask: Task<Void, Never>?
            var hasResumed = false
            
            let resume: (Bool) -> Void = { [weak self] result in
                guard !hasResumed else { return }
                hasResumed = true
                
                // Limpiar observer
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                
                // Cancelar timeout task
                timeoutTask?.cancel()
                
                if result {
                    self?.logger.debug("✅ Sistema listo (pantallas detectadas)")
                } else {
                    self?.logger.warning("⚠️ Timeout esperando pantallas (\(timeout, format: .fixed(precision: 1))s)")
                }
                
                continuation.resume(returning: result)
            }
            
            // Observar cambios en configuración de pantallas
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [logger] _ in
                // Verificar si ahora hay pantallas disponibles
                let hasScreens = !NSScreen.screens.isEmpty
                if hasScreens {
                    logger.debug("🖥️ Pantallas detectadas vía notificación")
                    resume(true)
                }
            }
            
            // Configurar timeout
            timeoutTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                    // Verificar una última vez al expirar el timeout
                    let finalReady = !NSScreen.screens.isEmpty
                    resume(finalReady)
                } catch {
                    // Task cancelado - observer ya disparó
                }
            }
            
            // Verificar de nuevo inmediatamente por si cambió entre la verificación inicial y el setup del observer
            Task { @MainActor in
                if !NSScreen.screens.isEmpty {
                    resume(true)
                }
            }
        }
    }
}
