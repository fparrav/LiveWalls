import SwiftUI
import AppKit
import ServiceManagement

@main
struct LiveWallsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var wallpaperManager = WallpaperManager()

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
            // Abrir ventana principal usando AppDelegate
            Button("Abrir Configuración") {
                appDelegate.showMainWindow()
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            // Toggle para iniciar al inicio del sistema
            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchAtLogin = newValue
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                })
            ) {
                Text("Iniciar al inicio del sistema")
            }

            Divider()

            Button("Salir") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
