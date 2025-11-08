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
    /// - Returns: Array de NSWindow creadas
    func createWindowsAsync(
        screens: [NSScreen],
        videoFile: VideoFile,
        bookmarkActor: BookmarkActor
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
        
        var createdWindows: [NSWindow] = []
        
        // Crear ventanas para cada pantalla de forma asíncrona
        for screen in screens {
            // Crear ventana de video para esta pantalla usando Task.detached en MainActor
            let window = await Task.detached { @MainActor in
                DesktopVideoWindowMejorada(screen: screen, videoURL: accessibleURL)
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
        
        // Liberar acceso security-scoped después de crear todas las ventanas
        await bookmarkActor.stopAccessingSecurityScopedResource(url: accessibleURL)
        
        print("✅ Creadas \(createdWindows.count) ventanas de forma asíncrona")
        return createdWindows
    }
}