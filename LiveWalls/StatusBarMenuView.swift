import SwiftUI
import AppKit
import os.log

/// Vista del menú del status bar con funcionalidades mejoradas
struct StatusBarMenuView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "StatusBarMenu")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Información del wallpaper actual
            if let currentVideo = wallpaperManager.currentVideo {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🎬 Wallpaper Actual")
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
            Button("Abrir aplicación") {
                openMainApplication()
            }
            .keyboardShortcut("o", modifiers: .command)
            
            if wallpaperManager.isPlayingWallpaper {
                Button("Detener wallpaper") {
                    wallpaperManager.stopWallpaper()
                }
                .keyboardShortcut("s", modifiers: .command)
            } else if wallpaperManager.currentVideo != nil {
                Button("Reproducir wallpaper") {
                    wallpaperManager.toggleWallpaper()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            
            Divider()
            
            // Configuraciones rápidas
            Toggle("Inicio automático", isOn: Binding(
                get: { launchManager.isLaunchAtLoginEnabled },
                set: { newValue in
                    launchManager.setLaunchAtLogin(newValue)
                }
            ))
            
            Divider()
            
            // Salir
            Button("Salir de Live Walls") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(minWidth: 200)
    }
    
    /// Abre la aplicación principal de manera segura evitando warnings
    private func openMainApplication() {
        logger.info("🚀 Abriendo aplicación principal desde status bar")
        
        // Cambiar política de activación temporalmente
        NSApp.setActivationPolicy(.regular)
        
        // Activar la aplicación
        NSApp.activate(ignoringOtherApps: true)
        
        // Buscar y mostrar la ventana principal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Buscar ventana principal (no de status bar)
            let mainWindows = NSApp.windows.filter { window in
                // Filtrar windows del status bar
                !window.className.contains("StatusBar") && 
                window.isVisible == false || window.isMiniaturized
            }
            
            if let mainWindow = mainWindows.first ?? NSApp.windows.first(where: { !$0.className.contains("StatusBar") }) {
                mainWindow.makeKeyAndOrderFront(nil)
                logger.info("✅ Ventana principal activada")
            } else {
                // Si no hay ventana principal, crear una nueva instancia
                logger.info("📱 No se encontró ventana principal, activando app")
            }
            
            // Volver a política accessory después de un momento
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
