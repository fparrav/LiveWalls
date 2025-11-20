import Foundation
import AppKit
import Combine
import AVFoundation
import os.log
import ImageIO
import UniformTypeIdentifiers

// Asegurarse de que Logger esté disponible
#if canImport(os)
import os
#endif

// Specific logger for memory debugging
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

/// Main video wallpaper manager for LiveWalls
/// Handles playback, changing and configuration of videos as desktop backgrounds
@MainActor
class WallpaperManager: NSObject, ObservableObject, NSWindowDelegate {
    
    // MARK: - Published Properties (MUST be declared BEFORE init)
    @Published var videoFiles: [VideoFile] = []
    @Published var currentVideo: VideoFile? = nil
    @Published var isPlayingWallpaper = false
    @Published var isAutoChangeEnabled = false
    @Published var autoChangeInterval: TimeInterval = 10 * 60 // 10 minutes default
    
    // MARK: - Private Properties
    private let appLogger = Logger(subsystem: "com.livewalls.app", category: "WallpaperManager")
    private var desktopVideoInstances: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)] = []
    private let notificationManager: NotificationManager
    private var currentStaticWallpaperURL: URL?
    private var staticFrameUpdateTimer: Timer?
    
    // MARK: - New Fullscreen and Timer Management
    private let fullscreenDetector = FullscreenDetector()
    private let timerManager = WallpaperTimerManager.shared
    private let transitionManager = TransitionManager()
    private var isWallpaperPausedForFullscreen = false
    
    // MARK: - Transition Settings
    private let isTransitionEnabledKey = "IsTransitionEnabled"
    private let transitionDurationKey = "TransitionDuration"
    private let transitionTypeKey = "TransitionType"
    private var isTransitionEnabled = true
    private var transitionDuration: TimeInterval = 1.0  // Reducido de 2.0s a 1.0s para transiciones más rápidas
    private var transitionType: TransitionManager.TransitionType = .crossfade
    
    // FASE 5.3: Flag para prevenir transiciones concurrentes
    private var isTransitioning = false
    
    // MARK: - Background color windows for transitions
    private var backgroundColorWindows: [NSWindow] = []
    
    // MARK: - Variables for window destruction synchronization
    var pendingDestroyCompletion: (() -> Void)? = nil
    var pendingWindowClosures: Set<NSWindow> = []
    var closedWindowsCount: Int = 0
    
    // MARK: - UserDefaults and configuration
    private let resourceReleaseDelay: TimeInterval = 0.1
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Security-Scoped Resource Tracking
    let bookmarkActor = BookmarkActor()
    let persistenceActor = PersistenceActor()
    private let systemReadinessObserver = SystemReadinessObserver()
    private let startupCoordinator = StartupCoordinator()
    private let playbackHealthChecker = PlaybackHealthChecker()
    private let windowCreationCoordinator = WindowCreationCoordinator()
     private let scheduledHealthCheckManager = ScheduledHealthCheckManager()
     private let videoPreloader = VideoPreloader()
     private var activeSecurityScopedURLs: Set<String> = []
     private let resourceTrackingQueue = DispatchQueue(label: "security.resources", attributes: .concurrent)
    
    // MARK: - Synchronization to prevent crashes
    private let wallpaperOperationQueue = DispatchQueue(label: "com.livewalls.wallpaperQueue", attributes: .concurrent)
    private let wallpaperOperationActor = WallpaperOperationActor()
    private var isChangingVideo = false
    private var isCleaningUp = false
    private var autoStartScheduled = false
    
    
    // Actor to serialize wallpaper operations
    private actor WallpaperOperationActor {
        func withExclusiveAccess<T>(@_implicitSelfCapture operation: () async throws -> T) async rethrows -> T {
            return try await operation()
        }
    }
    
    // MARK: - Initialization
    override init() {
        self.notificationManager = NotificationManager.shared
        super.init()
        
        appLogger.info("\(NSLocalizedString("initializing_wallpaper_manager", comment: "Initializing WallpaperManager"), privacy: .public)")
        
        // Cargar configuración en background usando PersistenceActor (NO bloquear init)
        Task.detached { [weak self] in
            guard let self else { return }
            await self.loadDataInBackground()
        }
        
        loadTransitionSettings()
        setupScreenChangeNotifications()
        setupWorkspaceNotifications()
        setupTerminationHandling()
        setupFullscreenDetection()
        setupAppActivationNotifications()
        
        // Intentar auto‑inicio cuando el estado esté listo (sin depender de delays fijos)
        attemptAutoStart()
        
        appLogger.info("\(NSLocalizedString("wallpaper_manager_initialized", comment: "WallpaperManager initialized"), privacy: .public)")
    }
    
    deinit {
        MainActor.assumeIsolated { [self] in
            appLogger.info("\(NSLocalizedString("deinitializing_wallpaper_manager", comment: "Deinitializing WallpaperManager"), privacy: .public)")
            timerManager.stopTimer()
            cleanupAllResources()
        }
    }

    // MARK: - Startup Helpers
    
    /// Intenta iniciar la reproducción automáticamente cuando la configuración y el sistema estén listos
    /// Usa StartupCoordinator para evitar bloqueos del main thread con backoff exponencial
    private func attemptAutoStart() {
        guard UserDefaults.standard.bool(forKey: "AutoStartWallpaper") else { return }
        guard !autoStartScheduled else { return }
        
        autoStartScheduled = true
        appLogger.info("🚀 Iniciando coordinación de startup con backoff exponencial")
        
        // Lanzar coordinación de startup sin bloquear
        Task { [weak self] in
            guard let self else { return }
            
            // Coordinar startup con backoff exponencial (máximo 5 reintentos)
            let success = await self.startupCoordinator.coordinateStartup(
                hasVideo: { [weak self] in
                    guard let self else { return false }
                    return self.currentVideo != nil && !self.videoFiles.isEmpty
                },
                hasScreens: { [weak self] in
                    guard let self else { return false }
                    return await self.systemReadinessObserver.waitUntilReady(timeout: 5.0)
                },
                maxRetries: 5,
                startAction: { [weak self] in
                    guard let self else { return }
                    self.startWallpaperSafe()
                }
            )
            
            if success {
                await MainActor.run {
                    self.appLogger.info("✅ AutoStart completado exitosamente")
                }
            } else {
                await MainActor.run {
                    self.appLogger.warning("⚠️ AutoStart: condiciones no cumplidas después de reintentos")
                }
            }
        }
    }
    

    
    // MARK: - Video Management
    
    // MARK: - Duplicate Detection
    
    /// Enum for duplicate handling options
    enum DuplicateHandling: CaseIterable {
        case skip
        case replace
        case keepBoth
        
        var localizedString: String {
            switch self {
            case .skip:
                return NSLocalizedString("duplicate_action_skip", comment: "Skip duplicate video")
            case .replace:
                return NSLocalizedString("duplicate_action_replace", comment: "Replace existing video")
            case .keepBoth:
                return NSLocalizedString("duplicate_action_keep_both", comment: "Keep both videos")
            }
        }
    }
    
    /// Checks if a URL represents a duplicate video based on file path
    /// - Parameter url: URL to check
    /// - Returns: true if a video with the same path already exists
    private func isDuplicateByURL(_ url: URL) -> Bool {
        let normalizedPath = url.standardizedFileURL.path
        return videoFiles.contains { videoFile in
            let existingPath = videoFile.url.standardizedFileURL.path
            return existingPath == normalizedPath
        }
    }
    
    /// Verifica si una URL representa un video duplicado basado en bookmark data
    /// - Parameter url: URL to check
    /// - Returns: true si ya existe un video con bookmark data equivalente
    private func isDuplicateByBookmark(_ bookmarkData: Data) -> Bool {
        return videoFiles.contains { videoFile in
            guard let existingBookmarkData = videoFile.bookmarkData else { return false }
            return existingBookmarkData == bookmarkData
        }
    }
    
    /// Encuentra un video duplicado existente para la URL dada
    /// - Parameter url: URL del nuevo video
    /// - Returns: VideoFile existente que es duplicado, o nil si no hay duplicados
    private func findDuplicateVideo(for url: URL) -> VideoFile? {
        let normalizedPath = url.standardizedFileURL.path
        return videoFiles.first { videoFile in
            let existingPath = videoFile.url.standardizedFileURL.path
            return existingPath == normalizedPath
        }
    }
    
    /// Muestra un diálogo para manejar un video duplicado
    /// - Parameters:
    ///   - originalVideo: VideoFile existente en la biblioteca
    ///   - newURL: URL del nuevo video que es duplicado
    /// - Returns: Acción elegida por el usuario
    private func showDuplicateDialog(originalVideo: VideoFile, newURL: URL) -> DuplicateHandling {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("duplicate_video_title", comment: "Duplicate video detected")
        alert.informativeText = String(format: NSLocalizedString("duplicate_video_message", comment: "Duplicate video message"), newURL.lastPathComponent, originalVideo.name)
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        
        // Agregar botones en orden inverso (NSAlert los muestra de derecha a izquierda)
        alert.addButton(withTitle: DuplicateHandling.keepBoth.localizedString)
        alert.addButton(withTitle: DuplicateHandling.replace.localizedString)
        alert.addButton(withTitle: DuplicateHandling.skip.localizedString)
        
        let response = alert.runModal()
        
        // NSAlert.ButtonType.alertFirstButtonReturn corresponde al último botón agregado
        switch response {
        case .alertFirstButtonReturn:
            return .keepBoth
        case .alertSecondButtonReturn:
            return .replace
        case .alertThirdButtonReturn:
            return .skip
        default:
            return .skip // Default fallback
        }
    }
    
    /// Genera un nombre único para un video duplicado
    /// - Parameter originalName: Nombre original del video
    /// - Returns: Nuevo nombre único
    private func generateUniqueName(for originalName: String) -> String {
        let baseName = originalName
        var counter = 2
        var candidateName = "\(baseName) (\(counter))"
        
        while videoFiles.contains(where: { $0.name == candidateName }) {
            counter += 1
            candidateName = "\(baseName) (\(counter))"
        }
        
        return candidateName
    }
    
    /// Agrega archivos de video a la lista de wallpapers disponibles
    /// - Parameter urls: URLs de los archivos de video a agregar
    func addVideoFiles(urls: [URL]) async {
        appLogger.info("\(String(format: NSLocalizedString("adding_video_files", comment: "Adding video files"), urls.count), privacy: .public)")
        
        var addedCount = 0
        var skippedCount = 0
        var replacedCount = 0
        
        for url in urls {
            // Verificar si es un duplicado antes de procesar
            if let existingVideo = findDuplicateVideo(for: url) {
                appLogger.info("🔍 Duplicado detectado: \(url.lastPathComponent) ya existe como '\(existingVideo.name)'")
                
                // Verificar si hay una preferencia guardada
                let duplicateHandlingRawValue = UserDefaults.standard.string(forKey: "DuplicateHandlingPreference") ?? "askAlways"
                let userChoice: DuplicateHandling
                
                if duplicateHandlingRawValue == "askAlways" {
                    // Mostrar diálogo para manejar duplicado
                    userChoice = showDuplicateDialog(originalVideo: existingVideo, newURL: url)
                } else {
                    // Usar preferencia guardada
                    switch duplicateHandlingRawValue {
                    case "skip":
                        userChoice = .skip
                    case "replace":
                        userChoice = .replace
                    case "keepBoth":
                        userChoice = .keepBoth
                    default:
                        userChoice = .skip
                    }
                    appLogger.info("🔧 Usando preferencia guardada: \(duplicateHandlingRawValue)")
                }
                
                switch userChoice {
                case .skip:
                    appLogger.info("⏭️ Saltando duplicado: \(url.lastPathComponent)")
                    skippedCount += 1
                    continue
                    
                case .replace:
                    appLogger.info("🔄 Reemplazando existente: \(existingVideo.name)")
                    // Remover el video existente y continuar con el procesamiento normal
                    self.videoFiles.removeAll { $0.id == existingVideo.id }
                    replacedCount += 1
                    
                case .keepBoth:
                    appLogger.info("📂 Manteniendo ambos: \(url.lastPathComponent)")
                    // Continuar con procesamiento normal pero con nombre único
                    break
                }
            }
            
            // Verificar si ya tenemos acceso al archivo
            var accessGranted = false
            
            // Intentar iniciar acceso security-scoped si no está activo
            if !url.startAccessingSecurityScopedResource() {
                appLogger.warning("\(String(format: NSLocalizedString("could_not_start_security_scoped_access", comment: "Could not start security scoped access"), url.lastPathComponent), privacy: .public)")
            } else {
                accessGranted = true
            }
            
            do {
                // Verificar que el archivo existe y es accesible
                guard try url.checkResourceIsReachable() else {
                    appLogger.error("\(String(format: NSLocalizedString("file_not_accessible", comment: "File not accessible"), url.lastPathComponent), privacy: .public)")
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                    continue
                }
                
                // Crear bookmark security-scoped
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                // Generar miniatura del video
                let thumbnail = await generateThumbnail(for: url)
                
                // Determinar el nombre del video (único si es necesario)
                var videoName = url.deletingPathExtension().lastPathComponent
                if let existingVideo = findDuplicateVideo(for: url),
                   videoFiles.contains(where: { $0.id == existingVideo.id }) {
                    // Solo si el video existente aún está en la lista (no fue reemplazado)
                    videoName = generateUniqueName(for: videoName)
                }
                
                let videoFile = VideoFile(
                    url: url,
                    name: videoName,
                    thumbnailData: thumbnail,
                    bookmarkData: bookmarkData
                )
                
                let countBefore = self.videoFiles.count
                self.videoFiles.append(videoFile)
                let countAfter = self.videoFiles.count
                
                // Si no hay video activo y este es el primer video, establecerlo como activo
                if self.currentVideo == nil && countBefore == 0 {
                    self.currentVideo = videoFile
                    await self.persistenceActor.saveCurrentVideo(videoFile)
                    self.appLogger.info("✨ Primer video agregado, establecido como activo: \(videoFile.name)")
                }
                
                self.saveVideos()
                self.appLogger.info("\(String(format: NSLocalizedString("video_added", comment: "Video added"), videoFile.name), privacy: .public)")
                self.appLogger.info("\(String(format: NSLocalizedString("videos_count_updated", comment: "Videos count updated"), countBefore, countAfter), privacy: .public)")
                
                // Additional debug to verify SwiftUI receives the update
                print(String(format: NSLocalizedString("videofiles_updated_debug", comment: "VideoFiles updated debug"), self.videoFiles.count))
                print(String(format: NSLocalizedString("names_debug", comment: "Names debug"), self.videoFiles.map { $0.name }.joined(separator: ", ")))
                
                addedCount += 1
                
                // Detener acceso temporal ya que tenemos el bookmark
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
                
            } catch {
                appLogger.error("\(String(format: NSLocalizedString("error_processing_file", comment: "Error processing file"), url.lastPathComponent, error.localizedDescription), privacy: .public)")
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        
        // Show import summary
        var summaryMessage = ""
        if addedCount > 0 {
            summaryMessage += String(format: NSLocalizedString("import_summary_added", comment: "Import summary added"), addedCount)
        }
        if skippedCount > 0 {
            if !summaryMessage.isEmpty { summaryMessage += "\n" }
            summaryMessage += String(format: NSLocalizedString("import_summary_skipped", comment: "Import summary skipped"), skippedCount)
        }
        if replacedCount > 0 {
            if !summaryMessage.isEmpty { summaryMessage += "\n" }
            summaryMessage += String(format: NSLocalizedString("import_summary_replaced", comment: "Import summary replaced"), replacedCount)
        }
        
        if !summaryMessage.isEmpty {
            self.notificationManager.showMessage(title: NSLocalizedString("import_completed_title", comment: "Import completed"), message: summaryMessage)
            self.appLogger.info("📊 Import summary: \(summaryMessage)")
        }
    }
    
    /// Generates a thumbnail for the video
    /// - Parameter url: URL of the video file
    /// - Returns: Image data in PNG format or nil if it fails
    private func generateThumbnail(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 80)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: CMTime.zero, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 80))
            return nsImage.tiffRepresentation
        } catch {
            appLogger.warning("\(String(format: NSLocalizedString("could_not_generate_thumbnail", comment: "Could not generate thumbnail"), url.lastPathComponent), privacy: .public)")
            return nil
        }
    }
    
    /// Generates a high resolution frame from the video to use as static wallpaper
    /// - Parameter url: URL of the video file
    /// - Parameter timeOffset: Specific video time (nil for random time)
    /// - Returns: URL of temporary image file or nil if it fails
    private func generateStaticWallpaperFrame(for url: URL, timeOffset: CMTime? = nil) async -> URL? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Use main screen resolution for better quality
        if let mainScreen = NSScreen.main {
            let screenSize = mainScreen.frame.size
            let scale = mainScreen.backingScaleFactor
            imageGenerator.maximumSize = CGSize(
                width: screenSize.width * scale,
                height: screenSize.height * scale
            )
        }
        
        // Generate high quality image
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        
        do {
            // Determine time of frame to extract
            let time: CMTime
            if let specificTime = timeOffset {
                time = specificTime
            } else {
                // Get video duration and generate random time
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                if durationSeconds > 0 {
                    let randomSeconds = Double.random(in: 0...(durationSeconds * 0.8)) // Avoid the end
                    time = CMTime(seconds: randomSeconds, preferredTimescale: 600)
                } else {
                    time = CMTime(seconds: 1.0, preferredTimescale: 600)
                }
            }
            
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            
            // Create NSImage and convert to data
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            ))
            
            guard let imageData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: imageData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                appLogger.error("❌ Error converting image to PNG")
                return nil
            }
            
            // Try using Application Support directory first
            guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                appLogger.error("❌ Could not get Application Support directory")
                return nil
            }
            
            let livewallsDir = appSupportURL.appendingPathComponent("LiveWalls")
            var finalImageURL: URL
            
            // Create directory and file with robust error handling
            do {
                // Ensure the directory exists
                if !FileManager.default.fileExists(atPath: livewallsDir.path) {
                    try FileManager.default.createDirectory(at: livewallsDir, withIntermediateDirectories: true, attributes: nil)
                    appLogger.info("📁 LiveWalls directory created: \(livewallsDir.path)")
                }
                
                // Use timestamp to avoid file conflicts
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "wallpaper_frame_\(timestamp).png"
                finalImageURL = livewallsDir.appendingPathComponent(fileName)
                
                // Write file
                try pngData.write(to: finalImageURL)
                appLogger.info("✅ Static frame generated: \(finalImageURL.path)")
                
                // Verify that the file exists and has content
                let attributes = try FileManager.default.attributesOfItem(atPath: finalImageURL.path)
                if let fileSize = attributes[.size] as? NSNumber, fileSize.intValue > 0 {
                    appLogger.info("📄 File verified - Size: \(fileSize) bytes")
                } else {
                    throw NSError(domain: "WallpaperManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Generated file is empty"])
                }
                
            } catch {
                appLogger.error("❌ Error using Application Support (\(error.localizedDescription)). Using temporary directory...")
                
                // Fallback to system temporary directory
                let tempDir = FileManager.default.temporaryDirectory
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "livewalls_frame_\(timestamp).png"
                finalImageURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try pngData.write(to: finalImageURL)
                    appLogger.info("✅ Static frame generated (temporary): \(finalImageURL.path)")
                } catch {
                    appLogger.error("❌ Final error generating frame: \(error.localizedDescription)")
                    return nil
                }
            }
            
            return finalImageURL
            
        } catch {
            appLogger.error("❌ Error generating static frame: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Sets a static image as system wallpaper for all screens
    /// - Parameter imageURL: URL of the image to set as wallpaper
    /// - Returns: true if set correctly on at least one screen
    @discardableResult
    private func setSystemStaticWallpaper(imageURL: URL) -> Bool {
        var success = false
        
        // Verify that the file exists before trying to set it
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            appLogger.error("❌ Wallpaper file does not exist: \(imageURL.path)")
            return false
        }
        
        appLogger.info("🖼️ Setting static wallpaper for all Spaces: \(imageURL.lastPathComponent)")
        
        // Multiple strategy to ensure it applies to all Spaces
        let applyWallpaper = { [weak self] in
            guard let self = self else { return }
            
            // Verify again that the file exists
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                self.appLogger.error("❌ File disappeared during application: \(imageURL.path)")
                return
            }
            
            // Apply to all screens
            for screen in NSScreen.screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(
                        imageURL,
                        for: screen,
                        options: [
                            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                            .allowClipping: true
                        ]
                    )
                    success = true
                    self.appLogger.info("✅ Static wallpaper set on screen: \(screen.localizedName)")
                } catch {
                    self.appLogger.error("❌ Error setting static wallpaper on \(screen.localizedName): \(error.localizedDescription)")
                }
            }
        }
        
        // Apply immediately
        applyWallpaper()
        
        // Apply again after brief delays to ensure it sticks in all Spaces
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            applyWallpaper()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            applyWallpaper()
        }
        
        // Final application to capture any Space that changed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            applyWallpaper()
        }
        
        if success {
            // Clean up previous wallpaper before setting the new one
            cleanupPreviousStaticWallpaper()
            
            // Update reference to new wallpaper
            currentStaticWallpaperURL = imageURL
            appLogger.info("📋 Current static wallpaper updated: \(imageURL.lastPathComponent)")
        }
        
        return success
    }
    
    /// Cleans up previous static wallpaper file only when necessary
     private func cleanupPreviousStaticWallpaper() {
         guard let previousURL = currentStaticWallpaperURL else { return }
         
         // HOTFIX: Los archivos estáticos (wallpaper_frame_*.png) se mantienen indefinidamente 
         // para evitar race conditions con NSWorkspace que puede estar usando el archivo
         // en los reintentos posteriores (0.5s, 1s, 2s, 4s). El sistema operativo limpará
         // Application Support cuando sea necesario.
         // Solo eliminar archivos en directorios temporales del sistema.
         let shouldDelete = previousURL.path.contains("TemporaryItems") || 
                           previousURL.path.contains("/tmp/")
         
         if shouldDelete {
             // Use 30-second delay to give NSWorkspace time to apply wallpaper to all Spaces
             scheduleFileForCleanup(fileURL: previousURL)
         } else {
             appLogger.info("💾 Keeping file in Application Support (no scheduled cleanup): \(previousURL.lastPathComponent)")
          }
     }
     
     /// Gets the next video in the queue (after current video)
     /// - Returns: Next video or nil if no videos available
     private func getNextVideoInQueue() -> VideoFile? {
         let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
         
         guard !enabledVideos.isEmpty, let currentVideo = currentVideo else {
             return nil
         }
         
         guard let currentIndex = enabledVideos.firstIndex(where: { $0.id == currentVideo.id }) else {
             return enabledVideos.first
         }
         
         let nextIndex = (currentIndex + 1) % enabledVideos.count
         return enabledVideos[nextIndex]
     }
     

    /// Schedules a file for cleanup after 30 seconds
    /// - Parameter fileURL: URL of the file to clean up
    func scheduleFileForCleanup(fileURL: URL) {
        appLogger.info("📅 Scheduling file for cleanup in 30s: \(fileURL.lastPathComponent)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            guard let self = self else { return }
            self.performBatchCleanup(fileURL: fileURL)
        }
    }
    
    /// Performs the actual cleanup of the scheduled file
    /// - Parameter fileURL: URL of the file to delete
    private func performBatchCleanup(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            appLogger.info("✓ File already deleted: \(fileURL.lastPathComponent)")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            appLogger.info("🧹 File deleted after 30s cleanup: \(fileURL.lastPathComponent)")
        } catch {
            appLogger.warning("⚠️ Could not delete file after cleanup: \(error.localizedDescription)")
        }
    }
    
    /// Establece un video como activo (wallpaper actual)
    /// - Parameter video: VideoFile a establecer como activo
    func setActiveVideo(_ video: VideoFile) async {
        appLogger.info("🎯 Setting active video: \(video.name)")
        
        // Update isActive state of all videos and force UI update
        var updatedVideos = videoFiles
        for i in 0..<updatedVideos.count {
            updatedVideos[i].isActive = (updatedVideos[i].id == video.id)
        }
        videoFiles = updatedVideos // This forces @Published update
        
        currentVideo = video
        saveCurrentVideo()
        
        appLogger.info("✅ Active video set: \(video.name)")
    }
    
    /// Removes a video from the wallpaper list
    /// - Parameter video: VideoFile to remove
    func removeVideo(_ video: VideoFile) {
        self.appLogger.info("🗑️ Removing video: \(video.name)")
        
        // If it's the current video, stop the wallpaper and select another
        let wasCurrentVideo = self.currentVideo?.id == video.id
        if wasCurrentVideo {
            self.stopWallpaper()
            self.currentVideo = nil
        }
        
        self.videoFiles.removeAll { $0.id == video.id }
        
        // Si era el video actual y quedan otros videos, seleccionar el primero
        if wasCurrentVideo && !self.videoFiles.isEmpty {
            let newCurrentVideo = self.videoFiles.first!
            self.currentVideo = newCurrentVideo
            Task {
                await self.persistenceActor.saveCurrentVideo(newCurrentVideo)
            }
            self.appLogger.info("🔄 Video actual eliminado, nuevo video seleccionado: \(newCurrentVideo.name)")
        }
        
        self.saveVideos()
    }
    
    // MARK: - Wallpaper Control
    
    /// Starts wallpaper playback safely
    func startWallpaperSafe() {
        guard let currentVideo = currentVideo else {
            appLogger.warning("⚠️ No video selected to start wallpaper")
            return
        }
        
        Task {
            await wallpaperOperationActor.withExclusiveAccess {
                await MainActor.run {
                    self.appLogger.info("▶️ Iniciando wallpaper: \(currentVideo.name)")
                }
                
                let resolvedURL = await self.resolveBookmark(for: currentVideo)
                guard let accessibleURL = resolvedURL else {
                    await MainActor.run {
                        self.notificationManager.showError(message: "No se pudo acceder al archivo de video")
                    }
                    return
                }
                
                 // Fase 1: Generar frame estático en background sin bloquear inicio del video
                 // HOTFIX: Usar DispatchQueue.main.async en lugar de await MainActor.run
                 // para evitar deadlocks causados por Task.detached anidado
                 Task.detached { [weak self] in
                     guard let self = self else { return }
                     if let staticImageURL = await self.generateStaticWallpaperFrame(for: accessibleURL) {
                         // Ejecutar en main thread sin await para evitar deadlock
                         DispatchQueue.main.async {
                             _ = self.setSystemStaticWallpaper(imageURL: staticImageURL)
                             self.appLogger.info("🖼️ Wallpaper estático establecido para Mission Control/Exposé")
                             self.scheduleWallpaperApplicationForAllSpaces()
                         }
                     } else {
                         DispatchQueue.main.async {
                             self.appLogger.warning("⚠️ No se pudo generar wallpaper estático")
                         }
                     }
                 }
                
                 // Crear ventanas de forma asíncrona sin bloquear en frame estático
                 await self.createDesktopWindows(for: currentVideo, accessibleURL: accessibleURL)
                 
                 await MainActor.run {
                     self.isPlayingWallpaper = true
                     self.startAutoChangeTimerIfNeeded()
                 }

                 // Programar verificaciones de salud post‑arranque en background (Phase 7)
                  await self.scheduledHealthCheckManager.scheduleHealthChecks(
                      action: { [weak self] in
                          await MainActor.run { [weak self] in
                              self?.ensurePlaying(reason: "post-start scheduled check")
                          }
                      },
                      intervals: [1.0, 3.0]
                  )
                  
                  // Precargar el siguiente video para transiciones instantáneas
                  if let nextVideo = self.getNextVideoInQueue() {
                      if let nextURL = await self.resolveBookmark(for: nextVideo) {
                          await self.videoPreloader.preload(videoURL: nextURL)
                      }
                  }
             }
         }
     }
    
    /// Stops wallpaper playback
    func stopWallpaper() {
        Task {
            await wallpaperOperationActor.withExclusiveAccess {
                await MainActor.run {
                    self.appLogger.info("⏹️ Deteniendo wallpaper")
                    self.stopAutoChangeTimer()
                    self.stopStaticFrameUpdateTimer()
                    self.destroyAllDesktopWindows {
                        self.isPlayingWallpaper = false
                    }
                }
            }
        }
    }
    
    /// Alterna entre iniciar/detener el wallpaper
    func toggleWallpaper() {
        if isPlayingWallpaper {
            stopWallpaper()
        } else {
            startWallpaperSafe()
        }
    }
    
    // MARK: - Bookmark Resolution
    
    /// Resuelve un bookmark security-scoped para obtener acceso al archivo
    /// - Parameter video: VideoFile cuyo bookmark se debe resolver
    /// - Returns: URL accesible o nil si falla
    func resolveBookmark(for video: VideoFile) async -> URL? {
        guard let bookmarkData = video.bookmarkData else {
            appLogger.error("❌ No hay bookmark data para: \(video.name)")
            return nil
        }
        
        do {
            // Resolver bookmark de forma asíncrona usando BookmarkActor
            let url = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
            
            // Iniciar acceso security-scoped usando BookmarkActor
            let started = await bookmarkActor.startAccessingSecurityScopedResource(url: url)
            guard started else {
                appLogger.error("❌ No se pudo iniciar acceso security-scoped para: \(video.name)")
                return nil
            }
            
            // Registrar URL activa en el conjunto local (para compatibilidad)
            let normalizedPath = url.path
            activeSecurityScopedURLs.insert(normalizedPath)
            
            appLogger.info("✅ Bookmark resuelto y acceso iniciado: \(video.name)")
            return url
            
        } catch {
            appLogger.error("❌ Error resolviendo bookmark para \(video.name): \(error)")
            return nil
        }
    }
    
    // MARK: - Desktop Windows Management
    
    /// Crea ventanas de video para todas las pantallas de forma asíncrona
    private func createDesktopWindows(for video: VideoFile, accessibleURL: URL) async {
        // Limpiar instancias previas
        if !desktopVideoInstances.isEmpty {
            appLogger.warning("⚠️ Limpiando ventanas previas antes de crear nuevas")
            for (window, _) in desktopVideoInstances {
                window.close()
            }
            desktopVideoInstances.removeAll()
        }
        
        let screens = NSScreen.screens
        
        // FASE 5: Métricas de rendimiento - timestamp inicio
        let startTime = Date()
        
        // Verificar si el filesystem está "caliente" por precarga
        let isWarmedUp = await videoPreloader.isWarmedUp(for: accessibleURL)
        if isWarmedUp {
            appLogger.info("🔥 Filesystem precalentado - creación acelerada esperada")
        }
        
        // Usar WindowCreationCoordinator para crear ventanas de forma asíncrona
        let createdWindows = await windowCreationCoordinator.createWindowsAsync(
            screens: screens,
            videoFile: video,
            bookmarkActor: bookmarkActor
        )
        
        // FASE 5: Métricas de rendimiento - calcular tiempo transcurrido
        let elapsedTime = Date().timeIntervalSince(startTime)
        let warmStatus = isWarmedUp ? "WARM" : "COLD"
        appLogger.info("⏱️ Creación de ventanas completada en \(String(format: "%.2f", elapsedTime * 1000))ms [Cache: \(warmStatus)]")
        
        if createdWindows.isEmpty {
            appLogger.error("❌ No se pudo crear ninguna ventana de escritorio")
            notificationManager.showError(message: "No se pudo crear ventanas de fondo de pantalla")
            safeStopSecurityScopedAccess(for: accessibleURL)
        } else {
            // Convertir NSWindow a DesktopVideoWindowMejorada para mantener compatibilidad
            let desktopWindows = createdWindows.map { window in
                (window: window as! DesktopVideoWindowMejorada, accessibleURL: accessibleURL)
            }
            desktopVideoInstances = desktopWindows
            appLogger.info("✅ Creadas \(createdWindows.count) ventanas de escritorio de forma asíncrona")
        }
    }
    
    /// Destruye todas las ventanas de escritorio
    private func destroyAllDesktopWindows(completion: @escaping () -> Void) {
        guard !desktopVideoInstances.isEmpty else {
            completion()
            return
        }
        
        appLogger.info("🧹 Destruyendo \(self.desktopVideoInstances.count) ventanas de escritorio")
        
        let instancesToDestroy = desktopVideoInstances
        desktopVideoInstances.removeAll()
        
        // Usar DispatchGroup para esperar que todas las ventanas se cierren completamente
        let group = DispatchGroup()
        
        for (window, accessibleURL) in instancesToDestroy {
            group.enter()
            
            // Usar el nuevo método close con completion
            window.close { [weak self] in
                // Liberar acceso security-scoped después de que la ventana esté completamente cerrada
                let delay = self?.resourceReleaseDelay ?? 0.1
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    if let self {
                        Task { @MainActor in
                            self.safeStopSecurityScopedAccess(for: accessibleURL)
                        }
                    }
                    group.leave()
                }
            }
        }
        
        // Ejecutar completion cuando todas las ventanas estén cerradas
        group.notify(queue: .main) {
            completion()
        }
    }
    
    // MARK: - Security-Scoped Resource Management
    
    /// Detiene el acceso security-scoped de forma segura
    @MainActor
    private func safeStopSecurityScopedAccess(for url: URL) {
        let normalizedPath = url.path
        if activeSecurityScopedURLs.contains(normalizedPath) {
            activeSecurityScopedURLs.remove(normalizedPath)
            
            // Usar BookmarkActor para detener acceso
            Task {
                await bookmarkActor.stopAccessingSecurityScopedResource(url: url)
            }
            
            appLogger.debug("🔓 Liberado acceso security-scoped: \(normalizedPath)")
        }
    }
    
    // MARK: - New Robust Auto Change Timer
    
    private func startAutoChangeTimerIfNeeded() {
        guard self.isAutoChangeEnabled, self.autoChangeInterval > 0, self.videoFiles.count > 1 else { 
            appLogger.debug("💡 No se inicia timer: enabled=\(self.isAutoChangeEnabled), interval=\(self.autoChangeInterval), videos=\(self.videoFiles.count)")
            return 
        }
        
        // Validate that there are videos enabled for random playback
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        guard enabledVideos.count > 1 else {
            appLogger.warning("⚠️ No hay suficientes videos habilitados para rotación automática")
            return
        }
        
        // Validar estado del timer manager
        if !timerManager.validateState() {
            appLogger.warning("⚠️ Estado de timer inconsistente, recuperando...")
            timerManager.recoverFromInconsistentState()
        }
        
        // Iniciar timer con el nuevo sistema robusto
        timerManager.startTimer(interval: autoChangeInterval) { [weak self] in
            await self?.changeToNextVideo()
        }
        
        appLogger.info("⏰ Timer robusto de cambio automático iniciado: \(Int(self.autoChangeInterval))s")
    }
    
    private func stopAutoChangeTimer() {
        timerManager.stopTimer()
        appLogger.info("⏹️ Timer de cambio automático detenido")
    }
    
    /// Reinicia el timer de cambio automático (útil después de cambios manuales)
    private func restartAutoChangeTimerIfNeeded() {
        guard timerManager.isTimerActive else {
            appLogger.debug("💡 No se reinicia timer: no está activo")
            return
        }
        
        appLogger.info("🔄 Reiniciando timer después de cambio manual")
        startAutoChangeTimerIfNeeded()
    }
    
    // MARK: - Static Frame Update Timer
    

    
    private func updateStaticFrameOnSpaceChange() async {
        guard let currentVideo = currentVideo, isPlayingWallpaper else { return }
        
        guard let accessibleURL = await resolveBookmark(for: currentVideo) else { return }
        
        // CRÍTICO: Reactivar reproducción de video en todas las ventanas
        // Al cambiar de Space, macOS puede pausar o congelar el video
        await MainActor.run {
            appLogger.info("🔄 Reactivando reproducción de video después de cambio de Space")
            for (window, _) in desktopVideoInstances {
                // Forzar reproducción
                window.forcePlay()
            }
        }
        
        // Obtener tiempo actual del video para el nuevo Space
        var currentVideoTime: CMTime? = nil
        if let firstInstance = desktopVideoInstances.first {
            currentVideoTime = firstInstance.window.getCurrentTime()
        }
        
         // Generar nuevo frame para el Space actual en background (no bloquear)
         // HOTFIX: Usar DispatchQueue.main.async en lugar de await MainActor.run
         // para evitar deadlocks
         Task.detached { [weak self] in
             guard let self = self else { return }
             
             if let staticImageURL = await self.generateStaticWallpaperFrame(for: accessibleURL, timeOffset: currentVideoTime) {
                 DispatchQueue.main.async {
                     _ = self.setSystemStaticWallpaper(imageURL: staticImageURL)
                     self.appLogger.info("🔄 Frame estático actualizado por cambio de Space - tiempo: \(currentVideoTime.map { "\(CMTimeGetSeconds($0))s" } ?? "inicial")")
                 }
                 
                 // Limpiar archivo temporal
                 try? FileManager.default.removeItem(at: staticImageURL)
             }
         }
        
        // Liberar acceso
        safeStopSecurityScopedAccess(for: accessibleURL)
    }
    
    // Eliminamos el timer periódico innecesario
    private func stopStaticFrameUpdateTimer() {
        staticFrameUpdateTimer?.invalidate()
        staticFrameUpdateTimer = nil
    }
    
    
    
    private func changeToNextVideo() async {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        
        guard enabledVideos.count > 1 else {
            appLogger.warning("⚠️ No hay suficientes wallpapers habilitados para cambio automático")
            return
        }
        
        guard let currentVideo = currentVideo,
              let currentIndex = enabledVideos.firstIndex(where: { $0.id == currentVideo.id }) else {
            // Si el video actual no está en la lista habilitada, ir al primer habilitado
            if let firstEnabled = enabledVideos.first {
                appLogger.info("🔄 Cambiando automáticamente al primer wallpaper habilitado: \(firstEnabled.name)")
                await setActiveVideo(firstEnabled)
                
                if isPlayingWallpaper {
                    startWallpaperSafe()
                }
            }
            return
        }
        
        let nextIndex = (currentIndex + 1) % enabledVideos.count
        let nextVideo = enabledVideos[nextIndex]
        
        appLogger.info("🔄 Cambiando automáticamente a: \(nextVideo.name)")
        
        // Check if we should use transition
        if isPlayingWallpaper {
            await changeToNextVideoWithTransition(to: nextVideo)
        } else {
            await setActiveVideo(nextVideo)
        }
    }
    
    /// Changes to the next video with a smooth transition
    /// OPTIMIZADO: Transición inmediata, frame estático generado en background después
    private func changeToNextVideoWithTransition(to nextVideo: VideoFile) async {
        // FASE 5.3: Prevenir transiciones concurrentes
        guard !isTransitioning else {
            appLogger.warning("⚠️ Transición ya en progreso - ignorando solicitud")
            return
        }
        
        isTransitioning = true
        defer { isTransitioning = false }
        
        appLogger.info("🔄 Cambiando con transición a: \(nextVideo.name)")
        
        // Ensure we have a current video selected
        guard currentVideo != nil else {
            appLogger.error("❌ No hay video actual")
            await setActiveVideo(nextVideo)
            return
        }
        
        // Get the next video URL
        guard let nextURL = await resolveBookmark(for: nextVideo) else {
            appLogger.error("❌ No se pudo obtener el URL del siguiente video")
            await setActiveVideo(nextVideo)
            return
        }

        let oldInstances = desktopVideoInstances
        let startTime = Date()
        
        appLogger.info("⏱️ T+0ms: Iniciando transición de \(self.currentVideo?.name ?? "?") → \(nextVideo.name)")
        
        // Create paused windows to prepare the transition
        let screens = NSScreen.screens
        let newWindows = await windowCreationCoordinator.createWindowsAsync(
            screens: screens,
            videoFile: nextVideo,
            bookmarkActor: bookmarkActor,
            startPaused: true,
            staticImageURL: nil  // No placeholder for faster transition
        )
        let newVideoWindows = newWindows.compactMap { $0 as? DesktopVideoWindowMejorada }
        
        let t1 = Date().timeIntervalSince(startTime)
        appLogger.info("⏱️ T+\(Int(t1*1000))ms: \(newVideoWindows.count) ventanas nuevas creadas")
        
        // Validate creation
        guard !newVideoWindows.isEmpty else {
            appLogger.error("❌ No se pudieron crear ventanas para transición - manteniendo wallpaper actual")
            await MainActor.run {
                self.safeStopSecurityScopedAccess(for: nextURL)
            }
            return
        }
        
        // Prepare new windows hidden at start
        await MainActor.run {
            newVideoWindows.forEach { window in
                window.delegate = self
                window.orderFront(nil)
                window.orderBack(nil)
                window.setOpacity(0.0)
            }
        }
        
        let t2 = Date().timeIntervalSince(startTime)
        appLogger.info("⏱️ T+\(Int(t2*1000))ms: Nuevas ventanas preparadas (opacidad 0)")
        
        // Activate playback in new windows BEFORE fading out the old ones
        let successCount = await windowCreationCoordinator.activatePlaybackInWindows(newVideoWindows.map { $0 as NSWindow })
        
        let t3 = Date().timeIntervalSince(startTime)
        appLogger.info("⏱️ T+\(Int(t3*1000))ms: Reproducción activada (\(successCount)/\(newVideoWindows.count) ventanas)")
        
        // If nothing played, keep the previous wallpaper and clean up
        guard successCount > 0 else {
            appLogger.error("❌ Ninguna ventana pudo activar reproducción - conservando wallpaper previo")
            await MainActor.run {
                oldInstances.forEach {
                    $0.window.setOpacity(1.0)
                    $0.window.forcePlay()
                }
            }
            await teardownWindows(newVideoWindows.map { ($0, nextURL) }, reason: "fallo al activar nuevas ventanas")
            await MainActor.run {
                self.safeStopSecurityScopedAccess(for: nextURL)
            }
            return
        }
    
        // Pick reference windows for the transition
        let firstOldWindow = oldInstances.first?.window
        let firstNewWindow = newVideoWindows.first
        
        // Run transition while keeping old windows visible until new ones are ready
        if firstNewWindow != nil {
            transitionManager.startCrossfadeTransition(fromWindow: firstOldWindow, toWindow: firstNewWindow)
        }
        
        let t4 = Date().timeIntervalSince(startTime)
        appLogger.info("⏱️ T+\(Int(t4*1000))ms: Crossfade iniciado - esperando \(Int(self.transitionDuration*1000))ms")
        
        // Allow visual transition time
        try? await Task.sleep(for: .seconds(transitionDuration))
        
        let t5 = Date().timeIntervalSince(startTime)
        appLogger.info("⏱️ T+\(Int(t5*1000))ms: Crossfade completado - aplicando opacidades finales")
        
        // Ensure all new windows are visible (multi-monitor)
        await MainActor.run {
            newVideoWindows.forEach { $0.setOpacity(1.0) }
            oldInstances.forEach { $0.window.setOpacity(0.0) }
        }
        
        let t6 = Date().timeIntervalSince(startTime)
        appLogger.info("⏱️ T+\(Int(t6*1000))ms: Opacidades finales aplicadas")
        
        if successCount < newVideoWindows.count {
            appLogger.warning("⚠️ Solo \(successCount)/\(newVideoWindows.count) ventanas activaron reproducción")
        } else {
            appLogger.info("✅ Todas las ventanas activaron reproducción exitosamente")
        }
        
        // Update active instances and selected video
        desktopVideoInstances = newVideoWindows.map { (window: $0, accessibleURL: nextURL) }
        await setActiveVideo(nextVideo)
        
        // Preload the next video in the queue for fast transitions
        Task {
            if let nextVideo = self.getNextVideoInQueue() {
                if let nextURL = await self.resolveBookmark(for: nextVideo) {
                    await self.videoPreloader.preload(videoURL: nextURL)
                }
            }
        }
        
        // Close previous windows once the new ones are playing
        await teardownWindows(oldInstances, reason: "transición completada")
        
        appLogger.info("✅ Cambio de video con transición completado: \(nextVideo.name)")
         
        // OPTIMIZATION: Generate static frame in background after the transition
        // Keep previous static wallpaper until the new one is ready to avoid showing the system wallpaper
        
        // HOTFIX: Use DispatchQueue.main.async instead of await MainActor.run to avoid deadlocks
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            // Generar frame estático
            if let staticImageURL = await self.generateStaticWallpaperFrame(for: nextURL) {
                DispatchQueue.main.async {
                    // Aplicar inmediatamente a todos los Spaces
                    let success = self.setSystemStaticWallpaper(imageURL: staticImageURL)
                    if success {
                        self.appLogger.info("🖼️ Frame estático generado y aplicado para Exposé/Lock Screen")
                    }
                }
                
                // Limpiar archivo temporal después de aplicarlo
                try? FileManager.default.removeItem(at: staticImageURL)
            }
        }
    }
    
    /// Closes windows and releases security-scoped access with a safety timeout
    private func teardownWindows(_ instances: [(DesktopVideoWindowMejorada, URL)], reason: String) async {
        guard !instances.isEmpty else { return }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            var hasResumed = false
            let resumeLock = NSLock()
            
            let resumeOnce = { (why: String) in
                resumeLock.lock()
                defer { resumeLock.unlock() }
                if !hasResumed {
                    hasResumed = true
                    self.appLogger.info("📍 Ventanas cerradas (\(reason)): \(why)")
                    continuation.resume()
                }
            }
            
            for (window, url) in instances {
                group.enter()
                window.close { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.safeStopSecurityScopedAccess(for: url)
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                resumeOnce("Todas las ventanas notificaron cierre")
            }
            
            // Timeout de seguridad
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resumeOnce("Timeout de 3s cerrando ventanas")
            }
        }
    }
    
    // MARK: - Manual Next Wallpaper & Random Play Control
    
    /// Manually changes to the next wallpaper available for random playback
    func nextWallpaper() async {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        
        // DEBUG: Log detallado de videos disponibles
        appLogger.info("🔍 DEBUG nextWallpaper() - Videos habilitados: \(enabledVideos.count)")
        appLogger.info("🔍 DEBUG - Current video: \(self.currentVideo?.name ?? "nil")")
        for (idx, video) in enabledVideos.enumerated() {
            appLogger.info("🔍 DEBUG - [\(idx)]: \(video.name) (id: \(video.id.uuidString.prefix(8))...)")
        }
        
        guard enabledVideos.count > 1 else {
            appLogger.warning("⚠️ No hay suficientes wallpapers habilitados para cambio manual (count: \(enabledVideos.count))")
            return
        }
        
        guard let currentVideo = currentVideo,
              let currentIndex = enabledVideos.firstIndex(where: { $0.id == currentVideo.id }) else {
            // Si el video actual no está en la lista habilitada, ir al primer habilitado
            if let firstEnabled = enabledVideos.first {
                appLogger.info("🔄 Cambiando manualmente al primer wallpaper habilitado: \(firstEnabled.name)")
                
                if isPlayingWallpaper {
                    await changeToNextVideoWithTransition(to: firstEnabled)
                    // Reiniciar timer después de cambio manual
                    await MainActor.run {
                        self.restartAutoChangeTimerIfNeeded()
                    }
                } else {
                    await setActiveVideo(firstEnabled)
                }
            }
            return
        }
        
        let nextIndex = (currentIndex + 1) % enabledVideos.count
        let nextVideo = enabledVideos[nextIndex]
        
        appLogger.info("🔄 Cambiando manualmente de [\(currentIndex)] \(currentVideo.name) → [\(nextIndex)] \(nextVideo.name)")
        
        // VERIFICACIÓN: Asegurar que realmente es un video diferente
        if nextVideo.id == currentVideo.id {
            appLogger.error("❌ BUG DETECTADO: nextVideo es el mismo que currentVideo!")
            appLogger.error("   Current: \(currentVideo.name) (\(currentVideo.id.uuidString))")
            appLogger.error("   Next: \(nextVideo.name) (\(nextVideo.id.uuidString))")
            appLogger.error("   CurrentIndex: \(currentIndex), NextIndex: \(nextIndex), Count: \(enabledVideos.count)")
            return
        }
        
        if isPlayingWallpaper {
            await changeToNextVideoWithTransition(to: nextVideo)
            // Reiniciar timer después de cambio manual
            await MainActor.run {
                self.restartAutoChangeTimerIfNeeded()
            }
        } else {
            await setActiveVideo(nextVideo)
        }
    }
    
    /// Comprueba si el botón "Siguiente Wallpaper" debe estar habilitado
    var canGoToNextWallpaper: Bool {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        return isAutoChangeEnabled && enabledVideos.count > 1
    }
    
    /// Toggles the enabled state for random playback of a specific video
    func toggleVideoRandomPlayEnabled(_ video: VideoFile) {
        guard let index = videoFiles.firstIndex(where: { $0.id == video.id }) else { return }
        
        videoFiles[index].isEnabledForRandomPlay.toggle()
        let newState = videoFiles[index].isEnabledForRandomPlay
        
        appLogger.info("🎯 Video '\(video.name)' \(newState ? "enabled" : "disabled") for random playback")
        
        // Guardar cambios
        saveVideos()
        
        // Si se deshabilitó el video actual y está en modo auto-change, cambiar al siguiente habilitado
        if !newState && video.id == currentVideo?.id && isAutoChangeEnabled && isPlayingWallpaper {
            Task {
                await self.nextWallpaper()
            }
        }
    }
    
    // MARK: - Persistence
    
    /// Guarda la lista de videos de forma asíncrona usando PersistenceActor
    func saveVideos() {
         let videos = videoFiles
         Task.detached { [weak self] in
             guard let self else { return }
             do {
                 try await self.persistenceActor.saveVideos(videos)
             } catch {
                 // HOTFIX: Usar DispatchQueue.main.async en lugar de await MainActor.run
                 // para evitar deadlocks en Task.detached
                 DispatchQueue.main.async {
                     self.appLogger.error("❌ Error al guardar videos: \(error.localizedDescription)")
                 }
             }
         }
    }
    
    /// Carga todos los datos de persistencia en background durante init
    private func loadDataInBackground() async {
        do {
            // Cargar videos de forma asíncrona
            let videos = try await persistenceActor.loadVideos()
            
            // Cargar video actual de forma asíncrona
            let currentVid = await persistenceActor.loadCurrentVideo()
            
            // Cargar configuración de auto-change de forma asíncrona
            let autoChangeSettings = await persistenceActor.loadAutoChangeSettings()
            
            // Actualizar estado en main thread
            await MainActor.run {
                self.videoFiles = videos
                self.currentVideo = currentVid
                self.isAutoChangeEnabled = autoChangeSettings.isEnabled
                self.autoChangeInterval = autoChangeSettings.interval
                
                self.appLogger.info("📂 Datos cargados en background: \(videos.count) videos, autoChange=\(autoChangeSettings.isEnabled)")
                self.syncActiveVideoState()
            }
        } catch {
            await MainActor.run {
                self.appLogger.error("❌ Error al cargar datos en background: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveCurrentVideo() {
        let video = currentVideo
        Task.detached { [weak self] in
            guard let self else { return }
            await self.persistenceActor.saveCurrentVideo(video)
        }
    }
    

    
    /// Sincroniza el estado isActive de todos los videos con el currentVideo
    private func syncActiveVideoState() {
        var updatedVideos = videoFiles
        
        guard let currentVideo = currentVideo else {
            // Si no hay video actual, desmarcar todos como activos
            for i in 0..<updatedVideos.count {
                updatedVideos[i].isActive = false
            }
            self.videoFiles = updatedVideos
            return
        }
        
        // Marcar solo el video actual como activo
        for i in 0..<updatedVideos.count {
            updatedVideos[i].isActive = (updatedVideos[i].id == currentVideo.id)
        }
        self.videoFiles = updatedVideos
        
        appLogger.info("🔄 Estado sincronizado - Video activo: \(currentVideo.name)")
    }
    

    /// Loads transition settings from UserDefaults
    private func loadTransitionSettings() {
        isTransitionEnabled = userDefaults.bool(forKey: isTransitionEnabledKey)
        transitionDuration = userDefaults.double(forKey: transitionDurationKey)
        if transitionDuration <= 0 {
            transitionDuration = 2.0 // Default 2 segundos
        }
        
        // Load transition type
        let transitionTypeRawValue = userDefaults.string(forKey: transitionTypeKey) ?? "crossfade"
        switch transitionTypeRawValue {
        case "fadeOutFadeIn":
            transitionType = .fadeOutFadeIn
        default:
            transitionType = .crossfade
        }
    }
    
    /// Guarda configuración de cambio automático usando PersistenceActor
    func saveAutoChangeSettings() {
        let isEnabled = isAutoChangeEnabled
        let interval = autoChangeInterval
        
        Task.detached { [weak self] in
            guard let self else { return }
            await self.persistenceActor.saveAutoChangeSettings(isEnabled: isEnabled, interval: interval)
        }
        
        appLogger.info("💾 Saving configuration: enabled=\(self.isAutoChangeEnabled), interval=\(Int(self.autoChangeInterval))s")
        
        if isAutoChangeEnabled && isPlayingWallpaper {
            // Solo iniciar timer si el wallpaper está reproduciéndose
            startAutoChangeTimerIfNeeded()
        } else {
            // Detener timer si se deshabilitó o no hay wallpaper activo
            stopAutoChangeTimer()
        }
        
        // Realizar health check después de cambios
        Task {
            await performTimerHealthCheck()
        }
    }
    
    /// Saves transition configuration
    func saveTransitionSettings() {
        userDefaults.set(isTransitionEnabled, forKey: isTransitionEnabledKey)
        userDefaults.set(transitionDuration, forKey: transitionDurationKey)
        
        // Save transition type
        let transitionTypeRawValue: String
        switch transitionType {
        case .fadeOutFadeIn:
            transitionTypeRawValue = "fadeOutFadeIn"
        default:
            transitionTypeRawValue = "crossfade"
        }
        userDefaults.set(transitionTypeRawValue, forKey: transitionTypeKey)
        
        appLogger.info("💾 Saving transition configuration: enabled=\(self.isTransitionEnabled), duration=\(self.transitionDuration)s, type=\(transitionTypeRawValue)")
    }
    
    /// Sets whether transitions are enabled
    func setTransitionEnabled(_ enabled: Bool) {
        isTransitionEnabled = enabled
        saveTransitionSettings()
    }
    
    /// Sets the transition duration
    func setTransitionDuration(_ duration: TimeInterval) {
        transitionDuration = duration
        saveTransitionSettings()
    }
    
    /// Sets the transition type
    func setTransitionType(_ type: TransitionManager.TransitionType) {
        transitionType = type
        saveTransitionSettings()
    }
    
    /// Gets the current transition settings
    func getTransitionSettings() -> (isEnabled: Bool, duration: TimeInterval, type: TransitionManager.TransitionType) {
        return (isTransitionEnabled, transitionDuration, transitionType)
    }
    
    /// Función para compatibilidad con ContentView - llama a stopWallpaper()
    func stopWallpaperSafe() {
        stopWallpaper()
    }
    
    /// Función para pruebas: establecer wallpaper estático manualmente
    func testStaticWallpaper() async {
        guard let currentVideo = currentVideo else {
            appLogger.warning("⚠️ No hay video seleccionado para prueba estática")
            return
        }
        
        guard let accessibleURL = await resolveBookmark(for: currentVideo) else {
            appLogger.error("❌ No se pudo acceder al video para prueba estática")
            return
        }
        
        appLogger.info("🧪 INICIANDO PRUEBA DE WALLPAPER ESTÁTICO")
        
        if let staticImageURL = await generateStaticWallpaperFrame(for: accessibleURL) {
            appLogger.info("✅ Frame estático generado: \(staticImageURL.path)")
            
            let success = setSystemStaticWallpaper(imageURL: staticImageURL)
            if success {
                appLogger.info("✅ PRUEBA EXITOSA: Wallpaper estático establecido")
                
                // También aplicar a todos los Spaces existentes con delay
                scheduleWallpaperApplicationForAllSpaces()
            } else {
                appLogger.error("❌ PRUEBA FALLIDA: No se pudo establecer wallpaper estático")
            }
        } else {
            appLogger.error("❌ PRUEBA FALLIDA: No se pudo generar frame estático")
        }
        
        // Liberar acceso al video
        safeStopSecurityScopedAccess(for: accessibleURL)
    }
    
    /// Programa la aplicación del wallpaper a intervalos para capturar todos los Spaces
    private func scheduleWallpaperApplicationForAllSpaces() {
        guard let staticURL = currentStaticWallpaperURL else { return }
        
        appLogger.info("📅 Programando aplicación de wallpaper para todos los Spaces")
        
        // Aplicar en intervalos más cortos para cubrir Spaces activos/inactivos
        let intervals: [TimeInterval] = [0.5, 1.0, 2.0, 4.0]
        
        for interval in intervals {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                self.setSystemStaticWallpaper(imageURL: staticURL)
            }
        }
    }
    
    /// Establece un video como wallpaper actual y lo inicia inmediatamente
    /// - Parameter video: VideoFile a establecer como wallpaper fijo
    func setAsCurrentWallpaper(video: VideoFile) {
        appLogger.info("🌟 Fijando video como wallpaper: \(video.name)")
        
        // Detener cambio automático si está activo
        if isAutoChangeEnabled {
            isAutoChangeEnabled = false
            saveAutoChangeSettings()
            appLogger.info("⏱️ Cambio automático desactivado por fijación manual")
        }
        
        // Establecer como video actual de forma síncrona para uso inmediato
        DispatchQueue.main.async {
            // Actualizar el estado isActive de todos los videos y forzar actualización de UI
            var updatedVideos = self.videoFiles
            for i in 0..<updatedVideos.count {
                updatedVideos[i].isActive = (updatedVideos[i].id == video.id)
            }
            self.videoFiles = updatedVideos // Esto fuerza la actualización de @Published
            
            self.currentVideo = video
            self.saveCurrentVideo()
            
            self.appLogger.info("✅ Video activo establecido: \(video.name)")
            
            // Iniciar wallpaper DESPUÉS de que currentVideo se haya actualizado
            self.startWallpaperSafe()
        }
    }
    
    // MARK: - System Notifications
    
    private func setupScreenChangeNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.appLogger.info("🖥️ Configuración de pantalla cambió")
                if self.isPlayingWallpaper {
                    self.startWallpaperSafe() // Recreate windows for new configuration
                }
            }
        }
    }

    private func setupWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Detectar cambios de Space para reaplicar wallpaper estático
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    /// Observa la activación de la app para asegurar reproducción tras el login
    private func setupAppActivationNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appLogger.info("🟢 App didBecomeActive - verificando reproducción")
                self.ensurePlaying(reason: "didBecomeActive")
            }
        }
    }
    
    /// Configura la detección de aplicaciones fullscreen
    private func setupFullscreenDetection() {
        appLogger.info("🔍 Configurando detección de fullscreen")
        
        // Configurar callbacks del detector
        fullscreenDetector.onFullscreenEntered = { [weak self] appName in
            Task { @MainActor [weak self] in
                await self?.handleFullscreenEntered(appName: appName)
            }
        }
        
        fullscreenDetector.onFullscreenExited = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleFullscreenExited()
            }
        }
        
        appLogger.info("✅ Detección de fullscreen configurada")
    }
    
    /// Maneja cuando una aplicación entra en fullscreen
    private func handleFullscreenEntered(appName: String) async {
        appLogger.info("🎮 Aplicación en fullscreen detectada: \(appName)")
        
        guard isAutoChangeEnabled && isPlayingWallpaper else {
            appLogger.debug("💡 No active timer, no need to pause")
            return
        }
        
        // Pausar el timer de cambio automático
        if timerManager.isTimerActive && !timerManager.isPaused {
            appLogger.info("⏸️ Pausando timer de wallpaper por fullscreen")
            timerManager.pauseTimer()
            isWallpaperPausedForFullscreen = true
            
            // Optional: Also pause video players to save resources
            await pauseVideoPlayersForFullscreen()
        }
    }
    
    /// Maneja cuando se sale de fullscreen
    private func handleFullscreenExited() async {
        appLogger.info("🏠 Salida de fullscreen detectada")
        
        guard isWallpaperPausedForFullscreen else {
            appLogger.debug("💡 Wallpaper no estaba pausado por fullscreen")
            return
        }
        
        // Resumir el timer de cambio automático
        if timerManager.isTimerActive && timerManager.isPaused {
            appLogger.info("▶️ Resumiendo timer de wallpaper después de fullscreen")
            timerManager.resumeTimer()
            isWallpaperPausedForFullscreen = false
            
            // Resumir reproductores de video
            await resumeVideoPlayersFromFullscreen()
        }
    }
    
    /// Pauses video players during fullscreen to save resources
    private func pauseVideoPlayersForFullscreen() async {
        appLogger.info("⏸️ Pausing video players for fullscreen")
        
        for (window, _) in desktopVideoInstances {
            if let playerLayer = window.currentPlayerLayer {
                playerLayer.player?.pause()
            }
        }
    }
    
    /// Resumes video players after fullscreen
    private func resumeVideoPlayersFromFullscreen() async {
        appLogger.info("▶️ Resuming video players after fullscreen")
        
        for (window, _) in desktopVideoInstances {
            if let playerLayer = window.currentPlayerLayer {
                playerLayer.player?.play()
            }
        }
    }

    @objc private func willSleep(notification: NSNotification) {
        appLogger.info("💤 El sistema va a suspenderse. Deteniendo temporalmente el wallpaper.")
        // No es necesario detenerlo explícitamente, el sistema lo pausa.
        // Si se detiene aquí, isPlayingWallpaper sería falso al despertar.
    }

    @objc private func didWake(notification: NSNotification) {
        appLogger.info("🌅 El sistema se ha despertado.")
        // Si el wallpaper estaba activo antes de suspender, lo reiniciamos.
        if isPlayingWallpaper {
            appLogger.info("🚀 Reiniciando wallpaper después de despertar.")
            // Optimized restart: first check screens then start
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                
                // Verificar que aún tenemos un video actual
                guard let currentVideo = self.currentVideo else { return }
                
                // Pre-resolver el bookmark para reducir latencia
                guard let accessibleURL = await self.resolveBookmark(for: currentVideo) else {
                    await MainActor.run {
                        self.appLogger.error("❌ No se pudo resolver bookmark al despertar")
                    }
                    return
                }
                
                // Crear ventanas de forma asíncrona sin bloquear main thread
                await self.createDesktopWindows(for: currentVideo, accessibleURL: accessibleURL)
                
                await MainActor.run {
                    self.isPlayingWallpaper = true
                    self.startAutoChangeTimerIfNeeded()
                }
            }
        }
    }
    
    @objc private func activeSpaceDidChange(notification: NSNotification) {
        appLogger.info("🔄 Space activo cambió - reactivando video INMEDIATAMENTE")
        
        // CRÍTICO: Reactivar video INMEDIATAMENTE (no esperar 500ms)
        Task { @MainActor in
            // Primera reactivación inmediata
            self.ensurePlaying(reason: "Space change - immediate")
            
            // Reintentos para asegurar que el video no se detenga
            try? await Task.sleep(for: .milliseconds(100))
            self.ensurePlaying(reason: "Space change - retry 100ms")
            
            try? await Task.sleep(for: .milliseconds(300))
            self.ensurePlaying(reason: "Space change - retry 400ms")
            
            try? await Task.sleep(for: .milliseconds(600))
            self.ensurePlaying(reason: "Space change - retry 1000ms")
            
            // Actualizar frame estático en background (no bloquear)
            await self.updateStaticFrameOnSpaceChange()
        }
    }
    
    private func setupTerminationHandling() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupAllResources()
            }
        }
    }
    
    // MARK: - Background Color Window Management
    
    /// Create background color windows for all screens
    @MainActor
    private func createBackgroundColorWindows() {
        self.appLogger.info("🎨 Creating background color windows for transition")
        
        // Clean up any existing background windows first
        self.cleanupBackgroundColorWindows()
        
        let screens = NSScreen.screens
        for screen in screens {
            let colorWindow = BackgroundColorWindow(screen: screen)
            // Ordenar al frente primero para asegurar visibilidad
            colorWindow.makeKeyAndOrderFront(nil)
            // Luego ordenar atrás pero manteniendo visible
            colorWindow.orderBack(nil)
            // Forzar renderizado inmediato
            colorWindow.display()
            colorWindow.displayIfNeeded()
            self.backgroundColorWindows.append(colorWindow)
        }
        
        self.appLogger.info("✅ Created \(self.backgroundColorWindows.count) background color windows with forced display")
    }
    
    /// Clean up background color windows
    @MainActor
    private func cleanupBackgroundColorWindows() {
        guard !self.backgroundColorWindows.isEmpty else { return }
        
        self.appLogger.info("🧹 Cleaning up \(self.backgroundColorWindows.count) background color windows")
        
        for window in self.backgroundColorWindows {
            if let colorWindow = window as? BackgroundColorWindow {
                colorWindow.cleanup()
            } else {
                window.orderOut(self)
                window.close()
            }
        }
        self.backgroundColorWindows.removeAll()
    }
    
    @MainActor
    private func cleanupAllResources() {
        appLogger.info("🧹 Cleaning up all resources")
        stopAutoChangeTimer()
        cleanupPreviousStaticWallpaper()
        cleanupBackgroundColorWindows()
        
        // Close all windows and release resources
        for (window, accessibleURL) in desktopVideoInstances {
            window.close()
            safeStopSecurityScopedAccess(for: accessibleURL)
        }
        desktopVideoInstances.removeAll()
        activeSecurityScopedURLs.removeAll()
    }
}

