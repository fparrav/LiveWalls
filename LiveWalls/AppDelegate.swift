import Cocoa
import os.log
import UserNotifications
import SwiftUI

/// AppDelegate simplificado que deja el manejo de ventanas a SwiftUI
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.livewalls.app", category: "AppLifecycle")
    
    /// Referencia al WallpaperManager
    var wallpaperManager: WallpaperManager? {
        didSet {
            logger.info("📱 WallpaperManager configurado")
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("🚀 Iniciando aplicación")
        
        // Configurar manejo de cierre de ventanas
        setupWindowCloseHandling()
        
        // Prevenir múltiples instancias
        if !isFirstInstance() {
            logger.warning("⚠️ Ya existe una instancia de la aplicación")
            NSApp.terminate(nil)
            return
        }
        
        // La política de activación y ventanas ahora se manejan completamente en LiveWallsApp.swift
        logger.info("✅ AppDelegate configurado - ventanas manejadas por SwiftUI")
    }
    
    /// Configura el manejo de cierre de ventanas
    private func setupWindowCloseHandling() {
        // Observar el cierre de ventanas para ajustar la política de activación
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
    
    /// Maneja el cierre de ventanas principales
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Si es una ventana principal (no de status bar), ajustar comportamiento
        if !window.className.contains("StatusBar") && !window.className.contains("MenuWindow") {
            logger.info("🚪 Ventana principal cerrándose - manteniendo app en background")
            
            // Verificar si quedan ventanas principales después del cierre
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let mainWindows = NSApp.windows.filter { w in
                    !w.className.contains("StatusBar") && 
                    !w.className.contains("MenuWindow") && 
                    w.isVisible && 
                    w != window
                }
                
                if mainWindows.isEmpty {
                    self.logger.info("📱 App funcionando en background - status bar disponible")
                    // Mantenemos política regular para permitir reactivación desde status bar
                }
            }
        }
    }

    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logger.info("🔄 Solicitud de reapertura - ventanas visibles: \(flag)")
        
        if !flag {
            // No hay ventanas visibles, necesitamos mostrar una
            logger.info("🎯 Mostrando ventana principal desde dock/reopen")
            
            DispatchQueue.main.async {
                // Activar la aplicación
                NSApp.activate(ignoringOtherApps: true)
                
                // Buscar cualquier ventana principal disponible
                let mainWindows = NSApp.windows.filter { window in
                    !window.className.contains("StatusBar") &&
                    !window.className.contains("MenuWindow") &&
                    window.canBecomeMain
                }
                
                if let window = mainWindows.first {
                    // Restaurar si está minimizada
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    
                    // Traer al frente
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    
                    self.logger.info("✅ Ventana restaurada desde dock/reopen")
                } else {
                    self.logger.warning("⚠️ No se encontró ventana para restaurar desde dock/reopen")
                }
            }
        }
        
        return true
    }
    
    // Permitir terminación normal
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logger.info("🛑 Solicitud de terminación recibida")
        return .terminateNow
    }
    
    /// Método auxiliar para abrir la ventana principal desde componentes externos
    @objc func showMainWindow() {
        logger.info("🚀 Mostrando ventana principal desde método auxiliar")
        
        DispatchQueue.main.async {
            // Activar la aplicación
            NSApp.unhide(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            // Buscar ventanas principales
            let mainWindows = NSApp.windows.filter { window in
                !window.className.contains("StatusBar") &&
                !window.className.contains("MenuWindow") &&
                window.canBecomeMain
            }
            
            if let window = mainWindows.first {
                // Restaurar y mostrar
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                
                // Verificar activación
                DispatchQueue.main.async {
                    window.makeKey()
                    NSApp.activate(ignoringOtherApps: true)
                }
                
                self.logger.info("✅ Ventana principal mostrada exitosamente")
            } else {
                self.logger.warning("⚠️ No se encontró ventana principal para mostrar")
            }
        }
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
