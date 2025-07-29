import Foundation
import ServiceManagement

/// Manager to configure automatic application launch at login.
final class LaunchManager: ObservableObject {
    @Published var isLaunchAtLoginEnabled: Bool = false
    
    private let bundleId = Bundle.main.bundleIdentifier ?? ""
    
    init() {
        checkLaunchAtLoginStatus()
    }
    
    /// Checks the current status of automatic launch
    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            // Use SMAppService on macOS 13+
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for earlier versions
            // En versiones anteriores, podríamos usar LSSharedFileList APIs
            // Por simplicidad, mantenemos false para versiones antiguas
            isLaunchAtLoginEnabled = false
        }
    }
    
    /// Configures automatic launch
    /// - Parameter enabled: true to enable, false to disable
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
                print("✅ Launch at login \(enabled ? "enabled" : "disabled")")
            } catch {
                print("❌ Error configuring launch at login: \(error.localizedDescription)")
            }
        } else {
            // For earlier macOS versions, do nothing for now
            print("⚠️ Launch at login not supported on this macOS version")
        }
    }
}
