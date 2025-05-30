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
}
