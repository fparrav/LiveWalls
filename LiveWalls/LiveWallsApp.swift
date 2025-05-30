import SwiftUI
import AppKit

@main
struct LiveWallsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var wallpaperManager = WallpaperManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(wallpaperManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)

        // Menu en la barra del sistema
        MenuBarExtra("Live Walls", systemImage: "video.fill") {
            Button("Abrir Configuración") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
