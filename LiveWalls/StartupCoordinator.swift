import Foundation
import OSLog

/// Actor que coordina el inicio diferido con backoff exponencial
/// Elimina el loop de 25 reintentos síncronos (5s de bloqueo) del main thread
actor StartupCoordinator {
    
    // MARK: - Propiedades
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "StartupCoordinator")
    
    // Backoff exponencial: 0.2s, 0.5s, 1.0s, 2.0s, 4.0s
    private let backoffIntervals: [TimeInterval] = [0.2, 0.5, 1.0, 2.0, 4.0]
    
    // MARK: - Inicialización
    
    init() {
        logger.info("🚀 StartupCoordinator inicializado")
    }
    
    // MARK: - Métodos públicos
    
    /// Coordina el inicio diferido con backoff exponencial
    /// - Parameters:
    ///   - hasVideo: Closure sincrónico en main thread que verifica si hay video disponible
    ///   - hasScreens: Closure async que verifica si hay pantallas disponibles
    ///   - maxRetries: Número máximo de reintentos (default: 5)
    ///   - startAction: Acción sincrónica en main thread a ejecutar cuando las condiciones se cumplan
    /// - Returns: `true` si el inicio fue exitoso, `false` si se agotaron los reintentos
    func coordinateStartup(
        hasVideo: @MainActor () -> Bool,
        hasScreens: @Sendable () async -> Bool,
        maxRetries: Int = 5,
        startAction: @MainActor () -> Void
    ) async -> Bool {
        
        logger.info("🔄 Iniciando coordinación de startup (maxRetries: \(maxRetries))")
        
        var attempt = 0
        
        while attempt <= maxRetries {
            attempt += 1
            
            logger.debug("🔍 Intento \(attempt)/\(maxRetries + 1): verificando condiciones...")
            
            // Verificar condiciones
            let videoAvailable = await MainActor.run { hasVideo() }
            let screensAvailable = await hasScreens()
            
            if videoAvailable && screensAvailable {
                logger.info("✅ Condiciones cumplidas en intento \(attempt): iniciando wallpaper")
                
                // Ejecutar acción de inicio
                await MainActor.run { startAction() }
                
                return true
            }
            
            // Si no es el último intento, aplicar backoff exponencial
            if attempt <= maxRetries {
                let backoffIndex = min(attempt - 1, backoffIntervals.count - 1)
                let delay = backoffIntervals[backoffIndex]
                
                logger.debug("⏳ Reintentando en \(String(format: "%.1f", delay))s (video: \(videoAvailable), pantallas: \(screensAvailable))")
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        logger.warning("⚠️ Startup fallido después de \(attempt) intentos - condiciones no cumplidas")
        return false
    }
}
