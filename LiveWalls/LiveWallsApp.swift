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
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
                .onAppear {
                    appDelegate.wallpaperManager = wallpaperManager
                    if isUITesting {
                        appLogger.info("🧪 UI test window content appeared")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { !$0.className.contains("StatusBar") && !$0.className.contains("MenuWindow") }) {
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                                appLogger.info("🧪 UI test window activated - Window count: \(NSApp.windows.count)")
                            }
                        }
                    } else {
                        appLogger.info("📱 Main window appeared - maintaining accessory policy")
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        MenuBarExtra("Live Walls", image: "statusbar-icon") {
            StatusBarMenuView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
        }
        .menuBarExtraStyle(.menu)
        
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
