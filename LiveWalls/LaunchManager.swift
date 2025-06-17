import Foundation
import ServiceManagement
import os.log

/// Gestor para controlar el inicio automático de la aplicación con el sistema
class LaunchManager: ObservableObject {
    private let logger = Logger(subsystem: "com.livewalls.app", category: "LaunchManager")
    private let userDefaults = UserDefaults.standard
    private let launchAtLoginKey = "LaunchAtLogin"
    
    /// Estado actual del launch at login
    @Published var isLaunchAtLoginEnabled: Bool = false {
        didSet {
            if oldValue != isLaunchAtLoginEnabled {
                saveLaunchAtLoginState()
            }
        }
    }
    
    init() {
        loadLaunchAtLoginState()
        // Verificar estado actual del sistema
        checkSystemLaunchAtLoginState()
    }
    
    /// Carga el estado guardado de UserDefaults
    private func loadLaunchAtLoginState() {
        isLaunchAtLoginEnabled = userDefaults.bool(forKey: launchAtLoginKey)
        logger.info("📱 Estado de Launch at Login cargado: \(self.isLaunchAtLoginEnabled)")
    }
    
    /// Guarda el estado en UserDefaults
    private func saveLaunchAtLoginState() {
        userDefaults.set(isLaunchAtLoginEnabled, forKey: launchAtLoginKey)
        logger.info("💾 Estado de Launch at Login guardado: \(self.isLaunchAtLoginEnabled)")
    }
    
    /// Activa o desactiva el launch at login
    func setLaunchAtLogin(_ enabled: Bool) {
        logger.info("🔄 Configurando Launch at Login: \(enabled)")
        
        // Usar SMAppService (macOS 13+) con fallback a LSSharedFileList
        if #available(macOS 13.0, *) {
            setLaunchAtLoginModern(enabled)
        } else {
            setLaunchAtLoginLegacy(enabled)
        }
        
        // Actualizar estado local
        isLaunchAtLoginEnabled = enabled
    }
    
    /// Configuración moderna usando SMAppService (macOS 13+)
    @available(macOS 13.0, *)
    private func setLaunchAtLoginModern(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("✅ Launch at Login registrado correctamente (SMAppService)")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("❌ Launch at Login desregistrado correctamente (SMAppService)")
            }
        } catch {
            logger.error("❗️ Error configurando Launch at Login (SMAppService): \(error.localizedDescription)")
        }
    }
    
    /// Configuración legacy usando LSSharedFileList (macOS < 13)
    /// Nota: Implementación simplificada para versiones antiguas
    private func setLaunchAtLoginLegacy(_ enabled: Bool) {
        logger.info("⚠️ Launch at Login no es completamente soportado en macOS < 13.0")
        logger.info("📝 Se recomienda actualizar a macOS 13+ para funcionalidad completa")
        
        // Para versiones legacy, solo guardamos la preferencia del usuario
        // El usuario deberá configurar manualmente el inicio automático en Preferencias del Sistema
        if enabled {
            logger.info("💡 Para configurar inicio automático: Preferencias del Sistema > Usuarios y Grupos > Objetos de inicio")
        }
    }
    
    /// Verifica el estado actual del sistema
    private func checkSystemLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            let isRegistered = status == .enabled
            
            // Solo actualizar si hay discrepancia
            if isRegistered != isLaunchAtLoginEnabled {
                logger.info("🔄 Sincronizando estado: Sistema=\(isRegistered), Local=\(self.isLaunchAtLoginEnabled)")
                isLaunchAtLoginEnabled = isRegistered
            }
        }
        // Para versiones legacy, es más complejo verificar el estado, así que confiamos en UserDefaults
    }
    
    /// Obtiene el estado actual del launch at login
    func getCurrentStatus() -> Bool {
        checkSystemLaunchAtLoginState()
        return isLaunchAtLoginEnabled
    }
}
