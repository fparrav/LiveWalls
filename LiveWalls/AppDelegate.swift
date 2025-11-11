import Cocoa
import os.log
import UserNotifications
import SwiftUI

/// Simplified AppDelegate that leaves window management to SwiftUI
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.livewalls.app", category: "AppLifecycle")
    
    /// Reference to WallpaperManager
    var wallpaperManager: WallpaperManager? {
        didSet {
            logger.info("📱 WallpaperManager configured")
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("🚀 Starting application")

        // Configure window close handling
        setupWindowCloseHandling()
        
        // Prevent multiple instances
        if !isFirstInstance() {
            logger.warning("⚠️ An instance of the application already exists")
            NSApp.terminate(nil)
            return
        }
        
        // Activation policy and windows are now handled completely in LiveWallsApp.swift
        logger.info("✅ AppDelegate configured - windows managed by SwiftUI")

        // Check for app updates in background and notify user (install / cancel / skip)
        InAppUpdater.shared.checkOnLaunchAndNotify()
    }
    
    // Prevent automatic document creation when app launches
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        logger.info("🚫 Preventing automatic untitled document creation")
        return false
    }
    
    // Prevent automatic document creation on reopen
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        logger.info("🚫 Preventing automatic untitled file creation on reopen")
        return false
    }
    
    /// Configura el manejo de cierre de ventanas
    private func setupWindowCloseHandling() {
        // Observar el cierre de ventanas para ajustar la política de activación
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    /// Handles main window closing
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // If it's a main window (not status bar), adjust behavior
        if !window.className.contains("StatusBar") && !window.className.contains("MenuWindow") {
            logger.info("🚪 Main window closing - keeping app in background")
            
            // Check if main windows remain after closing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let mainWindows = NSApp.windows.filter { w in
                    !w.className.contains("StatusBar") && 
                    !w.className.contains("MenuWindow") && 
                    w.isVisible && 
                    w != window
                }
                
                if mainWindows.isEmpty {
                    self.logger.info("📱 App running in background - status bar available")
                    // Maintain regular policy to allow reactivation from status bar
                }
            }
        }
    }

    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logger.info("🔄 Reopen request - visible windows: \(flag)")
        
        if !flag {
            // No visible windows, need to show one
            logger.info("🎯 Showing main window from dock/reopen")
            
            DispatchQueue.main.async {
                // Activate the application
                NSApp.activate(ignoringOtherApps: true)
                
                // Find any available main window
                let mainWindows = NSApp.windows.filter { window in
                    !window.className.contains("StatusBar") &&
                    !window.className.contains("MenuWindow") &&
                    window.canBecomeMain
                }
                
                if let window = mainWindows.first {
                    // Restore if minimized
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    
                    // Bring to front
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    
                    self.logger.info("✅ Window restored from dock/reopen")
                } else {
                    self.logger.warning("⚠️ No window found to restore from dock/reopen")
                }
            }
        }
        
        return true
    }
    
    // Allow normal termination
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("🛑 Termination request received")
        return .terminateNow
    }
    
    /// Helper method to open main window from external components
    @objc func showMainWindow() {
        logger.info("🚀 Showing main window from helper method")
        
        DispatchQueue.main.async {
            // Activate the application
            NSApp.unhide(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            // Find main windows
            let mainWindows = NSApp.windows.filter { window in
                !window.className.contains("StatusBar") &&
                !window.className.contains("MenuWindow") &&
                window.canBecomeMain
            }
            
            if let window = mainWindows.first {
                // Restore and show
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                
                // Verify activation
                DispatchQueue.main.async {
                    window.makeKey()
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                self.logger.info("✅ Main window shown successfully")
            } else {
                self.logger.warning("⚠️ No main window found to show")
            }
        }
    }
    
    /// ✅ Function to clean up resources before terminating the application
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("🛑 Terminating application")
        
        // Ensure WallpaperManager cleans up its resources
        wallpaperManager?.stopWallpaper()
    }
    
    /// Remove observers to avoid memory leaks when destroying AppDelegate
    deinit {
        // Remove window close observer to avoid leaks
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
    }
    
    private func isFirstInstance() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var isFirst = true
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.livewalls.app.instanceCheck"),
            object: nil,
            queue: nil
        ) { _ in
            isFirst = false
            semaphore.signal()
        }
        
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name("com.livewalls.app.instanceCheck"),
            object: nil
        )
        
        _ = semaphore.wait(timeout: .now() + 0.1)
        return isFirst
    }
}
