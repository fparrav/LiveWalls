import Cocoa
import AppKit

/// Ventana de color sólido para usar como fondo durante transiciones
/// Esta ventana se coloca por encima del wallpaper del sistema para evitar destellos blancos
@MainActor
class BackgroundColorWindow: NSWindow {
    
    /// Crea una ventana de color sólido para una pantalla específica
    /// - Parameters:
    ///   - screen: La pantalla donde se mostrará la ventana
    ///   - color: El color de fondo a mostrar
    init(screen: NSScreen, color: NSColor) {
        // Configurar el frame para cubrir toda la pantalla
        let frame = screen.frame
        
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        // Configurar propiedades de la ventana
        self.isOpaque = true
        self.backgroundColor = color
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.ignoresMouseEvents = true
        
        // Asegurar que la ventana cubra toda la pantalla
        self.setFrame(frame, display: true)
        
        // Crear una vista de color sólido
        let colorView = NSView(frame: frame)
        colorView.wantsLayer = true
        colorView.layer?.backgroundColor = color.cgColor
        self.contentView = colorView
    }
    
    /// Muestra la ventana y fuerza su renderizado inmediato
    func showAndForceDisplay() {
        self.makeKeyAndOrderFront(nil)
        self.orderBack(nil)
        self.display()
        self.displayIfNeeded()
    }
    
    /// Determina el color apropiado según el tema del sistema
    /// - Returns: Color gris oscuro para modo oscuro, claro para modo claro
    static func appropriateBackgroundColor() -> NSColor {
        if NSApp.effectiveAppearance.name == .darkAqua {
            return NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        } else {
            return NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.85, alpha: 1.0)
        }
    }
    
    /// Crea ventanas de color de fondo para todas las pantallas
    /// - Parameter color: Color de fondo opcional. Si es nil, usa el color apropiado según el tema
    /// - Returns: Array de ventanas creadas
    static func createForAllScreens(color: NSColor? = nil) -> [BackgroundColorWindow] {
        let backgroundColor = color ?? appropriateBackgroundColor()
        return NSScreen.screens.map { screen in
            BackgroundColorWindow(screen: screen, color: backgroundColor)
        }
    }
}
