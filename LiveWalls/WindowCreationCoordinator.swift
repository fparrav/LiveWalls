import Foundation
import AppKit

/// Coordinador para la creación asíncrona de ventanas de escritorio
/// Elimina el bloqueo del main thread durante la creación de ventanas múltiples
actor WindowCreationCoordinator {
    
    /// Crea ventanas de video para todas las pantallas de forma asíncrona
    /// - Parameters:
    ///   - screens: Array de pantallas donde crear las ventanas
    ///   - videoFile: Archivo de video para el wallpaper
    ///   - bookmarkActor: Actor para resolver bookmarks de seguridad
    ///   - startPaused: Si es true, las ventanas se crean pausadas para pre-carga
    ///   - staticImageURL: URL opcional de imagen estática para placeholder
    /// - Returns: Array de NSWindow creadas
    func createWindowsAsync(
        screens: [NSScreen],
        videoFile: VideoFile,
        bookmarkActor: BookmarkActor,
        startPaused: Bool = false,
        staticImageURL: URL? = nil
    ) async -> [NSWindow] {
        guard let bookmarkData = videoFile.bookmarkData else {
            print("❌ No hay bookmark data disponible")
            return []
        }
        
        // Resolver bookmark de forma asíncrona para obtener URL accesible
        let accessibleURL: URL
        do {
            accessibleURL = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
        } catch {
            print("❌ Error resolviendo bookmark: \(error.localizedDescription)")
            return []
        }
        
        // Iniciar acceso security-scoped
        let accessStarted = await bookmarkActor.startAccessingSecurityScopedResource(url: accessibleURL)
        guard accessStarted else {
            print("❌ No se pudo iniciar acceso security-scoped")
            return []
        }
        
        var createdWindows: [DesktopVideoWindowMejorada] = []
        
        // Crear ventanas para cada pantalla de forma asíncrona
        for screen in screens {
            // Crear ventana de video para esta pantalla usando Task.detached en MainActor
            let window = await Task.detached { @MainActor in
                DesktopVideoWindowMejorada(
                    screen: screen,
                    videoURL: accessibleURL,
                    startPaused: startPaused,
                    staticImageURL: staticImageURL
                )
            }.value
            
            // Configurar ventana
            await MainActor.run {
                window.orderFront(nil)
                window.orderBack(nil)
            }
            
            createdWindows.append(window)
            
            // Dar tiempo al sistema en lugar de bloquear con RunLoop
            await Task.yield()
        }
        
        // FASE 5.1: Si startPaused es true, esperar a que TODAS las ventanas estén ready
        if startPaused {
            print("⏳ Esperando a que todas las ventanas estén listas...")
            let maxWaitTime: TimeInterval = 10.0 // Timeout de 10 segundos
            let startTime = Date()
            
            while !createdWindows.allSatisfy({ $0.isPlayerReady }) {
                // Verificar timeout
                if Date().timeIntervalSince(startTime) > maxWaitTime {
                    print("⚠️ Timeout esperando ventanas ready - continuando de todas formas")
                    break
                }
                
                // Esperar un poco antes de verificar nuevamente
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            let readyCount = createdWindows.filter({ $0.isPlayerReady }).count
            print("✅ \(readyCount)/\(createdWindows.count) ventanas listas")
        }
        
        // Liberar acceso security-scoped después de crear todas las ventanas
        await bookmarkActor.stopAccessingSecurityScopedResource(url: accessibleURL)
        
        print("✅ Creadas \(createdWindows.count) ventanas de forma asíncrona")
        return createdWindows
    }
    
    /// Activa la reproducción en todas las ventanas después de la transición
    /// - Parameter windows: Array de ventanas donde activar reproducción
    /// - Returns: Número de ventanas donde se activó correctamente la reproducción
    @discardableResult
    func activatePlaybackInWindows(_ windows: [NSWindow]) async -> Int {
        var successCount = 0
        
        for window in windows {
            if let videoWindow = window as? DesktopVideoWindowMejorada {
                await MainActor.run {
                    if videoWindow.activatePlayback() {
                        successCount += 1
                    }
                }
            }
        }
        
        print("✅ Reproducción activada en \(successCount)/\(windows.count) ventanas")
        return successCount
    }
}