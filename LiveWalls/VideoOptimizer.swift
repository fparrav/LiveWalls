import Foundation
import AVFoundation
import CoreGraphics
import CoreImage

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
                case .high: return "High Quality"
                case .medium: return "Medium Quality" 
                case .balanced: return "Balanced"
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
    
    // MARK: - Black Frame Detection
    
    /// Detecta frames negros o muy oscuros al inicio y final del video
    /// - Parameter asset: El asset de video a analizar
    /// - Returns: Tupla con los tiempos de inicio y fin ajustados (startTime, endTime)
    func detectBlackFrames(in asset: AVURLAsset) async throws -> (startTime: CMTime, endTime: CMTime) {
        let duration = try await asset.load(.duration)
        let originalStartTime = CMTime.zero
        
        // Analizar solo el primer y último segundo
        let analysisRange: Double = 1.0 // 1 segundo
        
        // Encontrar el primer frame no-negro (analizar primer segundo)
        let adjustedStartTime = try await findFirstNonBlackFrame(
            in: asset, 
            searchRange: CMTimeRange(start: originalStartTime, duration: CMTime(seconds: min(analysisRange, duration.seconds), preferredTimescale: duration.timescale))
        )
        
        // Encontrar el último frame no-negro (analizar último segundo)
        let searchEndStart = CMTime(seconds: max(0, duration.seconds - analysisRange), preferredTimescale: duration.timescale)
        let adjustedEndTime = try await findLastNonBlackFrame(
            in: asset,
            searchRange: CMTimeRange(start: searchEndStart, duration: CMTime(seconds: min(analysisRange, duration.seconds - searchEndStart.seconds), preferredTimescale: duration.timescale))
        )
        
        return (adjustedStartTime, adjustedEndTime)
    }
    
    /// Encuentra el primer frame que no es negro en el rango especificado
    private func findFirstNonBlackFrame(in asset: AVURLAsset, searchRange: CMTimeRange) async throws -> CMTime {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        
        let frameInterval: Double = 0.1 // Analizar cada 0.1 segundos
        let searchDuration = searchRange.duration.seconds
        
        for i in stride(from: 0, through: searchDuration, by: frameInterval) {
            let timeToCheck = CMTimeAdd(searchRange.start, CMTime(seconds: i, preferredTimescale: searchRange.start.timescale))
            
            do {
                let (cgImage, _) = try await imageGenerator.image(at: timeToCheck)
                
                if !isBlackOrDarkFrame(cgImage) {
                    return timeToCheck
                }
            } catch {
                // Si no podemos generar la imagen, continuamos
                continue
            }
        }
        
        // Si no encontramos frames no-negros, devolver el inicio original
        return searchRange.start
    }
    
    /// Encuentra el último frame que no es negro en el rango especificado
    private func findLastNonBlackFrame(in asset: AVURLAsset, searchRange: CMTimeRange) async throws -> CMTime {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        
        let frameInterval: Double = 0.1 // Analizar cada 0.1 segundos
        let searchDuration = searchRange.duration.seconds
        let searchEnd = CMTimeAdd(searchRange.start, searchRange.duration)
        
        // Buscar desde el final hacia atrás
        for i in stride(from: searchDuration, through: 0, by: -frameInterval) {
            let timeToCheck = CMTimeAdd(searchRange.start, CMTime(seconds: i, preferredTimescale: searchRange.start.timescale))
            
            do {
                let (cgImage, _) = try await imageGenerator.image(at: timeToCheck)
                
                if !isBlackOrDarkFrame(cgImage) {
                    return timeToCheck
                }
            } catch {
                // Si no podemos generar la imagen, continuamos
                continue
            }
        }
        
        // Si no encontramos frames no-negros, devolver el final original
        return searchEnd
    }
    
    /// Determina si un frame es negro o muy oscuro
    /// - Parameter cgImage: La imagen del frame a analizar
    /// - Returns: true si el frame es considerado negro/oscuro
    internal func isBlackOrDarkFrame(_ cgImage: CGImage) -> Bool {
        // Crear contexto para analizar la imagen
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Analizar una muestra de píxeles para determinar si es oscuro
        let sampleSize = min(width * height, 10000) // Máximo 10,000 píxeles para eficiencia
        let step = max(1, (width * height) / sampleSize)
        
        var totalBrightness: Double = 0
        var sampledPixels = 0
        
        for i in stride(from: 0, to: totalBytes, by: step * bytesPerPixel) {
            let r = Double(pixelData[i])
            let g = Double(pixelData[i + 1])
            let b = Double(pixelData[i + 2])
            
            // Calcular luminancia usando la fórmula estándar
            let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            totalBrightness += luminance
            sampledPixels += 1
        }
        
        let averageBrightness = totalBrightness / Double(sampledPixels)
        
        // Umbral para considerar un frame como "negro/oscuro"
        // 0.05 significa que el frame promedio tiene menos del 5% de brillo
        return averageBrightness < 0.05
    }
    
    /// Crea una composición recortada del video eliminando frames negros
    /// - Parameters:
    ///   - asset: El asset de video original
    ///   - startTime: Tiempo de inicio ajustado
    ///   - endTime: Tiempo de fin ajustado
    /// - Returns: AVMutableComposition con el video recortado
    internal func createTrimmedComposition(from asset: AVURLAsset, startTime: CMTime, endTime: CMTime) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        
        // Crear las pistas de video y audio
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoOptimizerError.compositionCreationFailed
        }
        
        // Obtener las pistas originales
        let assetVideoTracks = try await asset.loadTracks(withMediaType: .video)
        let assetAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        // Calcular el rango de tiempo recortado
        let timeRange = CMTimeRange(start: startTime, end: endTime)
        
        // Insertar pista de video
        if let originalVideoTrack = assetVideoTracks.first {
            try videoTrack.insertTimeRange(timeRange, of: originalVideoTrack, at: CMTime.zero)
        }
        
        // Insertar pista de audio (si existe)
        if let originalAudioTrack = assetAudioTracks.first {
            try audioTrack.insertTimeRange(timeRange, of: originalAudioTrack, at: CMTime.zero)
        }
        
        return composition
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
        
        let finalAsset = asset
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: finalAsset, presetName: settings.quality.preset) else {
            throw VideoOptimizerError.exportSessionCreationFailed
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Store export session for progress tracking
        exportSessions[videoFile.id] = exportSession
        
        // Start export with progress tracking using async/await approach
        // Start export using legacy callback-based API to avoid sendability issues
        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                let status = exportSession.status
                switch status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? VideoOptimizerError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: VideoOptimizerError.exportCancelled)
                default:
                    continuation.resume(throwing: VideoOptimizerError.unexpectedStatus)
                }
                
                // Clean up tracking on main actor
                Task { @MainActor in
                    self.exportSessions.removeValue(forKey: videoFile.id)
                    self.processingProgress.removeValue(forKey: videoFile.id)
                }
            }
            
            // Store session for progress tracking
            exportSessions[videoFile.id] = exportSession
            
            // Start progress tracking
            Task { [weak exportSession] in
                while let session = exportSession, !Task.isCancelled {
                    let progress = session.progress
                    let status = session.status
                    
                    await MainActor.run {
                        self.processingProgress[videoFile.id] = Double(progress)
                    }
                    
                    if status == .completed || status == .failed || status == .cancelled {
                        break
                    }
                    
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }
    
    /// Elimina frames negros del video sin optimización HEVC (mantiene formato original)
    func trimVideoBlackFrames(_ videoFile: VideoFile, to outputURL: URL) async throws -> (processedURL: URL, hadBlackFrames: Bool) {
        
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
        
        let asset = AVURLAsset(url: inputURL)
        
        // Detectar frames negros al inicio y final
        let (trimmedStartTime, trimmedEndTime) = try await detectBlackFrames(in: asset)
        let originalDuration = try await asset.load(.duration)
        
        // Si no hay frames negros, copiar el archivo original
        if trimmedStartTime == CMTime.zero && trimmedEndTime == originalDuration {
            // No hay frames negros, copiar archivo original
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return (outputURL, false)
        }
        
        // Crear composición recortada
        let composition = try await createTrimmedComposition(from: asset, startTime: trimmedStartTime, endTime: trimmedEndTime)
        
        // Exportar con formato original (sin optimización HEVC)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoOptimizerError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = false
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, Bool), Error>) in
            exportSession.exportAsynchronously { [weak exportSession] in
                guard let session = exportSession else {
                    continuation.resume(throwing: VideoOptimizerError.exportCancelled)
                    return
                }
                let status = session.status
                switch status {
                case .completed:
                    continuation.resume(returning: (outputURL, true))
                case .failed:
                    let error = session.error ?? VideoOptimizerError.exportFailed
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: VideoOptimizerError.exportCancelled)
                default:
                    continuation.resume(throwing: VideoOptimizerError.exportFailed)
                }
            }
        }
    }
    
    /// Optimiza video con detección y eliminación de frames negros
    func optimizeVideoWithBlackFrameDetection(_ videoFile: VideoFile, to outputURL: URL, settings: OptimizationSettings = OptimizationSettings(quality: .medium, maintainOriginalFiles: false, autoOptimize: true)) async throws -> URL {
        
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
        
        let asset = AVURLAsset(url: inputURL)
        
        // Detectar y recortar frames negros al inicio y final
        let (trimmedStartTime, trimmedEndTime) = try await detectBlackFrames(in: asset)
        
        // Crear composición recortada si se detectaron frames negros
        let originalDuration = try await asset.load(.duration)
        let finalAsset: AVAsset
        if trimmedStartTime > CMTime.zero || trimmedEndTime < originalDuration {
            finalAsset = try await createTrimmedComposition(from: asset, startTime: trimmedStartTime, endTime: trimmedEndTime)
        } else {
            finalAsset = asset
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(asset: finalAsset, presetName: settings.quality.preset) else {
            throw VideoOptimizerError.exportSessionCreationFailed
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Store export session for progress tracking
        exportSessions[videoFile.id] = exportSession
        
        // Start export with progress tracking using async/await approach
        // Start export using legacy callback-based API to avoid sendability issues
        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                let status = exportSession.status
                switch status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? VideoOptimizerError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: VideoOptimizerError.exportCancelled)
                default:
                    continuation.resume(throwing: VideoOptimizerError.unexpectedStatus)
                }
                
                // Clean up tracking on main actor
                Task { @MainActor in
                    self.exportSessions.removeValue(forKey: videoFile.id)
                    self.processingProgress.removeValue(forKey: videoFile.id)
                }
            }
            
            // Store session for progress tracking
            exportSessions[videoFile.id] = exportSession
            
            // Start progress tracking
            Task { [weak exportSession] in
                while let session = exportSession, !Task.isCancelled {
                    let progress = session.progress
                    let status = session.status
                    
                    await MainActor.run {
                        self.processingProgress[videoFile.id] = Double(progress)
                    }
                    
                    if status == .completed || status == .failed || status == .cancelled {
                        break
                    }
                    
                    try? await Task.sleep(for: .milliseconds(100))
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
    case compositionCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in file"
        case .noFormatDescription:
            return "Could not get video format information"
        case .noBookmarkData:
            return "No security bookmark data for file"
        case .securityScopedAccessFailed:
            return "Could not access video file"
        case .exportSessionCreationFailed:
            return "Could not create export session"
        case .exportFailed:
            return "Error during video optimization"
        case .exportCancelled:
            return "Optimization cancelled by user"
        case .unexpectedStatus:
            return "Unexpected status during optimization"
        case .alreadyOptimized:
            return "Video is already optimized with HEVC"
        case .compositionCreationFailed:
            return "Could not create video composition to trim black frames"
        }
    }
}
