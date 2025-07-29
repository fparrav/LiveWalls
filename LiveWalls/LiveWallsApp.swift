import SwiftUI
import AppKit
import os.log

/// Logger for the main application
fileprivate let appLogger = Logger(subsystem: "com.livewalls.app", category: "MainApp")

@main
struct LiveWallsApp: App {
    // AppDelegate initialization
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Safe WallpaperManager initialization with StateObject
    @StateObject private var wallpaperManager = WallpaperManager()
    
    // Auto-launch manager
    @StateObject private var launchManager = LaunchManager()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
                .onAppear {
                    // Configure AppDelegate after the view appears
                    appDelegate.wallpaperManager = wallpaperManager
                    appLogger.info("📱 Main window appeared - maintaining accessory policy")
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
        appLogger.info("🚀 Starting LiveWalls App")
        
        // Initial application configuration
        DispatchQueue.main.async {
            // Start as accessory application to maintain background behavior
            NSApp.setActivationPolicy(.accessory)
            
            // Configure initial behavior
            appLogger.info("🔧 Configuring initial window behavior")
            
            appLogger.info("✅ Accessory activation policy configured - app without dock icon")
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
