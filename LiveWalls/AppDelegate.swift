import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevenir múltiples instancias
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if runningApps.count > 1 {
            print("⚠️ Ya hay una instancia de LiveWalls corriendo. Saliendo...")
            NSApp.terminate(nil)
        }
    }
    
    func showMainWindow() {
        // Activar la aplicación y mostrar ventana principal
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Buscar la ventana principal y traerla al frente
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            // Si no hay ventanas, crear una nueva instancia de la ventana principal
            // Esto puede requerir una referencia al WindowGroup, pero en la mayoría de casos
            // la ventana ya existe, solo está oculta
            print("⚠️ No se encontró ventana principal existente")
        }
        
        // Después de mostrar la ventana, volver al modo agent si es necesario
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
