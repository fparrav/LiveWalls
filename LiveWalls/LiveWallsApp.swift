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
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        
        MenuBarExtra("Live Walls", image: "statusbar-icon") {
            StatusBarMenuView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
        }
        .menuBarExtraStyle(.window)
        
        WindowGroup(id: "about") {
            AboutView()
        }
        // Without this, the WindowGroup opens at its own default system size
        // (larger than `AboutView`'s fixed 360x420 content) and only shrinks
        // to fit *after* `AboutView`'s `WindowAccessor` callback runs on the
        // next run-loop turn -- visible as a plain opaque rectangle bleeding
        // past the rounded glass card until then, and the size mismatch also
        // interferes with how the `.regularMaterial` blur composites against
        // the window backing. Sizing the window to its content up front (the
        // way the scene is declared, not as an AppKit post-fix) avoids both.
        .windowResizability(.contentSize)
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
