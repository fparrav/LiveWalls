import Foundation
import AVFoundation
import os.log

/// Manages preloading of video assets for smooth transitions
@MainActor
class VideoPreloader {
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "VideoPreloader")
    
    // Cache storage: only one video at a time
    private var cachedAsset: AVAsset?
    private var cachedVideoURL: URL?
    
    /// Preloads a video asset asynchronously
    /// - Parameter videoURL: URL of the video to preload
    func preload(videoURL: URL) async {
        logger.info("🔄 Preloading video: \(videoURL.lastPathComponent)")
        
        let asset = AVURLAsset(url: videoURL)
        
        do {
            // Load essential properties
            let (isPlayable, tracks) = try await asset.load(.isPlayable, .tracks)
            
            guard isPlayable, !tracks.isEmpty else {
                logger.warning("⚠️ Video not playable or has no tracks: \(videoURL.lastPathComponent)")
                return
            }
            
            // Cache the asset
            cachedAsset = asset
            cachedVideoURL = videoURL
            
            logger.info("✅ Video preloaded: \(videoURL.lastPathComponent)")
        } catch {
            logger.error("❌ Failed to preload video: \(error.localizedDescription)")
        }
    }
    
    /// Retrieves cached asset if available
    /// - Parameter videoURL: URL of the video
    /// - Returns: Cached AVAsset or nil if not in cache
    func getCachedAsset(for videoURL: URL) -> AVAsset? {
        guard cachedVideoURL == videoURL else {
            logger.debug("🔍 Cache miss for: \(videoURL.lastPathComponent)")
            return nil
        }
        
        logger.info("✅ Cache hit for: \(videoURL.lastPathComponent)")
        return cachedAsset
    }
    
    /// Clears the preload cache
    func clearCache() {
        cachedAsset = nil
        cachedVideoURL = nil
        logger.debug("🧹 Preload cache cleared")
    }
}
