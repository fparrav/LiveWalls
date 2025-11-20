import Foundation
import AVFoundation
import os.log

/// Manages preloading of video assets for smooth transitions
/// ARQUITECTURA CORREGIDA: Cachea metadata y "calienta" el archivo en lugar de compartir AVAsset
@MainActor
class VideoPreloader {
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "VideoPreloader")
    
    // Cache de metadata precargada (NO el AVAsset, que no puede compartirse)
    private struct PreloadedMetadata {
        let url: URL
        let isPlayable: Bool
        let duration: CMTime
        let naturalSize: CGSize
        let loadTimestamp: Date
    }
    
    private var cachedMetadata: PreloadedMetadata?
    
    /// Preloads a video by "warming up" filesystem cache and loading metadata
    /// NOTA: NO cachea AVAsset porque no puede compartirse entre múltiples AVPlayerItems
    /// - Parameter videoURL: URL of the video to preload
    func preload(videoURL: URL) async {
        logger.info("🔄 Precargando metadata de video: \(videoURL.lastPathComponent)")
        
        // Crear asset temporal SOLO para calentar el filesystem y cargar metadata
        let asset = AVURLAsset(url: videoURL)
        
        do {
            // Cargar propiedades esenciales (esto "calienta" el filesystem cache del OS)
            let (isPlayable, tracks, duration) = try await asset.load(.isPlayable, .tracks, .duration)
            
            guard isPlayable, !tracks.isEmpty else {
                logger.warning("⚠️ Video no reproducible o sin pistas: \(videoURL.lastPathComponent)")
                return
            }
            
            // Obtener naturalSize del primer video track
            var naturalSize: CGSize = .zero
            for track in tracks where track.mediaType == .video {
                naturalSize = try await track.load(.naturalSize)
                break
            }
            
            // Cachear SOLO la metadata, no el asset
            cachedMetadata = PreloadedMetadata(
                url: videoURL,
                isPlayable: isPlayable,
                duration: duration,
                naturalSize: naturalSize,
                loadTimestamp: Date()
            )
            
            logger.info("✅ Metadata precargada: \(videoURL.lastPathComponent) - \(String(format: "%.1fs", duration.seconds))")
        } catch {
            logger.error("❌ Falló precarga: \(error.localizedDescription)")
        }
    }
    
    /// Checks if metadata is cached for given URL (indicates warm filesystem cache)
    /// - Parameter videoURL: URL of the video
    /// - Returns: true if metadata is cached (filesystem likely warm)
    func isWarmedUp(for videoURL: URL) -> Bool {
        guard let metadata = cachedMetadata, metadata.url == videoURL else {
            return false
        }
        
        // Invalidar cache después de 5 minutos
        let cacheAge = Date().timeIntervalSince(metadata.loadTimestamp)
        if cacheAge > 300 {
            logger.debug("🕒 Cache expirado (> 5min), invalidando")
            clearCache()
            return false
        }
        
        return true
    }
    
    /// Legacy method - DEPRECATED: No longer returns AVAsset to prevent sharing
    /// Use isWarmedUp() instead to check if filesystem is warm
    @available(*, deprecated, message: "Use isWarmedUp() instead - AVAssets cannot be shared")
    func getCachedAsset(for videoURL: URL) -> AVAsset? {
        return nil  // Siempre retorna nil para forzar creación de asset fresco
    }
    
    /// Clears the preload cache
    func clearCache() {
        cachedMetadata = nil
        logger.debug("🧹 Cache de precarga limpiado")
    }
}
