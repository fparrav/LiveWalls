import Foundation
import AppKit
import Combine
import AVFoundation
import os.log

// Asegurarse de que Logger esté disponible
#if canImport(os)
import os
#endif

// Logger específico para debugging de memoria
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

/// Gestor principal de fondos de pantalla en video para LiveWalls
/// Maneja la reproducción, cambio y configuración de videos como fondo de escritorio
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
    private var autoChangeTimer: Timer?
    
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
    private let wallpaperOperationSemaphore = DispatchSemaphore(value: 1)
    private var isChangingVideo = false
    private var isCleaningUp = false
    
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
        stopAutoChangeTimer()
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
    func addVideoFiles(urls: [URL]) {
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
                let thumbnail = generateThumbnail(for: url)
                
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
    private func generateThumbnail(for url: URL) -> Data? {
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
    
    /// Establece un video como activo (wallpaper actual)
    /// - Parameter video: VideoFile a establecer como activo
    func setActiveVideo(_ video: VideoFile) {
        DispatchQueue.main.async {
            self.appLogger.info("🎯 Estableciendo video activo: \(video.name)")
            
            // Actualizar el estado isActive de todos los videos y forzar actualización de UI
            var updatedVideos = self.videoFiles
            for i in 0..<updatedVideos.count {
                updatedVideos[i].isActive = (updatedVideos[i].id == video.id)
            }
            self.videoFiles = updatedVideos // Esto fuerza la actualización de @Published
            
            self.currentVideo = video
            self.saveCurrentVideo()
            
            self.appLogger.info("✅ Video activo establecido: \(video.name)")
        }
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
        
        wallpaperOperationQueue.async {
            self.wallpaperOperationSemaphore.wait()
            defer { self.wallpaperOperationSemaphore.signal() }
            
            self.appLogger.info("▶️ Iniciando wallpaper: \(currentVideo.name)")
            
            guard let accessibleURL = self.resolveBookmark(for: currentVideo) else {
                DispatchQueue.main.async {
                    self.notificationManager.showError(message: "No se pudo acceder al archivo de video")
                }
                return
            }
            
            DispatchQueue.main.async {
                self.createDesktopWindows(for: currentVideo, accessibleURL: accessibleURL)
                self.isPlayingWallpaper = true
                self.startAutoChangeTimerIfNeeded()
            }
        }
    }
    
    /// Detiene la reproducción del wallpaper
    func stopWallpaper() {
        wallpaperOperationQueue.async {
            self.wallpaperOperationSemaphore.wait()
            defer { self.wallpaperOperationSemaphore.signal() }
            
            self.appLogger.info("⏹️ Deteniendo wallpaper")
            
            DispatchQueue.main.async {
                self.stopAutoChangeTimer()
                self.destroyAllDesktopWindows {
                    self.isPlayingWallpaper = false
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
            resourceTrackingQueue.async(flags: .barrier) {
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
            
            // Usar RunLoop en lugar de Thread.sleep para no bloquear
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
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
        
        resourceTrackingQueue.async(flags: .barrier) {
            if self.activeSecurityScopedURLs.contains(normalizedPath) {
                self.activeSecurityScopedURLs.remove(normalizedPath)
                DispatchQueue.main.async {
                    url.stopAccessingSecurityScopedResource()
                    self.appLogger.debug("🔓 Liberado acceso security-scoped: \(normalizedPath)")
                }
            }
        }
    }
    
    // MARK: - Auto Change Timer
    
    private func startAutoChangeTimerIfNeeded() {
        guard isAutoChangeEnabled, autoChangeInterval > 0, videoFiles.count > 1 else { return }
        
        stopAutoChangeTimer()
        
        autoChangeTimer = Timer.scheduledTimer(withTimeInterval: autoChangeInterval, repeats: true) { _ in
            self.changeToNextVideo()
        }
        
        appLogger.info("⏰ Timer de cambio automático iniciado (\(Int(self.autoChangeInterval))s)")
    }
    
    private func stopAutoChangeTimer() {
        autoChangeTimer?.invalidate()
        autoChangeTimer = nil
    }
    
    private func changeToNextVideo() {
        guard let currentVideo = currentVideo,
              let currentIndex = videoFiles.firstIndex(where: { $0.id == currentVideo.id }) else { return }
        
        let nextIndex = (currentIndex + 1) % videoFiles.count
        let nextVideo = videoFiles[nextIndex]
        
        appLogger.info("🔄 Cambiando automáticamente a: \(nextVideo.name)")
        setActiveVideo(nextVideo)
        
        if isPlayingWallpaper {
            startWallpaperSafe()
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
        
        if isAutoChangeEnabled {
            startAutoChangeTimerIfNeeded()
        } else {
            stopAutoChangeTimer()
        }
    }
    
    /// Función para compatibilidad con ContentView - llama a stopWallpaper()
    func stopWallpaperSafe() {
        stopWallpaper()
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
            self.appLogger.info("🖥️ Configuración de pantalla cambió")
            if self.isPlayingWallpaper {
                self.startWallpaperSafe() // Recrear ventanas para nueva configuración
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
            // Se reinicia inmediatamente para una transición más rápida.
            self.startWallpaperSafe()
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
    
    private func cleanupAllResources() {
        appLogger.info("🧹 Limpiando todos los recursos")
        stopAutoChangeTimer()
        
        // Cerrar todas las ventanas y liberar recursos
        for (window, accessibleURL) in desktopVideoInstances {
            window.close()
            safeStopSecurityScopedAccess(for: accessibleURL)
        }
        desktopVideoInstances.removeAll()
        
        // Liberar cualquier URL security-scoped restante
        resourceTrackingQueue.async(flags: .barrier) {
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

// MARK: - Final del archivo
