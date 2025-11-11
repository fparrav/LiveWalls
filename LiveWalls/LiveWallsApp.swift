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
    
    // Detect UI testing mode for configuration
    private var isUITesting: Bool {
        CommandLine.arguments.contains("-UITests")
    }
    
    @SceneBuilder
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
                .onAppear {
                    // Configure AppDelegate after the view appears
                    appDelegate.wallpaperManager = wallpaperManager
                    
                    // In UI test mode, ensure window becomes key and visible
                    if isUITesting {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { !$0.className.contains("StatusBar") && !$0.className.contains("MenuWindow") }) {
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                                appLogger.info("🧪 UI test window activated and brought to front")
                            }
                        }
                    } else {
                        appLogger.info("📱 Main window appeared - maintaining accessory policy")
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            // Remove the "New" menu item since this is not a document-based app
            CommandGroup(replacing: .newItem) { }
            
            // Replace default About panel to show our SwiftUI About window
            CommandGroup(replacing: .appInfo) {
                Button(NSLocalizedString("about", comment: "About")) {
                    NSApp.orderFrontStandardAboutPanel(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button(NSLocalizedString("check_for_updates", comment: "Check for updates")) {
                    InAppUpdater.shared.checkForUpdates()
                }
            }
        }

        MenuBarExtra("Live Walls", image: "statusbar-icon") {
            StatusBarMenuView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
        }
        .menuBarExtraStyle(.menu)

        // About window
        WindowGroup(id: "about") {
            AboutView()
        }
    }
    
    init() {
        appLogger.info("🚀 Starting LiveWalls App")
        
        // Initial application configuration
        DispatchQueue.main.async { [self] in
            if self.isUITesting {
                // In UI tests, use regular activation policy so the window is visible and interactive
                NSApp.setActivationPolicy(.regular)
                appLogger.info("🧪 UI Testing mode detected - using regular activation policy")
            } else {
                // Start as accessory application to maintain background behavior
                NSApp.setActivationPolicy(.accessory)
                appLogger.info("✅ Accessory activation policy configured - app without dock icon")
            }
            
            // Configure initial behavior
            appLogger.info("🔧 Configuring initial window behavior")
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
