import SwiftUI
import AppKit
import os.log

/// Vista del menú del status bar con funcionalidades mejoradas
struct StatusBarMenuView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @Environment(\.openWindow) private var openWindow
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "StatusBarMenu")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Información del wallpaper actual
            if let currentVideo = wallpaperManager.currentVideo {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🎬 Wallpaper Actual")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentVideo.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                
                Divider()
            }
            
            // Controles principales
            Button("Abrir aplicación") {
                openMainApplication()
            }
            .keyboardShortcut("o", modifiers: .command)
            
            if wallpaperManager.isPlayingWallpaper {
                Button("Detener wallpaper") {
                    wallpaperManager.stopWallpaper()
                }
                .keyboardShortcut("s", modifiers: .command)
            } else if wallpaperManager.currentVideo != nil {
                Button("Reproducir wallpaper") {
                    wallpaperManager.toggleWallpaper()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            
            Divider()
            
            // Configuraciones rápidas
            Toggle("Inicio automático", isOn: Binding(
                get: { launchManager.isLaunchAtLoginEnabled },
                set: { newValue in
                    launchManager.setLaunchAtLogin(newValue)
                }
            ))
            
            Divider()
            
            // Salir
            Button("Salir de Live Walls") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(8)
        .frame(minWidth: 200)
    }
    
    /// Abre la aplicación principal de manera segura y robusta usando SwiftUI + AppKit
    private func openMainApplication() {
        logger.info("🚀 Abriendo aplicación principal desde status bar")
        
        DispatchQueue.main.async {
            // Paso 1: Intentar usar openWindow de SwiftUI (método preferido)
            self.logger.info("🎯 Intentando abrir ventana con SwiftUI openWindow")
            self.openWindow(id: "main")
            
            // Paso 2: Dar tiempo a SwiftUI para procesar y luego verificar/activar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.activateApplicationAndWindows()
            }
        }
    }
    
    /// Activa la aplicación y busca/activa ventanas después de que SwiftUI haya procesado
    private func activateApplicationAndWindows() {
        logger.info("🔄 Activando aplicación y buscando ventanas")
        
        // Asegurar que la app no está oculta y está en política regular
        NSApp.unhide(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Buscar ventanas después de que SwiftUI haya tenido oportunidad de crearlas
        if let mainWindow = self.findMainWindow() {
            self.logger.info("✅ Ventana encontrada después de openWindow, activándola")
            self.activateWindow(mainWindow)
        } else {
            self.logger.info("🔍 No se encontró ventana después de openWindow, intentando fallback")
            self.fallbackWindowCreation()
        }
    }
    
    /// Fallback para crear ventana manualmente cuando SwiftUI openWindow no funciona
    private func fallbackWindowCreation() {
        logger.info("🛠️ Ejecutando fallback de creación manual de ventana")
        
        // Intentar métodos alternativos de AppKit
        if let keyWindow = NSApp.keyWindow {
            logger.info("🔑 Usando key window existente")
            activateWindow(keyWindow)
            return
        }
        
        if let mainWindow = NSApp.mainWindow {
            logger.info("🏠 Usando main window existente") 
            activateWindow(mainWindow)
            return
        }
        
        // Crear ventana manualmente como último recurso
        self.createManualWindow()
    }
    
    /// Crea una ventana manualmente usando AppKit + SwiftUI
    private func createManualWindow() {
        logger.info("🔨 Creando ventana manual con NSWindow + NSHostingView")
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Live Walls"
        window.center()
        window.isReleasedWhenClosed = false
        
        // Crear vista SwiftUI para la ventana manual
        let contentView = ContentView()
            .environmentObject(wallpaperManager)
            .environmentObject(launchManager)
        
        window.contentView = NSHostingView(rootView: contentView)
        
        // Mostrar la ventana
        activateWindow(window)
        
        logger.info("✅ Ventana manual creada y mostrada")
    }
    
    /// Activa una ventana específica de manera robusta
    private func activateWindow(_ window: NSWindow) {
        // Restaurar si está minimizada
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        
        // Traer al frente de manera forzosa
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        
        // Asegurar activación en el siguiente ciclo de run loop
        DispatchQueue.main.async {
            window.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            
            // Verificación adicional después de un breve delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !window.isKeyWindow {
                    self.logger.warning("⚠️ Ventana no se activó correctamente, reintentando")
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                self.logger.info("✅ Ventana principal activada exitosamente")
            }
        }
    }
    
    /// Encuentra la ventana principal de la aplicación con criterios mejorados
    private func findMainWindow() -> NSWindow? {
        logger.info("🔍 Buscando ventana principal...")
        
        // Buscar ventanas principales excluyendo las del status bar y panels
        let candidateWindows = NSApp.windows.filter { window in
            let className = window.className
            let isValidWindow = !className.contains("StatusBar") &&
                               !className.contains("MenuWindow") &&
                               !className.contains("NSPanel") &&
                               !className.contains("NSStatusBarWindow") &&
                               window.canBecomeMain
            
            if isValidWindow {
                self.logger.info("✅ Ventana candidata encontrada: \(className)")
            }
            
            return isValidWindow
        }
        
        logger.info("📊 Total de ventanas candidatas: \(candidateWindows.count)")
        
        // Priorizar ventana visible y no minimizada
        if let visibleWindow = candidateWindows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            logger.info("🎯 Ventana visible encontrada")
            return visibleWindow
        }
        
        // Si hay ventana minimizada, considerarla válida (se restaurará después)
        if let minimizedWindow = candidateWindows.first(where: { $0.isMiniaturized }) {
            logger.info("📦 Ventana minimizada encontrada")
            return minimizedWindow
        }
        
        // Expandir búsqueda a todas las ventanas que pueden ser main (incluso no visibles)
        let allMainWindows = NSApp.windows.filter { $0.canBecomeMain }
        if let anyMainWindow = allMainWindows.first {
            logger.info("🔄 Usando cualquier ventana main disponible")
            return anyMainWindow
        }
        
        logger.warning("⚠️ No se encontró ninguna ventana válida")
        return nil
    }
}
