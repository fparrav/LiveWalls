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

// Logger específico para debugging de memoria
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

/// Gestor principal de fondos de pantalla en video para LiveWalls
/// Maneja la reproducción, cambio y configuración de videos como fondo de escritorio
@MainActor
class WallpaperManager: NSObject, ObservableObject, NSWindowDelegate {
    
    // MARK: - Published Properties (DEBEN estar declaradas ANTES del init)
    @Published var videoFiles: [VideoFile] = []
    @Published var currentVideo: VideoFile? = nil
    @Published var isPlayingWallpaper = false
    @Published var isAutoChangeEnabled = false
    @Published var autoChangeInterval: TimeInterval = 10 * 60 // 10 minutos por defecto
    
    // MARK: - Private Properties
    private let appLogger = Logger(subsystem: "com.livewalls.app", category: "WallpaperManager")
    private var desktopVideoInstances: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)] = []
    private let notificationManager: NotificationManager
    private var currentStaticWallpaperURL: URL?
    private var staticFrameUpdateTimer: Timer?
    
    // MARK: - New Fullscreen and Timer Management
    private let fullscreenDetector = FullscreenDetector()
    private let timerManager = WallpaperTimerManager.shared
    private var isWallpaperPausedForFullscreen = false
    
    // MARK: - Variables para sincronización de destrucción de ventanas
    var pendingDestroyCompletion: (() -> Void)? = nil
    var pendingWindowClosures: Set<NSWindow> = []
    var closedWindowsCount: Int = 0
    
    // MARK: - UserDefaults y configuración
    private let resourceReleaseDelay: TimeInterval = 0.1
    private let userDefaults = UserDefaults.standard
    private let videosKey = "SavedVideos"
    private let currentVideoKey = "CurrentVideo"
    
    // MARK: - Security-Scoped Resource Tracking
    private var activeSecurityScopedURLs: Set<String> = []
    private let resourceTrackingQueue = DispatchQueue(label: "security.resources", attributes: .concurrent)
    
    // MARK: - Sincronización para prevenir crashes
    private let wallpaperOperationQueue = DispatchQueue(label: "com.livewalls.wallpaperQueue", attributes: .concurrent)
    private let wallpaperOperationActor = WallpaperOperationActor()
    private var isChangingVideo = false
    private var isCleaningUp = false
    
    // Actor para serializar operaciones de wallpaper
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
        
        // Cargar configuración y datos guardados
        loadSavedVideos()
        loadCurrentVideo()
        loadAutoChangeSettings()
        setupScreenChangeNotifications()
        setupWorkspaceNotifications()
        setupTerminationHandling()
        setupFullscreenDetection()
        
        // Auto-start solo si está configurado
        if !videoFiles.isEmpty && currentVideo != nil && UserDefaults.standard.bool(forKey: "AutoStartWallpaper") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startWallpaperSafe()
            }
        }
        
        appLogger.info("\(NSLocalizedString("wallpaper_manager_initialized", comment: "WallpaperManager initialized"), privacy: .public)")
    }
    
    deinit {
        appLogger.info("\(NSLocalizedString("deinitializing_wallpaper_manager", comment: "Deinitializing WallpaperManager"), privacy: .public)")
        timerManager.stopTimer()
        cleanupAllResources()
    }
    
    // MARK: - Video Management
    
    // MARK: - Duplicate Detection
    
    /// Enum para las opciones de manejo de duplicados
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
    
    /// Verifica si una URL representa un video duplicado basado en la ruta del archivo
    /// - Parameter url: URL a verificar
    /// - Returns: true si ya existe un video con la misma ruta
    private func isDuplicateByURL(_ url: URL) -> Bool {
        let normalizedPath = url.standardizedFileURL.path
        return videoFiles.contains { videoFile in
            let existingPath = videoFile.url.standardizedFileURL.path
            return existingPath == normalizedPath
        }
    }
    
    /// Verifica si una URL representa un video duplicado basado en bookmark data
    /// - Parameter url: URL a verificar
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
                    DispatchQueue.main.async {
                        self.videoFiles.removeAll { $0.id == existingVideo.id }
                    }
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
                
                DispatchQueue.main.async {
                    let countBefore = self.videoFiles.count
                    self.videoFiles.append(videoFile)
                    let countAfter = self.videoFiles.count
                    
                    self.saveVideos()
                    self.appLogger.info("\(String(format: NSLocalizedString("video_added", comment: "Video added"), videoFile.name), privacy: .public)")
                    self.appLogger.info("\(String(format: NSLocalizedString("videos_count_updated", comment: "Videos count updated"), countBefore, countAfter), privacy: .public)")
                    
                    // Debug adicional para verificar que SwiftUI recibe la actualización
                    print(String(format: NSLocalizedString("videofiles_updated_debug", comment: "VideoFiles updated debug"), self.videoFiles.count))
                    print(String(format: NSLocalizedString("names_debug", comment: "Names debug"), self.videoFiles.map { $0.name }.joined(separator: ", ")))
                }
                
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
        
        // Mostrar resumen de la importación
        DispatchQueue.main.async {
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
                self.appLogger.info("📊 Resumen de importación: \(summaryMessage)")
            }
        }
    }
    
    /// Genera una miniatura para el video
    /// - Parameter url: URL del archivo de video
    /// - Returns: Data de la imagen en formato PNG o nil si falla
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
    
    /// Genera un frame de alta resolución del video para usar como wallpaper estático
    /// - Parameter url: URL del archivo de video
    /// - Parameter timeOffset: Tiempo específico del video (nil para tiempo aleatorio)
    /// - Returns: URL del archivo temporal de imagen o nil si falla
    private func generateStaticWallpaperFrame(for url: URL, timeOffset: CMTime? = nil) async -> URL? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Usar resolución de pantalla principal para mejor calidad
        if let mainScreen = NSScreen.main {
            let screenSize = mainScreen.frame.size
            let scale = mainScreen.backingScaleFactor
            imageGenerator.maximumSize = CGSize(
                width: screenSize.width * scale,
                height: screenSize.height * scale
            )
        }
        
        // Generar imagen en alta calidad
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        
        do {
            // Determinar tiempo del frame a extraer
            let time: CMTime
            if let specificTime = timeOffset {
                time = specificTime
            } else {
                // Obtener duración del video y generar tiempo aleatorio
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                if durationSeconds > 0 {
                    let randomSeconds = Double.random(in: 0...(durationSeconds * 0.8)) // Evitar el final
                    time = CMTime(seconds: randomSeconds, preferredTimescale: 600)
                } else {
                    time = CMTime(seconds: 1.0, preferredTimescale: 600)
                }
            }
            
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            
            // Crear NSImage y convertir a datos
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            ))
            
            guard let imageData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: imageData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                appLogger.error("❌ Error convirtiendo imagen a PNG")
                return nil
            }
            
            // Intentar usar directorio Application Support primero
            guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                appLogger.error("❌ No se pudo obtener directorio Application Support")
                return nil
            }
            
            let livewallsDir = appSupportURL.appendingPathComponent("LiveWalls")
            var finalImageURL: URL
            
            // Crear directorio y archivo con manejo robusto de errores
            do {
                // Asegurar que el directorio existe
                if !FileManager.default.fileExists(atPath: livewallsDir.path) {
                    try FileManager.default.createDirectory(at: livewallsDir, withIntermediateDirectories: true, attributes: nil)
                    appLogger.info("📁 Directorio LiveWalls creado: \(livewallsDir.path)")
                }
                
                // Usar timestamp para evitar conflictos de archivos
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "wallpaper_frame_\(timestamp).png"
                finalImageURL = livewallsDir.appendingPathComponent(fileName)
                
                // Escribir archivo
                try pngData.write(to: finalImageURL)
                appLogger.info("✅ Frame estático generado: \(finalImageURL.path)")
                
                // Verificar que el archivo existe y tiene contenido
                let attributes = try FileManager.default.attributesOfItem(atPath: finalImageURL.path)
                if let fileSize = attributes[.size] as? NSNumber, fileSize.intValue > 0 {
                    appLogger.info("📄 Archivo verificado - Tamaño: \(fileSize) bytes")
                } else {
                    throw NSError(domain: "WallpaperManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Archivo generado está vacío"])
                }
                
            } catch {
                appLogger.error("❌ Error usando Application Support (\(error.localizedDescription)). Usando directorio temporal...")
                
                // Fallback a directorio temporal del sistema
                let tempDir = FileManager.default.temporaryDirectory
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "livewalls_frame_\(timestamp).png"
                finalImageURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try pngData.write(to: finalImageURL)
                    appLogger.info("✅ Frame estático generado (temporal): \(finalImageURL.path)")
                } catch {
                    appLogger.error("❌ Error final generando frame: \(error.localizedDescription)")
                    return nil
                }
            }
            
            return finalImageURL
            
        } catch {
            appLogger.error("❌ Error generando frame estático: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Establece una imagen estática como wallpaper del sistema para todas las pantallas
    /// - Parameter imageURL: URL de la imagen a establecer como wallpaper
    /// - Returns: true si se estableció correctamente en al menos una pantalla
    @discardableResult
    private func setSystemStaticWallpaper(imageURL: URL) -> Bool {
        var success = false
        
        // Verificar que el archivo existe antes de intentar establecerlo
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            appLogger.error("❌ Archivo de wallpaper no existe: \(imageURL.path)")
            return false
        }
        
        appLogger.info("🖼️ Estableciendo wallpaper estático para todos los Spaces: \(imageURL.lastPathComponent)")
        
        // Estrategia múltiple para asegurar que se aplique en todos los Spaces
        let applyWallpaper = { [weak self] in
            guard let self = self else { return }
            
            // Verificar nuevamente que el archivo existe
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                self.appLogger.error("❌ Archivo desapareció durante aplicación: \(imageURL.path)")
                return
            }
            
            // Aplicar en todas las pantallas
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
                    self.appLogger.info("✅ Wallpaper estático establecido en pantalla: \(screen.localizedName)")
                } catch {
                    self.appLogger.error("❌ Error estableciendo wallpaper estático en \(screen.localizedName): \(error.localizedDescription)")
                }
            }
        }
        
        // Aplicar inmediatamente
        applyWallpaper()
        
        // Aplicar nuevamente después de un breve delay para asegurar persistencia
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            applyWallpaper()
        }
        
        // Una aplicación más después de 1 segundo para capturar cualquier Space que se haya cambiado
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            applyWallpaper()
        }
        
        if success {
            // Limpiar wallpaper anterior antes de establecer el nuevo
            cleanupPreviousStaticWallpaper()
            
            // Actualizar la referencia al nuevo wallpaper
            currentStaticWallpaperURL = imageURL
            appLogger.info("📋 Wallpaper estático actual actualizado: \(imageURL.lastPathComponent)")
        }
        
        return success
    }
    
    /// Limpia el archivo de wallpaper estático anterior solo cuando es necesario
    private func cleanupPreviousStaticWallpaper() {
        guard let previousURL = currentStaticWallpaperURL else { return }
        
        // Delay la limpieza para dar tiempo a NSWorkspace a procesar la imagen
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }
            
            // Solo eliminar archivos antiguos, no los que están en Application Support actualmente activos
            let shouldDelete = previousURL.path.contains("TemporaryItems") || 
                              previousURL.path.contains("/tmp/") ||
                              (previousURL.path.contains("LiveWalls") && 
                               previousURL.lastPathComponent.starts(with: "wallpaper_frame_"))
            
            if shouldDelete {
                do {
                    if FileManager.default.fileExists(atPath: previousURL.path) {
                        try FileManager.default.removeItem(at: previousURL)
                        self.appLogger.info("🧹 Archivo anterior eliminado: \(previousURL.lastPathComponent)")
                    }
                } catch {
                    self.appLogger.warning("⚠️ No se pudo eliminar archivo anterior: \(error.localizedDescription)")
                }
            } else {
                self.appLogger.info("💾 Manteniendo archivo en Application Support: \(previousURL.lastPathComponent)")
            }
        }
    }
    
    /// Establece un video como activo (wallpaper actual)
    /// - Parameter video: VideoFile a establecer como activo
    func setActiveVideo(_ video: VideoFile) async {
        appLogger.info("🎯 Estableciendo video activo: \(video.name)")
        
        // Actualizar el estado isActive de todos los videos y forzar actualización de UI
        var updatedVideos = videoFiles
        for i in 0..<updatedVideos.count {
            updatedVideos[i].isActive = (updatedVideos[i].id == video.id)
        }
        videoFiles = updatedVideos // Esto fuerza la actualización de @Published
        
        currentVideo = video
        saveCurrentVideo()
        
        appLogger.info("✅ Video activo establecido: \(video.name)")
    }
    
    /// Elimina un video de la lista de wallpapers
    /// - Parameter video: VideoFile a eliminar
    func removeVideo(_ video: VideoFile) {
        DispatchQueue.main.async {
            self.appLogger.info("🗑️ Eliminando video: \(video.name)")
            
            // Si es el video actual, detener el wallpaper
            if self.currentVideo?.id == video.id {
                self.stopWallpaper()
                self.currentVideo = nil
            }
            
            self.videoFiles.removeAll { $0.id == video.id }
            self.saveVideos()
        }
    }
    
    // MARK: - Wallpaper Control
    
    /// Inicia la reproducción del wallpaper de forma segura
    func startWallpaperSafe() {
        guard let currentVideo = currentVideo else {
            appLogger.warning("⚠️ No hay video seleccionado para iniciar wallpaper")
            return
        }
        
        Task {
            await wallpaperOperationActor.withExclusiveAccess {
                await MainActor.run {
                    self.appLogger.info("▶️ Iniciando wallpaper: \(currentVideo.name)")
                }
                
                let resolvedURL = await MainActor.run { 
                    return self.resolveBookmark(for: currentVideo) 
                }
                guard let accessibleURL = resolvedURL else {
                    await MainActor.run {
                        self.notificationManager.showError(message: "No se pudo acceder al archivo de video")
                    }
                    return
                }
                
                // Generar y establecer wallpaper estático primero
                if let staticImageURL = await self.generateStaticWallpaperFrame(for: accessibleURL) {
                    await MainActor.run {
                        self.setSystemStaticWallpaper(imageURL: staticImageURL)
                        self.appLogger.info("🖼️ Wallpaper estático establecido para Mission Control/Exposé")
                        
                        // Programar aplicación para todos los Spaces
                        self.scheduleWallpaperApplicationForAllSpaces()
                    }
                } else {
                    await MainActor.run {
                        self.appLogger.warning("⚠️ No se pudo generar wallpaper estático")
                    }
                }
                
                await MainActor.run {
                    self.createDesktopWindows(for: currentVideo, accessibleURL: accessibleURL)
                    self.isPlayingWallpaper = true
                    self.startAutoChangeTimerIfNeeded()
                    
                    // Generar frame estático inicial para Mission Control/Exposé
                    Task {
                        await self.generateInitialStaticFrame()
                    }
                }
            }
        }
    }
    
    /// Detiene la reproducción del wallpaper
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
    func resolveBookmark(for video: VideoFile) -> URL? {
        guard let bookmarkData = video.bookmarkData else {
            appLogger.error("❌ No hay bookmark data para: \(video.name)")
            return nil
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                appLogger.warning("⚠️ Bookmark obsoleto para: \(video.name)")
            }
            
            // Iniciar acceso security-scoped
            guard url.startAccessingSecurityScopedResource() else {
                appLogger.error("❌ No se pudo iniciar acceso security-scoped para: \(video.name)")
                return nil
            }
            
            // Registrar URL activa
            let normalizedPath = url.path
            Task { @MainActor in
                self.activeSecurityScopedURLs.insert(normalizedPath)
            }
            
            return url
            
        } catch {
            appLogger.error("❌ Error resolviendo bookmark para \(video.name): \(error)")
            return nil
        }
    }
    
    // MARK: - Desktop Windows Management
    
    /// Crea ventanas de video para todas las pantallas
    private func createDesktopWindows(for video: VideoFile, accessibleURL: URL) {
        // Limpiar instancias previas
        if !desktopVideoInstances.isEmpty {
            appLogger.warning("⚠️ Limpiando ventanas previas antes de crear nuevas")
            for (window, _) in desktopVideoInstances {
                window.close()
            }
            desktopVideoInstances.removeAll()
        }
        
        let screens = NSScreen.screens
        var createdWindows: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)] = []
        
        for screen in screens {
            let window = DesktopVideoWindowMejorada(screen: screen, videoURL: accessibleURL)
            window.delegate = self
            window.orderFront(nil)
            window.orderBack(nil)
            
            createdWindows.append((window: window, accessibleURL: accessibleURL))
            
            // Reducir demora para mejorar latencia en wake-up
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        
        if createdWindows.isEmpty {
            appLogger.error("❌ No se pudo crear ninguna ventana de escritorio")
            notificationManager.showError(message: "No se pudo crear ventanas de fondo de pantalla")
            safeStopSecurityScopedAccess(for: accessibleURL)
        } else {
            desktopVideoInstances = createdWindows
            appLogger.info("✅ Creadas \(createdWindows.count) ventanas de escritorio")
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
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self?.safeStopSecurityScopedAccess(for: accessibleURL)
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
    private func safeStopSecurityScopedAccess(for url: URL) {
        let normalizedPath = url.path
        
        Task { @MainActor in
            if self.activeSecurityScopedURLs.contains(normalizedPath) {
                self.activeSecurityScopedURLs.remove(normalizedPath)
                url.stopAccessingSecurityScopedResource()
                self.appLogger.debug("🔓 Liberado acceso security-scoped: \(normalizedPath)")
            }
        }
    }
    
    // MARK: - New Robust Auto Change Timer
    
    private func startAutoChangeTimerIfNeeded() {
        guard isAutoChangeEnabled, autoChangeInterval > 0, videoFiles.count > 1 else { 
            appLogger.debug("💡 No se inicia timer: enabled=\(isAutoChangeEnabled), interval=\(autoChangeInterval), videos=\(videoFiles.count)")
            return 
        }
        
        // Validar que hay videos habilitados para reproducción aleatoria
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
    
    // MARK: - Static Frame Update Timer
    
    private func generateInitialStaticFrame() async {
        guard let currentVideo = currentVideo, isPlayingWallpaper else { return }
        
        guard let accessibleURL = resolveBookmark(for: currentVideo) else { return }
        
        // Generar frame inicial (sin tiempo específico para obtener frame representativo)
        if let staticImageURL = await generateStaticWallpaperFrame(for: accessibleURL, timeOffset: nil) {
            setSystemStaticWallpaper(imageURL: staticImageURL)
            appLogger.info("🖼️ Frame estático inicial generado para Mission Control")
        }
        
        // Liberar acceso
        safeStopSecurityScopedAccess(for: accessibleURL)
    }
    
    private func updateStaticFrameOnSpaceChange() async {
        guard let currentVideo = currentVideo, isPlayingWallpaper else { return }
        
        guard let accessibleURL = resolveBookmark(for: currentVideo) else { return }
        
        // Obtener tiempo actual del video para el nuevo Space
        var currentVideoTime: CMTime? = nil
        if let firstInstance = desktopVideoInstances.first {
            currentVideoTime = firstInstance.window.getCurrentTime()
        }
        
        // Generar nuevo frame para el Space actual
        if let staticImageURL = await generateStaticWallpaperFrame(for: accessibleURL, timeOffset: currentVideoTime) {
            setSystemStaticWallpaper(imageURL: staticImageURL)
            appLogger.info("🔄 Frame estático actualizado por cambio de Space - tiempo: \(currentVideoTime.map { "\(CMTimeGetSeconds($0))s" } ?? "inicial")")
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
        await setActiveVideo(nextVideo)
        
        if isPlayingWallpaper {
            startWallpaperSafe()
        }
    }
    
    // MARK: - Manual Next Wallpaper & Random Play Control
    
    /// Cambia manualmente al siguiente wallpaper disponible para reproducción aleatoria
    func nextWallpaper() async {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        
        guard enabledVideos.count > 1 else {
            appLogger.warning("⚠️ No hay suficientes wallpapers habilitados para cambio manual")
            return
        }
        
        guard let currentVideo = currentVideo,
              let currentIndex = enabledVideos.firstIndex(where: { $0.id == currentVideo.id }) else {
            // Si el video actual no está en la lista habilitada, ir al primer habilitado
            if let firstEnabled = enabledVideos.first {
                appLogger.info("🔄 Cambiando manualmente al primer wallpaper habilitado: \(firstEnabled.name)")
                await setActiveVideo(firstEnabled)
                
                if isPlayingWallpaper {
                    startWallpaperSafe()
                }
            }
            return
        }
        
        let nextIndex = (currentIndex + 1) % enabledVideos.count
        let nextVideo = enabledVideos[nextIndex]
        
        appLogger.info("🔄 Cambiando manualmente a: \(nextVideo.name)")
        await setActiveVideo(nextVideo)
        
        if isPlayingWallpaper {
            startWallpaperSafe()
        }
    }
    
    /// Comprueba si el botón "Siguiente Wallpaper" debe estar habilitado
    var canGoToNextWallpaper: Bool {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        return isAutoChangeEnabled && enabledVideos.count > 1
    }
    
    /// Alterna el estado de habilitación para reproducción aleatoria de un video específico
    func toggleVideoRandomPlayEnabled(_ video: VideoFile) {
        guard let index = videoFiles.firstIndex(where: { $0.id == video.id }) else { return }
        
        videoFiles[index].isEnabledForRandomPlay.toggle()
        let newState = videoFiles[index].isEnabledForRandomPlay
        
        appLogger.info("🎯 Video '\(video.name)' \(newState ? "habilitado" : "deshabilitado") para reproducción aleatoria")
        
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
    
    /// Guarda la lista de videos en UserDefaults
    func saveVideos() {
        let videoData = videoFiles.compactMap { video in
            try? JSONEncoder().encode(video)
        }
        userDefaults.set(videoData, forKey: videosKey)
    }
    
    private func loadSavedVideos() {
        guard let videoDataArray = userDefaults.array(forKey: videosKey) as? [Data] else { return }
        
        let videos = videoDataArray.compactMap { data in
            try? JSONDecoder().decode(VideoFile.self, from: data)
        }
        
        DispatchQueue.main.async {
            self.videoFiles = videos
            self.appLogger.info("📂 Cargados \(videos.count) videos guardados")
            self.syncActiveVideoState()
        }
    }
    
    private func saveCurrentVideo() {
        if let currentVideo = currentVideo,
           let data = try? JSONEncoder().encode(currentVideo) {
            userDefaults.set(data, forKey: currentVideoKey)
        }
    }
    
    private func loadCurrentVideo() {
        guard let data = userDefaults.data(forKey: currentVideoKey),
              let video = try? JSONDecoder().decode(VideoFile.self, from: data) else { return }
        
        DispatchQueue.main.async {
            self.currentVideo = video
            self.syncActiveVideoState()
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
    
    private func loadAutoChangeSettings() {
        isAutoChangeEnabled = userDefaults.bool(forKey: "AutoChangeEnabled")
        autoChangeInterval = userDefaults.double(forKey: "AutoChangeInterval")
        if autoChangeInterval <= 0 {
            autoChangeInterval = 10 * 60 // Default 10 minutos
        }
    }
    
    /// Guarda la configuración de cambio automático
    func saveAutoChangeSettings() {
        userDefaults.set(isAutoChangeEnabled, forKey: "AutoChangeEnabled")
        userDefaults.set(autoChangeInterval, forKey: "AutoChangeInterval")
        
        appLogger.info("💾 Guardando configuración: enabled=\(isAutoChangeEnabled), interval=\(Int(autoChangeInterval))s")
        
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
        
        guard let accessibleURL = resolveBookmark(for: currentVideo) else {
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
        
        // Aplicar en intervalos para asegurar que cubra todos los Spaces posibles
        let intervals: [TimeInterval] = [2.0, 5.0, 10.0, 15.0]
        
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
                    self.startWallpaperSafe() // Recrear ventanas para nueva configuración
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
    
    /// Configura la detección de aplicaciones fullscreen
    private func setupFullscreenDetection() {
        appLogger.info("🔍 Configurando detección de fullscreen")
        
        // Configurar callbacks del detector
        fullscreenDetector.onFullscreenEntered = { [weak self] appName in
            Task { @MainActor in
                await self?.handleFullscreenEntered(appName: appName)
            }
        }
        
        fullscreenDetector.onFullscreenExited = { [weak self] in
            Task { @MainActor in
                await self?.handleFullscreenExited()
            }
        }
        
        appLogger.info("✅ Detección de fullscreen configurada")
    }
    
    /// Maneja cuando una aplicación entra en fullscreen
    private func handleFullscreenEntered(appName: String) async {
        appLogger.info("🎮 Aplicación en fullscreen detectada: \(appName)")
        
        guard isAutoChangeEnabled && isPlayingWallpaper else {
            appLogger.debug("💡 No hay timer activo, no se requiere pausar")
            return
        }
        
        // Pausar el timer de cambio automático
        if timerManager.isTimerActive && !timerManager.isPaused {
            appLogger.info("⏸️ Pausando timer de wallpaper por fullscreen")
            timerManager.pauseTimer()
            isWallpaperPausedForFullscreen = true
            
            // Opcional: También pausar reproductores de video para ahorrar recursos
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
    
    /// Pausa los reproductores de video durante fullscreen para ahorrar recursos
    private func pauseVideoPlayersForFullscreen() async {
        appLogger.info("⏸️ Pausando reproductores de video por fullscreen")
        
        for (window, _) in desktopVideoInstances {
            if let playerLayer = window.playerLayer {
                playerLayer.player?.pause()
            }
        }
    }
    
    /// Reanuda los reproductores de video después de fullscreen
    private func resumeVideoPlayersFromFullscreen() async {
        appLogger.info("▶️ Resumiendo reproductores de video después de fullscreen")
        
        for (window, _) in desktopVideoInstances {
            if let playerLayer = window.playerLayer {
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
            // Reinicio optimizado: primero verificar pantallas y luego iniciar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Verificar que aún tenemos un video actual
                guard let currentVideo = self.currentVideo else { return }
                
                // Pre-resolver el bookmark para reducir latencia
                guard let accessibleURL = self.resolveBookmark(for: currentVideo) else {
                    self.appLogger.error("❌ No se pudo resolver bookmark al despertar")
                    return
                }
                
                // Crear ventanas inmediatamente con URL ya resuelta
                self.createDesktopWindows(for: currentVideo, accessibleURL: accessibleURL)
                self.isPlayingWallpaper = true
                self.startAutoChangeTimerIfNeeded()
            }
        }
    }
    
    @objc private func activeSpaceDidChange(notification: NSNotification) {
        appLogger.info("🔄 Space activo cambió - actualizando frame estático con tiempo actual del video")
        
        // Pequeño delay para asegurar que el Space está completamente cargado
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await self.updateStaticFrameOnSpaceChange()
        }
    }
    
    private func setupTerminationHandling() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.cleanupAllResources()
        }
    }
    
    nonisolated private func cleanupAllResources() {
        appLogger.info("🧹 Limpiando todos los recursos")
        stopAutoChangeTimer()
        
        // Limpiar wallpaper estático temporal
        Task { @MainActor in
            cleanupPreviousStaticWallpaper()
            
            // Cerrar todas las ventanas y liberar recursos
            for (window, accessibleURL) in desktopVideoInstances {
                window.close()
                safeStopSecurityScopedAccess(for: accessibleURL)
            }
            desktopVideoInstances.removeAll()
        }
        
        // Liberar cualquier URL security-scoped restante
        Task { @MainActor in
            self.activeSecurityScopedURLs.removeAll()
        }
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
        
        // Guardar configuración actual
        let originalEnabled = isAutoChangeEnabled
        let originalInterval = autoChangeInterval
        
        // Configurar para prueba rápida
        isAutoChangeEnabled = true
        autoChangeInterval = 5.0 // 5 segundos para prueba
        
        // Iniciar timer de prueba
        startAutoChangeTimerIfNeeded()
        
        // Programar restauración después de 20 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
            self.appLogger.info("🧪 Finalizando prueba de timer, restaurando configuración")
            self.isAutoChangeEnabled = originalEnabled
            self.autoChangeInterval = originalInterval
            self.saveAutoChangeSettings()
        }
    }
}

// MARK: - Final del archivo
