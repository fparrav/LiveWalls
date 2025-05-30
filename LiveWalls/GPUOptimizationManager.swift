import Foundation
import AVFoundation
import Metal
import MetalKit

class GPUOptimizationManager {
    static let shared = GPUOptimizationManager()
    
    private var metalDevice: MTLDevice?
    private var isMetalSupported: Bool = false
    
    private init() {
        setupMetal()
    }
    
    private func setupMetal() {
        // Verificar si Metal está disponible
        if let device = MTLCreateSystemDefaultDevice() {
            metalDevice = device
            isMetalSupported = true
            print("✅ Metal GPU acceleration disponible: \(device.name)")
        } else {
            print("❌ Metal GPU acceleration no disponible")
            isMetalSupported = false
        }
    }
    
    /// Configura un AVPlayerItem para máximo rendimiento con GPU
    func optimizePlayerItem(_ playerItem: AVPlayerItem) {
        guard isMetalSupported else { return }
        
        // Configuraciones específicas para aceleración por GPU
        if #available(macOS 10.15, *) {
            // Buffer optimizado para GPU
            playerItem.preferredForwardBufferDuration = 3.0
            
            // Configurar para usar decodificación por hardware
            playerItem.videoComposition = createOptimizedVideoComposition(for: playerItem)
        }
    }
    
    /// Crea una composición de video optimizada para GPU
    private func createOptimizedVideoComposition(for playerItem: AVPlayerItem) -> AVVideoComposition? {
        guard let videoTrack = playerItem.asset.tracks(withMediaType: .video).first else {
            return nil
        }
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30) // 30 FPS
        videoComposition.renderSize = videoTrack.naturalSize
        
        // Usar renderizado por GPU cuando sea posible
        if #available(macOS 10.15, *) {
            videoComposition.sourceTrackIDForFrameTiming = videoTrack.trackID
        }
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: playerItem.asset.duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        instruction.layerInstructions = [layerInstruction]
        
        videoComposition.instructions = [instruction]
        
        return videoComposition
    }
    
    /// Configuraciones recomendadas según el hardware
    func getRecommendedSettings() -> VideoSettings {
        guard isMetalSupported, let device = metalDevice else {
            return VideoSettings.lowPerformance
        }
        
        // Detectar capacidades del GPU
        let isIntegratedGPU = device.isLowPower
        let hasUnifiedMemory = device.hasUnifiedMemory
        
        if isIntegratedGPU {
            // GPU integrado (como Intel Iris o Apple Silicon integrado)
            return VideoSettings.mediumPerformance
        } else {
            // GPU dedicado
            return VideoSettings.highPerformance
        }
    }
    
    /// Información del sistema GPU
    func getGPUInfo() -> GPUInfo {
        guard let device = metalDevice else {
            return GPUInfo(name: "No disponible", isSupported: false, isLowPower: true)
        }
        
        return GPUInfo(
            name: device.name,
            isSupported: isMetalSupported,
            isLowPower: device.isLowPower
        )
    }
}

// MARK: - Estructuras de configuración

struct VideoSettings {
    let maxResolution: CGSize
    let maxBitrate: Double
    let bufferDuration: Double
    let useHardwareDecoding: Bool
    
    static let lowPerformance = VideoSettings(
        maxResolution: CGSize(width: 1920, height: 1080),
        maxBitrate: 2_000_000, // 2 Mbps
        bufferDuration: 2.0,
        useHardwareDecoding: false
    )
    
    static let mediumPerformance = VideoSettings(
        maxResolution: CGSize(width: 2560, height: 1440),
        maxBitrate: 8_000_000, // 8 Mbps
        bufferDuration: 3.0,
        useHardwareDecoding: true
    )
    
    static let highPerformance = VideoSettings(
        maxResolution: CGSize(width: 3840, height: 2160),
        maxBitrate: 20_000_000, // 20 Mbps
        bufferDuration: 5.0,
        useHardwareDecoding: true
    )
}

struct GPUInfo {
    let name: String
    let isSupported: Bool
    let isLowPower: Bool
    
    var description: String {
        var info = "GPU: \(name)"
        info += isSupported ? " (Metal ✅)" : " (Metal ❌)"
        info += isLowPower ? " [Integrado]" : " [Dedicado]"
        return info
    }
}
