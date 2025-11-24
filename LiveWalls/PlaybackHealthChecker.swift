import Foundation
import AppKit
import AVFoundation
import os.log

/// Actor para realizar verificaciones de salud de reproducción de forma asíncrona y thread-safe
/// Reemplaza verificaciones síncronas bloqueantes en ensurePlaying con operaciones asíncronas
actor PlaybackHealthChecker {
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "PlaybackHealthChecker")
    
    /// Verifica el estado de salud de la reproducción de wallpaper
    /// - Parameters:
    ///   - windows: Ventanas de escritorio activas
    ///   - currentVideo: Video actual configurado
    ///   - bookmarkActor: Actor para acceso seguro a bookmarks
    /// - Returns: true si la reproducción está saludable, false si necesita reinicio
    func checkPlaybackHealth(
        windows: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)],
        currentVideo: VideoFile?,
        bookmarkActor: BookmarkActor
    ) async -> Bool {
        logger.info("🩺 Iniciando verificación de salud de reproducción")
        
        // 1. Verificar que hay un video actual
        guard let currentVideo = currentVideo else {
            logger.warning("⚠️ No hay video actual configurado")
            return false
        }
        
        // 2. Verificar que hay ventanas creadas
        guard !windows.isEmpty else {
            logger.warning("⚠️ No hay ventanas de escritorio creadas")
            return false
        }
        
        // 3. Verificar que el bookmark del video es accesible
        guard let bookmarkData = currentVideo.bookmarkData else {
            logger.error("❌ Video actual no tiene bookmark data: \(currentVideo.name)")
            return false
        }
        
        // 4. Intentar resolver bookmark de forma asíncrona
        do {
            let resolvedURL = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
            
            // Verificar que el archivo existe
            let fileExists = await checkFileExists(at: resolvedURL)
            if !fileExists {
                logger.error("❌ El archivo de video no existe: \(resolvedURL.path)")
                return false
            }
            
            logger.debug("✅ Bookmark resuelto exitosamente: \(currentVideo.name)")
        } catch {
            logger.error("❌ Error resolviendo bookmark: \(error.localizedDescription)")
            return false
        }
        
         // 5. Verificar estado de reproducción de las ventanas (en main thread)
         let windowStates = await MainActor.run {
             return windows.map { window, url in
                 // PHASE 6: Check timeControlStatus FIRST for accurate stall detection
                 let timeControlStatus = window.getTimeControlStatus()
                 let rate = window.getPlaybackRate() ?? 0.0
                 let isVisible = window.isVisible
                 
                 // Determine if playing based on timeControlStatus (more reliable)
                 let isPlaying: Bool
                 if let status = timeControlStatus {
                     // Use timeControlStatus as primary indicator
                     isPlaying = (status == .playing)
                 } else {
                     // Fallback to rate if timeControlStatus unavailable
                     isPlaying = (rate > 0.0)
                 }
                 
                 return (
                     isPlaying: isPlaying,
                     timeControlStatus: timeControlStatus,
                     rate: rate,
                     isVisible: isVisible,
                     url: url.lastPathComponent
                 )
             }
         }
         
         // Analizar estados
         let playingCount = windowStates.filter { $0.isPlaying }.count
         let visibleCount = windowStates.filter { $0.isVisible }.count
         let waitingCount = windowStates.filter { $0.timeControlStatus == .waitingToPlayAtSpecifiedRate }.count
         
         logger.info("📊 Estado ventanas: \(windows.count) total, \(playingCount) reproduciendo, \(visibleCount) visibles, \(waitingCount) esperando")
        
        // Si ninguna ventana está reproduciendo, la salud es negativa
        if playingCount == 0 {
            logger.warning("⚠️ Ninguna ventana está reproduciendo")
            return false
        }
        
        // Si hay menos ventanas reproduciendo que pantallas disponibles
        let screenCount = await MainActor.run { NSScreen.screens.count }
        if playingCount < screenCount {
            logger.warning("⚠️ Reproduciendo en \(playingCount) de \(screenCount) pantallas")
            // Esto no es crítico si al menos una está reproduciendo
        }
        
        logger.info("✅ Verificación de salud completada: reproducción saludable")
        return true
    }
    
    /// Verifica que un archivo existe de forma asíncrona
    /// - Parameter url: URL del archivo a verificar
    /// - Returns: true si el archivo existe y es accesible
    private func checkFileExists(at url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let exists = FileManager.default.fileExists(atPath: url.path)
                continuation.resume(returning: exists)
            }
        }
    }
    
    /// Obtiene información de debug sobre el estado actual de reproducción
    /// - Parameters:
    ///   - windows: Ventanas de escritorio activas
    ///   - currentVideo: Video actual configurado
    /// - Returns: String con información de debug
    func getDebugInfo(
        windows: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)],
        currentVideo: VideoFile?
    ) async -> String {
        var info = "=== PlaybackHealthChecker Debug ===\n"
        info += "Video actual: \(currentVideo?.name ?? "None")\n"
        info += "Ventanas totales: \(windows.count)\n"
        
        if !windows.isEmpty {
            let windowStates = await MainActor.run {
                return windows.enumerated().map { index, item in
                    let rate = item.window.getPlaybackRate() ?? 0.0
                    let isVisible = item.window.isVisible
                    return "  Ventana \(index): rate=\(rate), visible=\(isVisible), video=\(item.accessibleURL.lastPathComponent)"
                }
            }
            
            info += "Estado de ventanas:\n"
            info += windowStates.joined(separator: "\n")
        }
        
        return info
    }
}
