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
    @Published var shouldAutoPlayOnSelection = false
    
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
        
        appLogger.info("🏗️ Inicializando WallpaperManager")
        
        // Cargar configuración y datos guardados
        loadSavedVideos()
        loadCurrentVideo()
        loadAutoChangeSettings()
        setupScreenChangeNotifications()
        setupTerminationHandling()
        
        // Auto-start solo si está configurado
        if !videoFiles.isEmpty && currentVideo != nil && UserDefaults.standard.bool(forKey: "AutoStartWallpaper") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startWallpaperSafe()
            }
        }
        
        appLogger.info("✅ WallpaperManager inicializado correctamente")
    }
    
    deinit {
        appLogger.info("🔄 Deinicializando WallpaperManager")
        stopAutoChangeTimer()
        cleanupAllResources()
    }
    
    // MARK: - Video Management
    
    /// Agrega archivos de video a la lista de wallpapers disponibles
    /// - Parameter urls: URLs de los archivos de video a agregar
    func addVideoFiles(urls: [URL]) {
        appLogger.info("📁 Agregando \(urls.count) archivos de video")
        
        for url in urls {
            // Crear bookmark security-scoped
            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                let videoFile = VideoFile(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    bookmarkData: bookmarkData
                )
                
                DispatchQueue.main.async {
                    self.videoFiles.append(videoFile)
                    self.saveVideos()
                    self.appLogger.info("✅ Video agregado: \(videoFile.name)")
                }
                
            } catch {
                appLogger.error("❌ Error creando bookmark para \(url.lastPathComponent): \(error)")
            }
        }
    }
    
    /// Establece un video como activo (wallpaper actual)
    /// - Parameter video: VideoFile a establecer como activo
    func setActiveVideo(_ video: VideoFile) {
        DispatchQueue.main.async {
            self.appLogger.info("🎯 Estableciendo video activo: \(video.name)")
            self.currentVideo = video
            self.saveCurrentVideo()
            
            if self.shouldAutoPlayOnSelection {
                self.startWallpaperSafe()
            }
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
            
            // Pequeña pausa entre ventanas
            Thread.sleep(forTimeInterval: 0.1)
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
        
        for (window, accessibleURL) in instancesToDestroy {
            window.close()
            
            // Liberar acceso security-scoped con retraso
            DispatchQueue.main.asyncAfter(deadline: .now() + resourceReleaseDelay) {
                self.safeStopSecurityScopedAccess(for: accessibleURL)
            }
        }
        
        completion()
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
        }
    }
    
    private func loadAutoChangeSettings() {
        isAutoChangeEnabled = userDefaults.bool(forKey: "AutoChangeEnabled")
        autoChangeInterval = userDefaults.double(forKey: "AutoChangeInterval")
        if autoChangeInterval <= 0 {
            autoChangeInterval = 10 * 60 // Default 10 minutos
        }
        shouldAutoPlayOnSelection = userDefaults.bool(forKey: "AutoPlayOnSelection")
    }
    
    /// Guarda la configuración de cambio automático
    func saveAutoChangeSettings() {
        userDefaults.set(isAutoChangeEnabled, forKey: "AutoChangeEnabled")
        userDefaults.set(autoChangeInterval, forKey: "AutoChangeInterval")
        userDefaults.set(shouldAutoPlayOnSelection, forKey: "AutoPlayOnSelection")
        
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
        
        // Establecer como video actual e iniciar
        setActiveVideo(video)
        startWallpaperSafe()
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
