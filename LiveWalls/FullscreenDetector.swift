import Foundation
import AppKit
import os.log

/// Fullscreen application detector
/// Monitors application state and detects when an application enters or exits fullscreen mode
@MainActor
class FullscreenDetector: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Indicates if there is currently an application in fullscreen
    @Published var isAnyAppFullscreen: Bool = false
    
    /// Name of the application currently in fullscreen (if any)
    @Published var currentFullscreenApp: String? = nil
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "FullscreenDetector")
    private var applicationObserver: NSObjectProtocol?
    private var presentationOptionsObserver: NSObjectProtocol?
    
    // MARK: - Callbacks
    
    /// Callback that executes when an application enters fullscreen
    var onFullscreenEntered: ((String) -> Void)?
    
    /// Callback that executes when exiting fullscreen
    var onFullscreenExited: (() -> Void)?
    
    // MARK: - Initialization
    
    init() {
        logger.info("🔍 Initializing FullscreenDetector")
        setupObservers()
        
        // Check initial state
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.checkInitialFullscreenState()
        }
    }
    
    deinit {
        MainActor.assumeIsolated { [self] in
            logger.info("🔍 Deinitializing FullscreenDetector")
            removeObservers()
        }
    }
    
    // MARK: - Observer Setup
    
    private func setupObservers() {
        setupApplicationObservers()
        setupPresentationOptionsObserver()
    }
    
    private func setupApplicationObservers() {
        // Observe when applications become active
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.handleApplicationActivated(notification)
            }
        }
        
        logger.info("📡 NSWorkspace observers configured")
    }
    
    private func setupPresentationOptionsObserver() {
        // Observe changes in system presentation options
        presentationOptionsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.checkPresentationOptions()
            }
        }
        
        logger.info("📡 Presentation observer configured")
    }
    
    private func removeObservers() {
        if let observer = applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            applicationObserver = nil
        }
        
        if let observer = presentationOptionsObserver {
            NotificationCenter.default.removeObserver(observer)
            presentationOptionsObserver = nil
        }
        
        logger.info("📡 Observers removed")
    }
    
    // MARK: - State Detection
    
    private func checkInitialFullscreenState() async {
        await checkPresentationOptions()
        await checkActiveApplication()
    }
    
    private func handleApplicationActivated(_ notification: Notification) async {
        await checkActiveApplication()
    }
    
    private func checkActiveApplication() async {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            logger.debug("🔍 No active application")
            await updateFullscreenState(false, appName: nil)
            return
        }
        
        let appName = activeApp.localizedName ?? "Unknown"
        logger.debug("🔍 Active application: \(appName)")
        
        // Check if the application is in fullscreen
        let isFullscreen = await isApplicationFullscreen(activeApp)
        await updateFullscreenState(isFullscreen, appName: isFullscreen ? appName : nil)
    }
    
    private func checkPresentationOptions() async {
        let options = NSApp.presentationOptions
        let isFullscreen = options.contains(.fullScreen) || 
                          options.contains(.hideMenuBar) && options.contains(.hideDock)
        
        if isFullscreen {
            if let activeApp = NSWorkspace.shared.frontmostApplication {
                let appName = activeApp.localizedName ?? "Unknown"
                logger.info("🎮 Fullscreen detected via presentation options: \(appName)")
                await updateFullscreenState(true, appName: appName)
            }
        } else {
            // Check if we really exited fullscreen or something else changed
            await checkActiveApplication()
        }
    }
    
    private func isApplicationFullscreen(_ application: NSRunningApplication) async -> Bool {
        // Method 1: Check application windows
        let pid = application.processIdentifier
        
        // Get list of application windows
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            logger.warning("⚠️ Could not get window list")
            return false
        }
        
        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid else { continue }
            
            // Check if window occupies the entire screen
            if let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat,
               let y = bounds["Y"] as? CGFloat,
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                
                let windowRect = CGRect(x: x, y: y, width: width, height: height)
                
                // Check against each screen
                for screen in NSScreen.screens {
                    let screenFrame = screen.frame
                    
                    // Tolerance for minor differences
                    let tolerance: CGFloat = 10
                    
                    if abs(windowRect.origin.x - screenFrame.origin.x) < tolerance &&
                       abs(windowRect.origin.y - screenFrame.origin.y) < tolerance &&
                       abs(windowRect.width - screenFrame.width) < tolerance &&
                       abs(windowRect.height - screenFrame.height) < tolerance {
                        
                        logger.info("🎮 Fullscreen window detected: \(String(describing: windowRect)) on screen \(String(describing: screenFrame))")
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    private func updateFullscreenState(_ isFullscreen: Bool, appName: String?) async {
        let previousState = isAnyAppFullscreen
        
        isAnyAppFullscreen = isFullscreen
        currentFullscreenApp = appName
        
        // Detailed logging
        if isFullscreen && !previousState {
            logger.info("🎮 FULLSCREEN ENTERED: \(appName ?? "Unknown")")
            onFullscreenEntered?(appName ?? "Unknown")
        } else if !isFullscreen && previousState {
            logger.info("🏠 FULLSCREEN EXITED")
            onFullscreenExited?()
        }
        
        // Current state log
        if isFullscreen {
            logger.debug("📱 Current state: Fullscreen (\(appName ?? "Unknown"))")
        } else {
            logger.debug("🪟 Current state: Windowed mode")
        }
    }
    
    // MARK: - Public Interface
    
    /// Forces a manual check of fullscreen state
    func forceCheck() async {
        logger.info("🔄 Forcing fullscreen state check")
        await checkInitialFullscreenState()
    }
    
    /// Gets detailed information about current state
    func getCurrentState() -> (isFullscreen: Bool, appName: String?) {
        return (isAnyAppFullscreen, currentFullscreenApp)
    }
}

// MARK: - Debug Extensions

extension FullscreenDetector {
    
    /// Debugging information about current state
    func getDebugInfo() -> String {
        var info = "=== FullscreenDetector Debug Info ===\n"
        info += "Is Any App Fullscreen: \(isAnyAppFullscreen)\n"
        info += "Current Fullscreen App: \(currentFullscreenApp ?? "None")\n"
        
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            info += "Active Application: \(activeApp.localizedName ?? "Unknown")\n"
            info += "Active App PID: \(activeApp.processIdentifier)\n"
        }
        
        let options = NSApp.presentationOptions
        info += "Presentation Options: \(options.rawValue)\n"
        info += "Contains .fullScreen: \(options.contains(.fullScreen))\n"
        info += "Contains .hideMenuBar: \(options.contains(.hideMenuBar))\n"
        info += "Contains .hideDock: \(options.contains(.hideDock))\n"
        
        return info
    }
}
