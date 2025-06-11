import Cocoa
import os.log
import UserNotifications
import SwiftUI

/// AppDelegate mejorado con protección contra cierres inesperados de la ventana principal
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.livewalls.app", category: "AppLifecycle")
    private var mainWindow: NSWindow?
    
    /// Referencia al WallpaperManager
    var wallpaperManager: WallpaperManager? {
        didSet {
            logger.info("📱 WallpaperManager configurado")
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("🚀 Iniciando aplicación")
        
        // Configurar la ventana principal
        setupMainWindow()
        
        // Prevenir múltiples instancias
        if !isFirstInstance() {
            logger.warning("⚠️ Ya existe una instancia de la aplicación")
            NSApp.terminate(nil)
            return
        }
        
        // Configurar la política de activación
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Live Walls"
        window.isReleasedWhenClosed = false // Importante: no liberar la ventana al cerrarla
        // Comentado: SwiftUI maneja la ventana principal automáticamente a través de LiveWallsApp
        // window.contentView = NSHostingView(rootView: ContentView())
        self.mainWindow = window
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = mainWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
    
    // Permitir terminación normal
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("🛑 Solicitud de terminación recibida")
        return .terminateNow
    }
    
    /// ✅ Función para limpiar recursos antes de terminar la aplicación
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("🛑 Terminando aplicación")
        
        // Asegurar que el WallpaperManager limpie sus recursos
        wallpaperManager?.stopWallpaper()
    }
    
    /// Elimina observers para evitar fugas de memoria al destruir el AppDelegate
    deinit {
        // Remover observer de cierre de ventana para evitar leaks
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
