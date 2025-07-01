import SwiftUI
import AppKit
import os.log

/// Vista del menú del status bar simplificada y robusta
struct StatusBarMenuView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @Environment(\.openWindow) private var openWindow
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "StatusBarMenu")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Información del wallpaper actual
            if let currentVideo = wallpaperManager.currentVideo {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("current_wallpaper", comment: "Current wallpaper"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentVideo.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                
                Divider()
            }
            
            // Controles principales
            Button(NSLocalizedString("open_app", comment: "Open app")) {
                openMainApplication()
            }
            .keyboardShortcut("o", modifiers: .command)
            
            if wallpaperManager.isPlayingWallpaper {
                Button(NSLocalizedString("stop_wallpaper", comment: "Stop wallpaper")) {
                    wallpaperManager.stopWallpaper()
                }
                .keyboardShortcut("s", modifiers: .command)
            } else if wallpaperManager.currentVideo != nil {
                Button(NSLocalizedString("play_wallpaper", comment: "Play wallpaper")) {
                    wallpaperManager.toggleWallpaper()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            
            Divider()
            
            // Configuraciones rápidas
            Toggle(NSLocalizedString("auto_launch", comment: "Auto launch"), isOn: Binding(
                get: { launchManager.isLaunchAtLoginEnabled },
                set: { newValue in
                    launchManager.setLaunchAtLogin(newValue)
                }
            ))
            
            Divider()
            
            // Salir
            Button(NSLocalizedString("quit_app", comment: "Quit app")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(minWidth: 200)
    }
    
    /// Abre la aplicación principal de manera simple y confiable usando solo SwiftUI
    private func openMainApplication() {
        logger.info("🚀 Abriendo aplicación principal desde status bar")
        
        DispatchQueue.main.async {
            // Verificar si ya existe una ventana principal visible
            if let existingWindow = self.findMainWindow(), existingWindow.isVisible {
                self.logger.info("✅ Ventana existente encontrada - activándola")
                self.activateExistingWindow(existingWindow)
                return
            }
            
            // Activar app y crear ventana con SwiftUI - simple y directo
            self.logger.info("🆕 Creando nueva ventana con SwiftUI")
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            self.openWindow(id: "main")
        }
    }
    
    /// Encuentra la ventana principal de la aplicación de manera simple
    private func findMainWindow() -> NSWindow? {
        // Buscar ventanas principales excluyendo las del status bar
        let candidateWindows = NSApp.windows.filter { window in
            let className = window.className
            return !className.contains("StatusBar") &&
                   !className.contains("MenuWindow") &&
                   !className.contains("NSPanel") &&
                   window.canBecomeMain
        }
        
        // Priorizar ventana visible y no minimizada
        return candidateWindows.first(where: { $0.isVisible && !$0.isMiniaturized }) ??
               candidateWindows.first(where: { $0.isMiniaturized }) ??
               candidateWindows.first
    }
    
    /// Activa una ventana existente de manera simple
    private func activateExistingWindow(_ window: NSWindow) {
        logger.info("🎯 Activando ventana existente")
        
        // Restaurar si está minimizada
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        
        // Activar ventana y aplicación
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        logger.info("✅ Ventana activada correctamente")
    }
}
