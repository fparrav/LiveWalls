import Foundation
import AVFoundation

@MainActor
class VideoOptimizer: ObservableObject {
    @Published var processingProgress: [UUID: Double] = [:]
    @Published var isProcessing = false
    
    private var exportSessions: [UUID: AVAssetExportSession] = [:]
    private let processingQueue = DispatchQueue(label: "video.optimization", qos: .userInitiated)
    
    // HEVC optimization settings
    struct OptimizationSettings {
        let quality: VideoQuality
        let maintainOriginalFiles: Bool
        let autoOptimize: Bool
        
        enum VideoQuality: String, CaseIterable {
            case high = "AVAssetExportPresetHEVCHighestQuality"
            case medium = "AVAssetExportPreset1920x1080"
            case balanced = "AVAssetExportPreset1280x720"
            
            var preset: String {
                return self.rawValue
            }
            
            var displayName: String {
                switch self {
                case .high: return "Alta Calidad"
                case .medium: return "Calidad Media" 
                case .balanced: return "Balanceada"
                }
            }
        }
    }
    
    // Default settings
    var settings = OptimizationSettings(
        quality: .medium,
        maintainOriginalFiles: false,
        autoOptimize: true
    )
    
    // MARK: - Video Analysis
    
    func analyzeVideo(at url: URL) async throws -> VideoAnalysis {
        let asset = AVURLAsset(url: url)
        
        // Get file size
        let fileSize = try getFileSize(at: url)
        
        // Detect codec
        let codec = try await detectVideoCodec(asset: asset)
        
        // Get video properties
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        let videoTrack = tracks.first { $0.mediaType == .video }
        
        var resolution: CGSize = .zero
        if let videoTrack = videoTrack {
            let naturalSize = try await videoTrack.load(.naturalSize)
            resolution = naturalSize
        }
        
        return VideoAnalysis(
            codec: codec,
            fileSize: fileSize,
            duration: duration.seconds,
            resolution: resolution,
            needsOptimization: codec.lowercased() != "hevc"
        )
    }
    
    func detectVideoCodec(asset: AVURLAsset) async throws -> String {
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw VideoOptimizerError.noVideoTrack
        }
        
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw VideoOptimizerError.noFormatDescription
        }
        
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription)
        
        switch mediaSubType {
        case kCMVideoCodecType_HEVC:
            return "hevc"
        case kCMVideoCodecType_H264:
            return "h264"
        case kCMVideoCodecType_VP9:
            return "vp9"
        case kCMVideoCodecType_AV1:
            return "av1"
        default:
            return "unknown"
        }
    }
    
    // MARK: - Video Optimization
    
    func optimizeVideo(_ videoFile: VideoFile, to outputURL: URL, settings: OptimizationSettings = OptimizationSettings(quality: .medium, maintainOriginalFiles: false, autoOptimize: true)) async throws -> URL {
        
        guard let bookmarkData = videoFile.bookmarkData else {
            throw VideoOptimizerError.noBookmarkData
        }
        
        // Resolve security-scoped bookmark
        var isStale = false
        let inputURL = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
        
        guard inputURL.startAccessingSecurityScopedResource() else {
            throw VideoOptimizerError.securityScopedAccessFailed
        }
        
        defer {
            inputURL.stopAccessingSecurityScopedResource()
        }
        
        // Analyze video first
        let analysis = try await analyzeVideo(at: inputURL)
        
        // Skip if already HEVC
        if !analysis.needsOptimization {
            throw VideoOptimizerError.alreadyOptimized
        }
        
        let asset = AVURLAsset(url: inputURL)
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: settings.quality.preset) else {
            throw VideoOptimizerError.exportSessionCreationFailed
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Store export session for progress tracking
        exportSessions[videoFile.id] = exportSession
        
        // Start export with progress tracking
        return try await withCheckedThrowingContinuation { continuation in
            // Start progress tracking
            let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    self.processingProgress[videoFile.id] = Double(exportSession.progress)
                }
            }
            
            exportSession.exportAsynchronously {
                timer.invalidate()
                
                Task { @MainActor in
                    self.exportSessions.removeValue(forKey: videoFile.id)
                    self.processingProgress.removeValue(forKey: videoFile.id)
                }
                
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? VideoOptimizerError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: VideoOptimizerError.exportCancelled)
                default:
                    continuation.resume(throwing: VideoOptimizerError.unexpectedStatus)
                }
            }
        }
    }
    
    // MARK: - Utility Functions
    
    private func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    func cancelOptimization(for videoFile: VideoFile) {
        if let exportSession = exportSessions[videoFile.id] {
            exportSession.cancelExport()
            exportSessions.removeValue(forKey: videoFile.id)
            processingProgress.removeValue(forKey: videoFile.id)
        }
    }
    
    func generateOptimizedURL(for originalURL: URL) -> URL {
        let filename = originalURL.deletingPathExtension().lastPathComponent
        let optimizedFilename = "\(filename)_hevc.mp4"
        return originalURL.deletingLastPathComponent().appendingPathComponent(optimizedFilename)
    }
}

// MARK: - Supporting Types

struct VideoAnalysis {
    let codec: String
    let fileSize: Int64
    let duration: Double
    let resolution: CGSize
    let needsOptimization: Bool
}

enum VideoOptimizerError: LocalizedError {
    case noVideoTrack
    case noFormatDescription
    case noBookmarkData
    case securityScopedAccessFailed
    case exportSessionCreationFailed
    case exportFailed
    case exportCancelled
    case unexpectedStatus
    case alreadyOptimized
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No se encontró pista de video en el archivo"
        case .noFormatDescription:
            return "No se pudo obtener información del formato de video"
        case .noBookmarkData:
            return "No hay datos de marcador de seguridad para el archivo"
        case .securityScopedAccessFailed:
            return "No se pudo acceder al archivo de video"
        case .exportSessionCreationFailed:
            return "No se pudo crear sesión de exportación"
        case .exportFailed:
            return "Error durante la optimización del video"
        case .exportCancelled:
            return "Optimización cancelada por el usuario"
        case .unexpectedStatus:
            return "Estado inesperado durante la optimización"
        case .alreadyOptimized:
            return "El video ya está optimizado con HEVC"
        }
    }
}