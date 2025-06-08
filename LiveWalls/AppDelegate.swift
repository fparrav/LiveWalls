import Cocoa
import os.log

/// AppDelegate mejorado con protección contra cierres inesperados de la ventana principal
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.livewalls.app", category: "AppLifecycle")
    private var mainWindowController: NSWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevenir múltiples instancias
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if runningApps.count > 1 {
            logger.warning("⚠️ Ya hay una instancia de LiveWalls corriendo. Activando la instancia existente y saliendo...")
            
            // Intentar activar la instancia existente
            for app in runningApps {
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    app.activate(options: [.activateIgnoringOtherApps])
                    break
                }
            }
            
            // Salir de ESTA instancia sin afectar a la existente
            DispatchQueue.main.async {
                exit(0) // Usar exit(0) en lugar de NSApp.terminate(nil)
            }
            return
        }
        
        // Configurar para manejar terminación
        NSApp.delegate = self
        
        // Registrar para notificación de cierre de ventana
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    @objc func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Verificar si es la ventana principal que se está cerrando
        if window == NSApp.mainWindow {
            logger.info("🪟 Ventana principal cerrándose")
            
            // Ajustar la lógica para manejar el cierre de la ventana principal sin usar `return`
            logger.info("🔄 Aplicación terminando o cierre inesperado detectado")
            
            // Si no está terminando, prevenir el cierre ordenando al frente de nuevo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Reabrir la ventana principal si no hay otras ventanas visibles
                if NSApp.windows.filter({ $0.isVisible }).isEmpty {
                    self.logger.info("🔄 Reabriendo ventana principal automáticamente")
                    self.showMainWindow()
                }
            }
        }
    }
    
    func showMainWindow() {
        // Política accessory: la app NO aparece en el Dock
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        // Buscar la ventana principal y traerla al frente
        if let window = NSApp.windows.first(where: { $0.isVisible == false && !($0 is NSPanel) }) {
            logger.info("🪟 Restaurando ventana principal existente")
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else if let window = NSApp.windows.first {
            logger.info("🪟 Usando primera ventana disponible")
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            // Si no hay ventanas, crear una nueva instancia de la ventana principal
            logger.warning("⚠️ No se encontró ventana principal existente. Recargando interfaz...")
            recreateMainWindow()
        }
    }
    
    private func recreateMainWindow() {
        // Esta es una implementación básica, puede necesitar ajustes según tu app
        logger.info("🔄 Recreando ventana principal")
        // Forzar a SwiftUI a recrear la ventana principal:
        // Enviar una notificación que la vista principal escuche para forzar su aparición
        NotificationCenter.default.post(name: NSNotification.Name("ShowMainWindow"), object: nil)
    }
    
    // Permitir terminación normal
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("🛑 Solicitud de terminación recibida")
        return .terminateNow
    }
}
