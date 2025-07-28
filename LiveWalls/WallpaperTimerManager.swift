import Foundation
import AppKit
import os.log

/// Gestor robusto de timer para rotación automática de wallpapers
/// Implementa singleton pattern para prevenir múltiples instancias y asegurar comportamiento consistente
@MainActor
class WallpaperTimerManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = WallpaperTimerManager()
    
    // MARK: - Published Properties
    
    @Published var isTimerActive: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentInterval: TimeInterval = 0
    @Published var nextChangeTime: Date? = nil
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "WallpaperTimerManager")
    private var activeTimer: Timer? = nil
    private var pausedRemainingTime: TimeInterval = 0
    private var pausedAt: Date? = nil
    private var timerID: UUID? = nil
    
    // Callback para cuando el timer se dispara
    private var timerCallback: (() async -> Void)? = nil
    
    // Mutex para thread safety
    private let timerLock = NSLock()
    
    // MARK: - Timer Statistics (Para debugging)
    
    private var timerStartTime: Date? = nil
    private var timerFireCount: Int = 0
    private var lastFireTime: Date? = nil
    
    // MARK: - Initialization
    
    private init() {
        logger.info("⏰ Inicializando WallpaperTimerManager (Singleton)")
    }
    
    deinit {
        logger.info("⏰ Deinicializando WallpaperTimerManager")
        Task { @MainActor in
            stopTimer()
        }
    }
    
    // MARK: - Public Interface
    
    /// Inicia el timer con el intervalo especificado
    /// - Parameters:
    ///   - interval: Intervalo en segundos entre cambios
    ///   - callback: Función que se ejecuta cada vez que el timer se dispara
    func startTimer(interval: TimeInterval, callback: @escaping () async -> Void) {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        guard interval > 0 else {
            logger.error("❌ Intervalo inválido: \(interval). Debe ser mayor que 0")
            return
        }
        
        // Detener timer existente si lo hay
        stopTimerInternal()
        
        // Configurar nuevo timer
        currentInterval = interval
        timerCallback = callback
        timerID = UUID()
        
        // Crear y configurar timer
        let currentTimerID = timerID!
        activeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                await self?.handleTimerFire(timerID: currentTimerID, timer: timer)
            }
        }
        
        // Actualizar estado
        isTimerActive = true
        isPaused = false
        timerStartTime = Date()
        timerFireCount = 0
        nextChangeTime = Date().addingTimeInterval(interval)
        
        logger.info("⏰ Timer iniciado: \(Int(interval))s, ID: \(currentTimerID)")
    }
    
    /// Pausa el timer manteniendo el tiempo restante
    func pauseTimer() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        guard isTimerActive && !isPaused else {
            logger.warning("⚠️ No se puede pausar: timer no activo o ya pausado")
            return
        }
        
        guard let nextChange = nextChangeTime else {
            logger.error("❌ No se puede pausar: no hay próximo cambio programado")
            return
        }
        
        // Calcular tiempo restante
        let now = Date()
        pausedRemainingTime = max(0, nextChange.timeIntervalSince(now))
        pausedAt = now
        
        // Detener timer actual
        activeTimer?.invalidate()
        activeTimer = nil
        
        // Actualizar estado
        isPaused = true
        nextChangeTime = nil
        
        logger.info("⏸️ Timer pausado. Tiempo restante: \(Int(self.pausedRemainingTime))s")
    }
    
    /// Reanuda el timer desde donde se pausó
    func resumeTimer() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        guard isTimerActive && isPaused else {
            logger.warning("⚠️ No se puede resumir: timer no pausado")
            return
        }
        
        guard let callback = timerCallback, let currentTimerID = timerID else {
            logger.error("❌ No se puede resumir: falta callback o ID de timer")
            return
        }
        
        // Si el tiempo restante es muy pequeño, disparar inmediatamente
        if pausedRemainingTime <= 1.0 {
            logger.info("⏰ Tiempo restante muy pequeño, disparando inmediatamente")
            Task {
                await callback()
                // Reiniciar con intervalo completo
                startTimer(interval: currentInterval, callback: callback)
            }
            return
        }
        
        // Crear timer con tiempo restante
        activeTimer = Timer.scheduledTimer(withTimeInterval: pausedRemainingTime, repeats: false) { [weak self] timer in
            Task { @MainActor [weak self] in
                await self?.handleTimerFire(timerID: currentTimerID, timer: timer)
                
                // Después del primer disparo, crear timer normal con intervalo completo
                if let self = self, let callback = self.timerCallback {
                    self.startTimer(interval: self.currentInterval, callback: callback)
                }
            }
        }
        
        // Actualizar estado
        isPaused = false
        nextChangeTime = Date().addingTimeInterval(pausedRemainingTime)
        
        logger.info("▶️ Timer resumido. Próximo cambio en: \(Int(self.pausedRemainingTime))s")
    }
    
    /// Detiene completamente el timer
    func stopTimer() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        stopTimerInternal()
    }
    
    /// Reinicia el timer con nuevo intervalo (equivale a stop + start)
    func restartTimer(interval: TimeInterval, callback: @escaping () async -> Void) {
        logger.info("🔄 Reiniciando timer con intervalo: \(Int(interval))s")
        stopTimer()
        startTimer(interval: interval, callback: callback)
    }
    
    // MARK: - Private Methods
    
    private func stopTimerInternal() {
        activeTimer?.invalidate()
        activeTimer = nil
        timerCallback = nil
        timerID = nil
        
        // Resetear estado
        isTimerActive = false
        isPaused = false
        pausedRemainingTime = 0
        pausedAt = nil
        nextChangeTime = nil
        
        // Resetear estadísticas
        timerStartTime = nil
        timerFireCount = 0
        lastFireTime = nil
        
        logger.info("⏹️ Timer detenido completamente")
    }
    
    private func handleTimerFire(timerID: UUID, timer: Timer) async {
        // Verificar que este es el timer correcto (prevenir race conditions)
        guard self.timerID == timerID else {
            logger.warning("⚠️ Timer obsoleto disparado, ignorando")
            return
        }
        
        // Actualizar estadísticas
        timerFireCount += 1
        lastFireTime = Date()
        
        logger.info("🔥 Timer disparado (disparo #\(self.timerFireCount))")
        
        // Ejecutar callback
        if let callback = timerCallback {
            await callback()
        }
        
        // Si no es repetitivo, planificar próximo disparo
        if !timer.isValid || !(activeTimer?.isValid ?? false) {
            // Timer was invalidated, don't update next change time
            return
        }
        
        // Actualizar próximo cambio
        nextChangeTime = Date().addingTimeInterval(currentInterval)
        
        logger.debug("⏭️ Próximo cambio programado: \(self.nextChangeTime?.formatted() ?? "None")")
    }
    
    // MARK: - State Validation
    
    /// Valida que el estado del timer sea consistente
    func validateState() -> Bool {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        let isValid = validateStateInternal()
        
        if !isValid {
            logger.error("❌ Estado de timer inconsistente detectado")
            logDebugInfo()
        }
        
        return isValid
    }
    
    private func validateStateInternal() -> Bool {
        // Validar que el estado Published coincida con el estado interno
        if isTimerActive {
            // Si está activo, debe tener timer o estar pausado
            if activeTimer == nil && !isPaused {
                return false
            }
            
            // Si está pausado, no debe tener timer activo
            if isPaused && activeTimer != nil {
                return false
            }
            
            // Debe tener callback y timer ID
            if timerCallback == nil || timerID == nil {
                return false
            }
        } else {
            // Si no está activo, no debe tener timer ni estar pausado
            if activeTimer != nil || isPaused || timerCallback != nil {
                return false
            }
        }
        
        return true
    }
    
    /// Recupera automáticamente de estados inconsistentes
    func recoverFromInconsistentState() {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        logger.warning("🔧 Iniciando recuperación de estado inconsistente")
        
        // Detener todo y limpiar estado
        stopTimerInternal()
        
        logger.info("✅ Recuperación completada, timer reseteado")
    }
    
    // MARK: - Debug Information
    
    func getDebugInfo() -> String {
        timerLock.lock()
        defer { timerLock.unlock() }
        
        var info = "=== WallpaperTimerManager Debug Info ===\n"
        info += "Is Timer Active: \(isTimerActive)\n"
        info += "Is Paused: \(isPaused)\n"
        info += "Current Interval: \(Int(currentInterval))s\n"
        info += "Timer ID: \(timerID?.uuidString ?? "None")\n"
        info += "Active Timer: \(activeTimer != nil ? "Yes" : "No")\n"
        info += "Timer Valid: \(activeTimer?.isValid ?? false)\n"
        info += "Next Change Time: \(nextChangeTime?.formatted() ?? "None")\n"
        info += "Paused Remaining Time: \(Int(pausedRemainingTime))s\n"
        info += "Paused At: \(pausedAt?.formatted() ?? "None")\n"
        info += "Fire Count: \(timerFireCount)\n"
        info += "Last Fire Time: \(lastFireTime?.formatted() ?? "None")\n"
        
        if let startTime = timerStartTime {
            let uptime = Date().timeIntervalSince(startTime)
            info += "Timer Uptime: \(Int(uptime))s\n"
        }
        
        info += "State Valid: \(validateStateInternal())\n"
        
        return info
    }
    
    private func logDebugInfo() {
        let debugInfo = getDebugInfo()
        logger.info("🐛 Debug Info:\n\(debugInfo)")
    }
}

// MARK: - Timer Health Check

extension WallpaperTimerManager {
    
    /// Verifica la salud del timer y corrige problemas automáticamente
    func performHealthCheck() -> Bool {
        logger.info("🏥 Realizando health check del timer")
        
        let isHealthy = validateState()
        
        if !isHealthy {
            logger.warning("⚠️ Timer no saludable, iniciando auto-corrección")
            recoverFromInconsistentState()
            return false
        }
        
        // Verificar si el timer debería haber disparado ya
        if let nextChange = nextChangeTime, !isPaused {
            let now = Date()
            if now > nextChange.addingTimeInterval(5) { // 5 segundos de tolerancia
                logger.warning("⚠️ Timer parece estar atrasado, puede haber problema")
                return false
            }
        }
        
        logger.info("✅ Timer saludable")
        return true
    }
}