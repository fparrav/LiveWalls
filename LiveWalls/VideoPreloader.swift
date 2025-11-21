import Foundation
import AVFoundation
import os.log

/// Manages preloading of video assets for smooth transitions
/// Caches fully-loaded AVAssets to eliminate window creation delays
@MainActor
class VideoPreloader {
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "VideoPreloader")
    
    // Cache de AVAsset precargado (AVAssets PUEDEN compartirse entre múltiples AVPlayerItems)
    private struct PreloadedAsset {
        let url: URL
        let asset: AVURLAsset
        let isPlayable: Bool
        let duration: CMTime
        let naturalSize: CGSize
        let loadTimestamp: Date
    }
    
    private var cachedAsset: PreloadedAsset?
    
    /// Preloads a video by fully loading the AVAsset and caching it
    /// The cached AVAsset can be safely shared between multiple AVPlayerItems
    /// - Parameter videoURL: URL of the video to preload
    func preload(videoURL: URL) async {
        logger.info("🔄 Precargando AVAsset completo: \(videoURL.lastPathComponent)")
        
        // Crear AVAsset que será cacheado
        let asset = AVURLAsset(url: videoURL)
        
        do {
            // Cargar TODAS las propiedades para asegurar asset completamente listo
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
            
            // Cachear el AVAsset COMPLETO para reuso
            cachedAsset = PreloadedAsset(
                url: videoURL,
                asset: asset,
                isPlayable: isPlayable,
                duration: duration,
                naturalSize: naturalSize,
                loadTimestamp: Date()
            )
            
            logger.info("✅ AVAsset precargado y cacheado: \(videoURL.lastPathComponent) - \(String(format: "%.1fs", duration.seconds))")
        } catch {
            logger.error("❌ Falló precarga: \(error.localizedDescription)")
        }
    }
    
    /// Returns the preloaded AVAsset if available and not expired
    /// - Parameter videoURL: URL of the video
    /// - Returns: Cached AVAsset if available, nil otherwise
    func getPreloadedAsset(for videoURL: URL) -> AVURLAsset? {
        guard let preloaded = cachedAsset, preloaded.url == videoURL else {
            return nil
        }
        
        // Invalidar cache después de 5 minutos
        let cacheAge = Date().timeIntervalSince(preloaded.loadTimestamp)
        if cacheAge > 300 {
            logger.debug("🕒 Cache expirado (> 5min), invalidando")
            clearCache()
            return nil
        }
        
        logger.info("🎯 Cache HIT - retornando AVAsset precargado para \(videoURL.lastPathComponent)")
        return preloaded.asset
    }
    
    /// Checks if an asset is cached for given URL
    /// - Parameter videoURL: URL of the video
    /// - Returns: true if asset is cached and not expired
    func isWarmedUp(for videoURL: URL) -> Bool {
        return getPreloadedAsset(for: videoURL) != nil
    }
    
    /// Legacy method - DEPRECATED: Use getPreloadedAsset() instead
    @available(*, deprecated, message: "Use getPreloadedAsset() instead", renamed: "getPreloadedAsset")
    func getCachedAsset(for videoURL: URL) -> AVAsset? {
        return getPreloadedAsset(for: videoURL)
    }
    
    /// Clears the preload cache
    func clearCache() {
        cachedAsset = nil
        logger.debug("🧹 Cache de precarga limpiado")
    }
}
