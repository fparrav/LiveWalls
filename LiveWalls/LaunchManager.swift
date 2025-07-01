import Foundation
import ServiceManagement

/// Gestor para configurar el lanzamiento automático de la aplicación al iniciar sesión.
final class LaunchManager: ObservableObject {
    @Published var isLaunchAtLoginEnabled: Bool = false
    
    private let bundleId = Bundle.main.bundleIdentifier ?? ""
    
    init() {
        checkLaunchAtLoginStatus()
    }
    
    /// Verifica el estado actual del lanzamiento automático
    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            // Usar SMAppService en macOS 13+
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            // Fallback para versiones anteriores
            // En versiones anteriores, podríamos usar LSSharedFileList APIs
            // Por simplicidad, mantenemos false para versiones antiguas
            isLaunchAtLoginEnabled = false
        }
    }
    
    /// Configura el lanzamiento automático
    /// - Parameter enabled: true para habilitar, false para deshabilitar
    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != isLaunchAtLoginEnabled else { return }
        
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                isLaunchAtLoginEnabled = enabled
                print("✅ Launch at login \(enabled ? "habilitado" : "deshabilitado")")
            } catch {
                print("❌ Error configurando launch at login: \(error.localizedDescription)")
            }
        } else {
            // Para versiones anteriores de macOS, no hacer nada por ahora
            print("⚠️ Launch at login no soportado en esta versión de macOS")
        }
    }
}
