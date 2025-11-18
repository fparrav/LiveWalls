import Cocoa
import os.log

private let backgroundLogger = Logger(subsystem: "com.livewalls.app", category: "BackgroundColorWindow")

/// Simple window that displays a solid color as a background layer
/// Used during transitions to prevent showing system wallpaper
class BackgroundColorWindow: NSWindow {
    
    private let colorView: NSView
    
    /// Initialize with screen and adaptive color based on system appearance
    init(screen: NSScreen) {
        // Get adaptive color based on system appearance
        let backgroundColor = BackgroundColorWindow.adaptiveBackgroundColor()
        
        // Create colored view
        colorView = NSView()
        colorView.wantsLayer = true
        colorView.layer?.backgroundColor = backgroundColor.cgColor
        
        // Create window with frame matching the screen
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        // Configure window properties
        self.isReleasedWhenClosed = false
        self.ignoresMouseEvents = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        // Set window level just below desktop icons (above system wallpaper)
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 2)
        
        // Set content view
        self.contentView = colorView
        
        backgroundLogger.info("🎨 BackgroundColorWindow created for screen: \(screen.localizedName)")
    }
    
    /// Get adaptive background color based on system appearance
    static func adaptiveBackgroundColor() -> NSColor {
        let appearance = NSApp.effectiveAppearance
        let isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        
        if isDarkMode {
            // Dark mode: use very dark gray (almost black)
            return NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) // #1C1C1E
        } else {
            // Light mode: use very light gray (almost white)
            return NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.97, alpha: 1.0) // #F2F2F7
        }
    }
    
    /// Update color to match current system appearance
    func updateColor() {
        let newColor = BackgroundColorWindow.adaptiveBackgroundColor()
        colorView.layer?.backgroundColor = newColor.cgColor
        backgroundLogger.debug("🎨 Updated background color to match system appearance")
    }
    
    /// Cleanup and close window
    func cleanup() {
        backgroundLogger.info("🧹 Cleaning up BackgroundColorWindow")
        self.orderOut(nil)
        self.close()
    }
}
