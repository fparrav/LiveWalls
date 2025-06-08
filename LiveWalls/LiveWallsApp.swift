import SwiftUI
import AppKit
import ServiceManagement
import os.log

/// Logger para la aplicación principal
fileprivate let appLogger = Logger(subsystem: "com.livewalls.app", category: "MainApp")

@main
struct LiveWallsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate // Posible punto a revisar: AppDelegate
    
    // Intenta comentar esta línea primero para ver si WallpaperManager.init() es el problema
    @StateObject private var wallpaperManager = WallpaperManager() 

    // Intenta comentar esta línea si la anterior no resuelve el problema
    // @State private var launchAtLogin = SMAppService.mainApp.status == .enabled 
    // Si la comentas, puedes usar un valor temporal:
    // @State private var launchAtLogin = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wallpaperManager) // Asegúrate que wallpaperManager esté disponible si no lo comentaste
                // Si comentaste wallpaperManager arriba, necesitarás un mock o comentar su uso aquí también.
                // Por ejemplo, podrías necesitar pasar un MockWallpaperManager si comentas el original:
                // .environmentObject(MockWallpaperManager()) // Asumiendo que tienes un MockWallpaperManager
                .onAppear {
                    // 🔗 Configurar conexión entre AppDelegate y WallpaperManager para gestión de terminación
                    setupTerminationHandling()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        appLogger.info("🟢 Aplicación activa")
                    case .inactive:
                        appLogger.info("🟡 Aplicación inactiva")
                    case .background:
                        appLogger.info("🔵 Aplicación en segundo plano")
                        // Ten cuidado aquí si wallpaperManager puede no estar inicializado
                        // if wallpaperManager.isPlayingWallpaper { 
                        //     appLogger.info("✅ Verificando wallpaper en segundo plano...")
                        // }
                    @unknown default:
                        appLogger.warning("⚠️ Estado de escena desconocido")
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra("Live Walls", systemImage: "video.fill") {
            Button("Abrir Configuración") {
                appLogger.info("🔘 Usuario solicitó abrir configuración")
                // Lógica para abrir la ventana de configuración
                // Asegúrate que esta lógica no cause problemas si appDelegate o wallpaperManager no están listos.
                 NotificationCenter.default.post(name: Notification.Name("ShowMainWindow"), object: nil)
            }
        }
    }
    
    /// 🔗 Configura la gestión de terminación de la aplicación
    private func setupTerminationHandling() {
        appLogger.info("🔗 Configurando gestión de terminación de la aplicación")
        
        // Configurar listener para notificación de terminación en WallpaperManager
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppWillTerminate"),
            object: nil,
            queue: .main
        ) { _ in
            appLogger.info("🧹 Ejecutando limpieza de WallpaperManager antes de terminar")
            wallpaperManager.stopWallpaper()
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
