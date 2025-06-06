import SwiftUI
import AppKit
import ServiceManagement
import os.log

/// Logger para la aplicación principal
fileprivate let appLogger = Logger(subsystem: "com.livewalls.app", category: "MainApp")

@main
struct LiveWallsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var wallpaperManager = WallpaperManager()

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wallpaperManager)
                // Manejar cambios en el ciclo de vida de la app
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        appLogger.info("🟢 Aplicación activa")
                    case .inactive:
                        appLogger.info("🟡 Aplicación inactiva")
                    case .background:
                        appLogger.info("🔵 Aplicación en segundo plano")
                        // Verificar si las ventanas de wallpaper siguen activas
                        if wallpaperManager.isPlayingWallpaper {
                            appLogger.info("✅ Verificando wallpaper en segundo plano...")
                            // Aquí se podría añadir un refrescado del wallpaper si es necesario
                        }
                    @unknown default:
                        appLogger.warning("⚠️ Estado de escena desconocido")
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        // Evitar cierre accidental de la ventana
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu en la barra del sistema
        MenuBarExtra("Live Walls", systemImage: "video.fill") {
            // Abrir ventana principal usando AppDelegate
            Button("Abrir Configuración") {
                appLogger.info("🔘 Usuario solicitó abrir configuración")
                appDelegate.showMainWindow()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            // Toggle para iniciar al inicio del sistema
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchAtLogin = newValue
                    if newValue {
                        do {
                            try SMAppService.mainApp.register()
                            appLogger.info("✅ Aplicación registrada para inicio automático")
                        } catch {
                            appLogger.error("❌ Error al registrar inicio automático: \(error.localizedDescription)")
                        }
                    } else {
                        do {
                            try SMAppService.mainApp.unregister()
                            appLogger.info("🚫 Inicio automático desactivado")
                        } catch {
                            appLogger.error("❌ Error al desactivar inicio automático: \(error.localizedDescription)")
                        }
                    }
                })
            ) {
                Text("Iniciar al inicio del sistema")
            }

            if wallpaperManager.isPlayingWallpaper {
                Divider()
                
                Button("Detener Wallpaper") {
                    appLogger.info("🔘 Usuario solicitó detener wallpaper desde menú")
                    wallpaperManager.stopWallpaper()
                }
            }

            Divider()

            Button("Salir") {
                appLogger.info("🚪 Usuario solicitó salir de la aplicación")
                
                // Detener wallpaper antes de terminar
                if wallpaperManager.isPlayingWallpaper {
                    appLogger.info("🛑 Deteniendo wallpaper antes de salir")
                    wallpaperManager.stopWallpaper()
                    
                    // Dar tiempo para que se liberen los recursos
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApplication.shared.terminate(nil)
                    }
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
