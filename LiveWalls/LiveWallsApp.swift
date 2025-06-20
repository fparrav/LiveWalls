import SwiftUI
import AppKit
import os.log

/// Logger para la aplicación principal
fileprivate let appLogger = Logger(subsystem: "com.livewalls.app", category: "MainApp")

@main
struct LiveWallsApp: App {
    // Inicialización del AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Inicialización segura del WallpaperManager con StateObject
    @StateObject private var wallpaperManager = WallpaperManager()
    
    // Gestor de inicio automático
    @StateObject private var launchManager = LaunchManager()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
                .onAppear {
                    // Configurar el AppDelegate después de que la vista aparezca
                    appDelegate.wallpaperManager = wallpaperManager
                    appLogger.info("📱 Ventana principal apareció - manteniendo política regular")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        MenuBarExtra("Live Walls", image: "statusbar-icon") {
            StatusBarMenuView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
        }
        .menuBarExtraStyle(.menu)
    }
    
    init() {
        appLogger.info("🚀 Iniciando LiveWalls App")
        
        // Configuración inicial de la aplicación
        DispatchQueue.main.async {
            // Iniciar como aplicación regular para permitir ventana principal
            NSApp.setActivationPolicy(.regular)
            
            // Configurar comportamiento inicial
            appLogger.info("🔧 Configurando comportamiento inicial de ventanas")
            
            appLogger.info("✅ Política de activación regular configurada - app lista para mostrar ventanas")
        }
    }
}

// Considera añadir un MockWallpaperManager si necesitas comentar el real para pruebas:
// final class MockWallpaperManager: ObservableObject {
//     @Published var videoFiles: [VideoFile] = []
//     @Published var currentVideo: VideoFile? = nil
//     @Published var isPlayingWallpaper: Bool = false
//     func setActiveVideo(_ video: VideoFile) {}
//     func removeVideo(_ video: VideoFile) {}
//     func addVideoFiles(urls: [URL]) {}
//     func toggleWallpaper() {}
//     func stopWallpaper() {}
//     func resolveBookmark(for video: VideoFile) -> URL? { nil }
// }