// MARK: - NSWindowDelegate

extension WallpaperManager {
    func windowWillClose(_ notification: Notification) {
        // Manejar cierre de ventanas si es necesario
        if let window = notification.object as? NSWindow {
            appLogger.debug("🪟 Ventana cerrándose: \(window)")
        }
    }
}

// MARK: - Debug Functions

extension WallpaperManager {
    
    /// Realiza un health check completo del timer
    func performTimerHealthCheck() async {
        appLogger.info("🏥 Realizando health check del timer")
        
        let isHealthy = timerManager.performHealthCheck()
        let fullscreenState = fullscreenDetector.getCurrentState()
        
        if !isHealthy {
            appLogger.error("❌ Timer health check falló")
            logSystemState()
        }
        
        appLogger.info("📊 Estado actual: Timer saludable=\(isHealthy), Fullscreen=\(fullscreenState.isFullscreen)")
    }

    /// Verifica y re‑inicia reproducción si no se aplicó correctamente
    /// Refactorizado para usar verificaciones asíncronas no bloqueantes con PlaybackHealthChecker
    func ensurePlaying(reason: String) {
        appLogger.info("🩺 ensurePlaying() invocado: \(reason)")

        // Necesitamos datos mínimos
        guard currentVideo != nil else {
            appLogger.debug("ℹ️ No currentVideo disponible")
            return
        }

        // Si no se reporta reproducción pero el auto‑inicio está activo, intentar iniciar
        let shouldAutoStart = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        if !isPlayingWallpaper && shouldAutoStart {
            appLogger.info("▶️ ensurePlaying: no isPlaying, auto‑inicio activo → startWallpaperSafe()")
            startWallpaperSafe()
            return
        }

        // Si se supone que está reproduciendo, validar de forma asíncrona
        if isPlayingWallpaper {
            // Lanzar verificación de salud de forma asíncrona sin bloquear main thread
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                // Usar PlaybackHealthChecker para verificación asíncrona
                let isHealthy = await self.playbackHealthChecker.checkPlaybackHealth(
                    windows: self.desktopVideoInstances,
                    currentVideo: self.currentVideo,
                    bookmarkActor: self.bookmarkActor
                )
                
                if !isHealthy {
                    self.appLogger.warning("⚠️ ensurePlaying: verificación de salud falló, reiniciando...")
                    self.startWallpaperSafe()
                } else {
                    self.appLogger.debug("✅ ensurePlaying: reproducción verificada como saludable")
                }
            }
        } else {
            appLogger.debug("ℹ️ ensurePlaying: isPlayingWallpaper=false y auto‑inicio desactivado")
        }
    }
    
    /// Registra el estado completo del sistema para debugging
    func logSystemState() {
        let timerDebugInfo = timerManager.getDebugInfo()
        let fullscreenDebugInfo = fullscreenDetector.getDebugInfo()
        
        var systemState = "=== SISTEMA LIVEWALLS DEBUG ===\n"
        systemState += "WallpaperManager State:\n"
        systemState += "- isPlayingWallpaper: \(isPlayingWallpaper)\n"
        systemState += "- isAutoChangeEnabled: \(isAutoChangeEnabled)\n"
        systemState += "- autoChangeInterval: \(Int(autoChangeInterval))s\n"
        systemState += "- currentVideo: \(currentVideo?.name ?? "None")\n"
        systemState += "- videoFiles.count: \(videoFiles.count)\n"
        systemState += "- enabledVideos.count: \(videoFiles.filter { $0.isEnabledForRandomPlay }.count)\n"
        systemState += "- desktopVideoInstances.count: \(desktopVideoInstances.count)\n"
        systemState += "- isWallpaperPausedForFullscreen: \(isWallpaperPausedForFullscreen)\n\n"
        
        systemState += timerDebugInfo + "\n"
        systemState += fullscreenDebugInfo
        
        appLogger.info("🐛 \(systemState)")
    }
    
    /// Función de debug para forzar verificación de estados
    func debugForceStateCheck() {
        Task {
            appLogger.info("🔧 Forzando verificación de estados...")
            
            // Verificar estado de fullscreen
            await fullscreenDetector.forceCheck()
            
            // Verificar salud del timer
            await performTimerHealthCheck()
            
            // Log estado completo
            logSystemState()
            
            appLogger.info("✅ Verificación de estados completada")
        }
    }
    
    /// Función de debug para testing de timer
    func debugTestTimer() {
        appLogger.info("🧪 Iniciando prueba de timer...")
        
        // Save current configuration
        let originalEnabled = isAutoChangeEnabled
        let originalInterval = autoChangeInterval
        
        // Configurar para prueba rápida
        isAutoChangeEnabled = true
        autoChangeInterval = 5.0 // 5 segundos para prueba
        
        // Iniciar timer de prueba
        startAutoChangeTimerIfNeeded()
        
        // Programar restauración después de 20 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
            self.appLogger.info("🧪 Ending timer test, restoring configuration")
            self.isAutoChangeEnabled = originalEnabled
            self.autoChangeInterval = originalInterval
            self.saveAutoChangeSettings()
        }
    }
}

// MARK: - Final del archivo
