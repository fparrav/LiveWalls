import Foundation
import AppKit
import AVFoundation
import UserNotifications
import CoreMedia
import os.log

// Importación del logger específico para debugging de memoria en WallpaperManager

// Logger específico para debugging de memoria en WallpaperManager
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "WallpaperManagerMemory")

class WallpaperManager: ObservableObject {
    @Published var videoFiles: [VideoFile] = []
    @Published var currentVideo: VideoFile?
    @Published var isPlayingWallpaper = false
    
    // private var desktopWindows: [DesktopVideoWindowMejorada] = // Modificado
    private var desktopVideoInstances: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)] = [] // Nuevo
    /// Retardo (en segundos) antes de liberar el acceso security-scoped tras cerrar una ventana.
    /// Ajusta este valor si observas problemas de recursos o race conditions.
    private let resourceReleaseDelay: TimeInterval = 0.1
    private let userDefaults = UserDefaults.standard
    private let videosKey = "SavedVideos"
    private let currentVideoKey = "CurrentVideo"
    private let notificationManager = NotificationManager.shared
    
    // MARK: - Security-Scoped Resource Tracking
    /// Tracking de URLs que tienen acceso security-scoped activo para prevenir double-stop crashes
    /// Usamos el path absoluto normalizado como clave para evitar problemas de comparación de URLs
    private var activeSecurityScopedURLs: Set<String> = []
    private let resourceTrackingQueue = DispatchQueue(label: "security.resources", attributes: .concurrent)
    
    // MARK: - Sincronización para prevenir crashes durante cambio de videos
    /// Queue serial para operaciones críticas de wallpaper que deben ejecutarse una a la vez
    private let wallpaperOperationQueue = DispatchQueue(label: "wallpaper.operations", qos: .userInitiated)
    /// Semáforo para prevenir operaciones concurrentes de start/stop wallpaper
    private let wallpaperOperationSemaphore = DispatchSemaphore(value: 1)
    /// Flag para rastrear si hay una operación de cambio de video en progreso
    private var isChangingVideo = false
    
    init() {
        loadSavedVideos()
        loadCurrentVideo() // loadCurrentVideo ya verifica si el video existe en la lista
        setupScreenChangeNotifications()
        
        // Auto-start solo si hay videos disponibles y un video actual seleccionado
        if !videoFiles.isEmpty && currentVideo != nil && UserDefaults.standard.bool(forKey: "AutoStartWallpaper") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startWallpaper()
            }
        } else if videoFiles.isEmpty && UserDefaults.standard.bool(forKey: "AutoStartWallpaper") {
            // Si la lista está vacía pero se esperaba auto-start, desactivar el setting
            print("⚠️ Auto-start desactivado porque la lista de videos está vacía")
            UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
        }
    }
    
    // MARK: - Testing Helpers
    
    private func loadTestingVideos() {
        print("🧪 Cargando videos de testing automáticamente...")
        let testingPath = "/Users/felipe/Livewall/"
        
        guard let enumerator = FileManager.default.enumerator(atPath: testingPath) else {
            print("⚠️ No se pudo acceder a la carpeta de testing: \(testingPath)")
            return
        }
        
        var testUrls: [URL] = []
        
        for case let file as String in enumerator {
            if file.hasSuffix(".mp4") || file.hasSuffix(".mov") {
                let fileURL = URL(fileURLWithPath: testingPath + file)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    testUrls.append(fileURL)
                    print("🎬 Encontrado video de testing: \(file)")
                }
            }
        }
        
        if !testUrls.isEmpty {
            print("🎯 Cargando \(testUrls.count) videos de testing...")
            addVideoFiles(urls: testUrls)
            
            // Seleccionar automáticamente el primer video para testing
            if let firstVideo = videoFiles.first {
                setActiveVideo(firstVideo)
                print("✅ Video de testing seleccionado: \(firstVideo.name)")
            }
        } else {
            print("⚠️ No se encontraron videos de testing en \(testingPath)")
        }
    }
    
    // MARK: - Video Management
    
    func addVideoFiles(urls: [URL]) {
        for url in urls {
            // Verificar que el archivo sea un video soportado
            guard url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" else {
                print("Archivo no soportado: \(url.lastPathComponent)")
                continue
            }

            // Iniciar el acceso al security-scoped resource de forma segura
            guard safeStartSecurityScopedAccess(for: url) else {
                print("⚠️ No se pudo iniciar el acceso al security-scoped resource para: \(url.path)")
                continue
            }

            // Verificar que el archivo exista y sea accesible
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("Archivo no encontrado: \(url.path)")
                safeStopSecurityScopedAccess(for: url) // Detener el acceso si el archivo no existe
                continue
            }

            // Verificar que no esté ya en la lista
            guard !videoFiles.contains(where: { $0.url.path == url.path }) else { // Comparar por path para evitar problemas con bookmarks
                print("Video ya existe: \(url.lastPathComponent)")
                safeStopSecurityScopedAccess(for: url) // Detener el acceso si ya existe
                continue
            }

            var bookmarkData: Data?
            do {
                bookmarkData = try url.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                print("🔖 Bookmark creado para: \(url.lastPathComponent)")
            } catch {
                print("❌ Error al crear bookmark para \(url.path): \(error.localizedDescription)")
                safeStopSecurityScopedAccess(for: url) // Detener el acceso si falla la creación del bookmark
                continue // No añadir el video si no se puede crear el bookmark
            }

            // Es importante detener el acceso después de crear el bookmark si no se va a usar la URL inmediatamente.
            // Se volverá a iniciar el acceso cuando se necesite reproducir el video.
            safeStopSecurityScopedAccess(for: url)

            let videoFile = VideoFile(url: url, bookmarkData: bookmarkData) // Guardar el bookmarkData
            videoFiles.append(videoFile)
            generateThumbnail(for: videoFile) // generateThumbnail también necesitará resolver el bookmark
            print("Video agregado: \(videoFile.name)")
        }
        saveVideos()
    }
    
    func removeVideo(_ video: VideoFile) {
        if currentVideo?.id == video.id {
            stopWallpaper()
        }
        videoFiles.removeAll { $0.id == video.id }
        saveVideos()
    }
    
    func setActiveVideo(_ video: VideoFile) {
        wallpaperOperationQueue.async { [weak self] in
            guard let self = self else { return }

            self.wallpaperOperationSemaphore.wait() // Adquirir semáforo

            self.isChangingVideo = true // Marcar inicio de cambio

            let currentlyPlaying = self.isPlayingWallpaper
            
            DispatchQueue.main.async {
                // Capturar la URL del video anterior ANTES de actualizar self.currentVideo
                let previousVideoURL = self.currentVideo?.url

                if let currentIndex = self.videoFiles.firstIndex(where: { $0.isActive }) {
                    self.videoFiles[currentIndex].isActive = false
                }
                if let newIndex = self.videoFiles.firstIndex(where: { $0.id == video.id }) {
                    self.videoFiles[newIndex].isActive = true
                    self.currentVideo = self.videoFiles[newIndex] // self.currentVideo ahora es el NUEVO video
                    self.saveCurrentVideo()
                    print("🔄 Video activo cambiado a: \(video.name)")

                    if currentlyPlaying {
                        print("🔄 Transición de wallpaper requerida para \(video.name).")
                        // Pasar previousVideoURL a stopWallpaperInternal
                        self.stopWallpaperInternal(urlToRelease: previousVideoURL) { // MODIFICADO
                            // Asegurarse de que el video actual sigue siendo el que queremos iniciar
                            if self.currentVideo?.id == video.id {
                                print("▶️ Iniciando nuevo wallpaper después de la transición: \(video.name)")
                                self.startWallpaperInternal { success in
                                    if success {
                                        print("✅ Transición de video completada a: \(video.name)")
                                    } else {
                                        memoryLogger.error("❌ Falló la transición de video a: \(video.name)")
                                    }
                                    self.isChangingVideo = false // Finalizar el cambio
                                    self.wallpaperOperationSemaphore.signal() // Liberar semáforo
                                }
                            } else {
                                print("⚠️ Transición abortada: el video actual cambió (\(self.currentVideo?.name ?? "nil")) durante la detención del anterior (\(video.name)).")
                                self.isChangingVideo = false
                                self.wallpaperOperationSemaphore.signal()
                            }
                        }
                    } else {
                        // Si no se estaba reproduciendo, solo actualizamos el video y liberamos.
                        self.isChangingVideo = false
                        self.wallpaperOperationSemaphore.signal()
                    }
                } else {
                    // No se encontró el nuevo video.
                    print("❌ No se encontró el video \(video.name) en la lista para activar.")
                    self.isChangingVideo = false
                    self.wallpaperOperationSemaphore.signal()
                }
            }
        }
    }

    // MARK: - Wallpaper Control

    func setRandomWallpaper() {
        guard !videoFiles.isEmpty else {
            notificationManager.showError(message: "No videos available to set a random wallpaper.")
            return
        }

        guard let randomVideo = videoFiles.randomElement() else {
            return // This case will never occur because videoFiles is not empty.
        }

        setActiveVideo(randomVideo)
        // If wallpaper was already playing, or if setActiveVideo started it (e.g. if it was already the current video),
        // ensure the new random one plays immediately.
        // Checking isPlayingWallpaper ensures we don't start it if it was previously stopped.
        if isPlayingWallpaper {
            startWallpaper()
        }
    }
    
    func startWallpaper() {
        wallpaperOperationQueue.async { [weak self] in
            guard let self = self else { return }
            self.wallpaperOperationSemaphore.wait()
            // Reiniciar el flag isChangingVideo si se llama directamente a startWallpaper
            self.isChangingVideo = false 
            self.startWallpaperInternal { success in
                // Manejar el resultado si es necesario para la llamada externa
                if !success && self.isPlayingWallpaper { // Solo cambiar si falló Y estaba reproduciendo
                     DispatchQueue.main.async { self.isPlayingWallpaper = false }
                }
                self.wallpaperOperationSemaphore.signal()
            }
        }
    }

    private func startWallpaperInternal(completion: @escaping (Bool) -> Void) {
        // El flag isChangingVideo es más para la lógica de transición.
        // Si se llama a start directamente, no debería estar "cambiando".
        // Sin embargo, si una transición está en curso y currentVideo es nil, evitamos.
        if isChangingVideo && self.currentVideo == nil { // Asegurarse que currentVideo no sea nil durante un cambio
             print("⚠️ Inicio de wallpaper cancelado: cambio de video en progreso sin un video actual claro.")
             completion(false)
             return
        }

        guard let videoToPlay = self.currentVideo else {
            DispatchQueue.main.async {
                self.notificationManager.showError(message: "No hay ningún video seleccionado")
            }
            completion(false)
            return
        }

        // Primero, asegurar que cualquier ventana existente sea destruida.
        // Esto es crucial si startWallpaperInternal es llamado sin un stop previo explícito
        // o si un stop anterior falló en limpiar completamente.
        // Usaremos la URL del video que *estaba* currentVideo *antes* de esta operación de start,
        // que en este contexto (si no es una transición) es el mismo videoToPlay.
        // Sin embargo, destroyDesktopWindowsInternal ahora toma la URL explícitamente.
        // Si estamos en una transición, stopWallpaperInternal ya se encargó.
        // Si es un inicio directo, y había algo, ¿qué URL liberar?
        // Por seguridad, si isPlayingWallpaper es true (o había instancias), se debería haber llamado a stop.
        // Aquí, nos enfocamos en iniciar. La limpieza previa es responsabilidad del llamador o de la lógica de transición.

        guard let accessibleURL = self.resolveBookmark(for: videoToPlay) else {
            DispatchQueue.main.async {
                self.notificationManager.showError(message: "No se pudo acceder al archivo de video: \\(videoToPlay.name). Por favor, selecciónelo de nuevo o verifique los permisos.")
            }
            completion(false)
            return
        }

        guard FileManager.default.fileExists(atPath: accessibleURL.path) else {
            DispatchQueue.main.async {
                self.notificationManager.showError(message: "El archivo de video no se encuentra: \\(videoToPlay.name) (ruta accesible: \\(accessibleURL.path))")
            }
            self.safeStopSecurityScopedAccess(for: accessibleURL) // Detener si se inició y el archivo no existe
            completion(false)
            return
        }

        // La destrucción de ventanas anteriores ya debe haber ocurrido ANTES de llamar a startWallpaperInternal
        // si esto es parte de una transición (setActiveVideo).
        // Si es un inicio directo (startWallpaper()), y algo estaba corriendo, stopWallpaper() debió ser llamado.
        DispatchQueue.main.async {
            // Este retardo puede ayudar a asegurar que el sistema esté listo para nuevas ventanas,
            // especialmente después de una operación de destrucción. Un valor pequeño debería ser suficiente.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { 
                if FileManager.default.fileExists(atPath: accessibleURL.path) {
                    // Solo marcar isPlayingWallpaper = true si realmente vamos a crear ventanas
                    self.isPlayingWallpaper = true 
                    self.createDesktopWindows(for: videoToPlay, accessibleURL: accessibleURL)
                    self.notificationManager.showWallpaperStarted(videoName: videoToPlay.name)
                    UserDefaults.standard.set(true, forKey: "AutoStartWallpaper")
                    print("✅ Wallpaper iniciado exitosamente para: \\(videoToPlay.name)")
                    completion(true)
                } else {
                    print("❌ El archivo \\(accessibleURL.path) dejó de existir antes de crear ventanas.")
                    self.notificationManager.showError(message: "No se pudo acceder al archivo durante el inicio del wallpaper")
                    UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
                    self.safeStopSecurityScopedAccess(for: accessibleURL)
                    // Asegurarse de que isPlayingWallpaper sea false si fallamos aquí
                    self.isPlayingWallpaper = false
                    completion(false)
                }
            }
        }
    }

    func stopWallpaper() {
        wallpaperOperationQueue.async { [weak self] in
            guard let self = self else { return }
            self.wallpaperOperationSemaphore.wait()
            
            // Si no hay currentVideo pero hay ventanas activas, necesitamos una forma de cerrarlas
            var urlToActuallyRelease: URL? = nil
            
            if let videoActual = self.currentVideo {
                urlToActuallyRelease = videoActual.url
                print("🔍 Deteniendo wallpaper con video actual: \(videoActual.name)")
            } else if !self.desktopVideoInstances.isEmpty, let firstInstance = self.desktopVideoInstances.first {
                // Si hay ventanas pero no hay currentVideo, usar la URL del primer instance
                urlToActuallyRelease = firstInstance.accessibleURL
                print("🔍 Deteniendo wallpaper sin video actual, usando URL del primer instance")
            } else {
                print("🔍 Deteniendo wallpaper sin video actual ni instancias")
            }
            
            self.stopWallpaperInternal(urlToRelease: urlToActuallyRelease) {
                self.wallpaperOperationSemaphore.signal()
            }
        }
    }

    // Modificado para aceptar urlToRelease y manejar caso de lista vacía
    private func stopWallpaperInternal(urlToRelease: URL?, completion: (() -> Void)? = nil) {
        print("🛑 [stopWallpaperInternal] iniciado")
        DispatchQueue.main.async {
            let wasPlaying = self.isPlayingWallpaper // Capturar antes de cambiar
            self.isPlayingWallpaper = false // Marcar como no reproduciendo inmediatamente

            // Verificar si hay instancias de ventanas a cerrar
            if self.desktopVideoInstances.isEmpty {
                // No hay ventanas para cerrar, simplemente terminamos
                print("ℹ️ [stopWallpaperInternal] No hay ventanas de fondo para detener")
                if wasPlaying { // Usar el estado capturado
                    self.notificationManager.showWallpaperStopped()
                }
                UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
                print("✅ [stopWallpaperInternal] completado (sin ventanas para cerrar).")
                completion?()
                return
            }

            // Pasar la urlToRelease capturada a destroyDesktopWindowsInternal
            self.destroyDesktopWindowsInternal(urlToRelease: urlToRelease) { // MODIFICADO
                if wasPlaying { // Usar el estado capturado
                    self.notificationManager.showWallpaperStopped()
                }
                UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
                print("✅ [stopWallpaperInternal] completado.")
                completion?()
            }
        }
    }

    func toggleWallpaper() {
        if isPlayingWallpaper {
            stopWallpaper()
        } else {
            startWallpaper()
        }
    }
    
    // MARK: - Funciones síncronas internas para toggleWallpaper
    
    /// Versión síncrona interna de startWallpaper que no usa queue ni semáforo
    /// (porque ya está siendo llamada desde dentro del queue serializado)
    private func startWallpaperSync() {
        // Esta función parece ser una versión síncrona para toggleWallpaper.
        // Debería idealmente reutilizar la lógica de startWallpaperInternal
        // o ser eliminada si toggleWallpaper puede usar la versión asíncrona.
        // Por ahora, la dejamos como estaba pero advertimos que su lógica de limpieza
        // y creación podría no estar tan sincronizada como la nueva startWallpaperInternal.
        // Para mayor seguridad, podría llamar a startWallpaperInternal y bloquear
        // la cola actual si es estrictamente necesario que sea síncrona,
        // pero eso puede llevar a deadlocks si no se maneja con cuidado.
        // Considerar refactorizar toggleWallpaper para que sea completamente asíncrono.
        print("⚠️ [startWallpaperSync] está siendo llamada. Considerar refactorizar toggleWallpaper.")
        guard let videoToPlay = self.currentVideo else {
            DispatchQueue.main.async {
                self.notificationManager.showError(message: "No hay ningún video seleccionado")
            }
            return
        }

        guard let accessibleURL = self.resolveBookmark(for: videoToPlay) else {
            DispatchQueue.main.async {
                self.notificationManager.showError(message: "No se pudo acceder al archivo de video: \(videoToPlay.name). Por favor, selecciónelo de nuevo o verifique los permisos.")
            }
            return
        }

        // Verificar que el archivo existe
        guard FileManager.default.fileExists(atPath: accessibleURL.path) else {
            DispatchQueue.main.async {
                self.notificationManager.showError(message: "El archivo de video no se encuentra: \(videoToPlay.name) (ruta accesible: \(accessibleURL.path))")
            }
            accessibleURL.stopAccessingSecurityScopedResource()
            return
        }

        // Realizar operaciones de UI en el hilo principal
        DispatchQueue.main.async {
            // Destruir ventanas existentes si hay alguna
            self.destroyDesktopWindows()
            
            // Esperar un poco para asegurar que las ventanas se han liberado
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Verificar nuevamente que accessibleURL es válido
                if FileManager.default.fileExists(atPath: accessibleURL.path) {
                    self.isPlayingWallpaper = true
                    self.createDesktopWindows(for: videoToPlay, accessibleURL: accessibleURL)
                    self.notificationManager.showWallpaperStarted(videoName: videoToPlay.name)
                    UserDefaults.standard.set(true, forKey: "AutoStartWallpaper")
                    print("✅ [startWallpaperSync] Wallpaper iniciado exitosamente para: \(videoToPlay.name)")
                } else {
                    self.notificationManager.showError(message: "No se pudo acceder al archivo durante el inicio del wallpaper")
                    UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
                    // Detener acceso al recurso si ya no es válido
                    accessibleURL.stopAccessingSecurityScopedResource()
                }
            }
        }
    }
    
    /// Versión síncrona interna de stopWallpaper que no usa queue ni semáforo
    /// (porque ya está siendo llamada desde dentro del queue serializado)
    private func stopWallpaperSync() {
        // Similar a startWallpaperSync, considerar refactorizar.
        print("⚠️ [stopWallpaperSync] está siendo llamada. Considerar refactorizar toggleWallpaper.")
        
        print("🛑 [stopWallpaperSync] iniciado")
        
        // Actualizar el estado en el hilo principal
        DispatchQueue.main.async {
            self.isPlayingWallpaper = false
            self.destroyDesktopWindows()
            self.notificationManager.showWallpaperStopped()
            UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
            print("✅ [stopWallpaperSync] completado exitosamente")
        }
    }
    
    // MARK: - Desktop Windows Management
    
    private func createDesktopWindows(for video: VideoFile, accessibleURL: URL) { // Modificado para aceptar accessibleURL
        let screens = NSScreen.screens
        print("🖥️ Creando ventanas para \(screens.count) pantalla(s)")
        
        // La limpieza principal ahora la hace startWallpaperInternal -> destroyDesktopWindowsInternal ANTES de este punto.
        // Esta verificación es una doble seguridad.
        if !desktopVideoInstances.isEmpty {
            print("⚠️ createDesktopWindows llamado pero desktopVideoInstances no estaba vacío. Esto no debería ocurrir si la lógica de stop/start es correcta.")
            // No llamamos a destroy aquí para evitar bucles o limpiezas no deseadas si hay un error lógico previo.
        }

        for (index, screen) in screens.enumerated() {
            print("📺 Pantalla \(index + 1): \(screen.localizedName) - \(screen.frame)")
            let window = DesktopVideoWindowMejorada(screen: screen, videoURL: accessibleURL)
            self.desktopVideoInstances.append((window: window, accessibleURL: accessibleURL))
            
            window.orderBack(nil as NSWindow?)
            print("✅ Ventana \(index + 1) creada y posicionada")
        }
        
        print("🎬 Total de ventanas creadas: \(desktopVideoInstances.count)")
    }
    
    /// Destruye todas las ventanas de video de escritorio de forma segura.
    /// Implementa mejor sincronización para evitar race conditions.
    private func destroyDesktopWindows() {
        // Esta es la versión pública que podría ser llamada desde otros lugares.
        // Debería usar el queue y el semáforo para seguridad.
        print("💥 [destroyDesktopWindows] Solicitud pública para destruir ventanas.")
        wallpaperOperationQueue.async { [weak self] in
            guard let self = self else { return }
            self.wallpaperOperationSemaphore.wait()
            // Capturar la URL del video actual aquí para la versión pública
            let urlToActuallyRelease = self.currentVideo?.url
            self.destroyDesktopWindowsInternal(urlToRelease: urlToActuallyRelease) { // MODIFICADO
                self.wallpaperOperationSemaphore.signal()
            }
        }
    }

    /**
     * Destruye todas las ventanas de video de escritorio existentes y libera sus recursos.
     * Esta función ahora utiliza un DispatchGroup para asegurar que todas las operaciones asíncronas
     * (como el cierre de ventanas y la detención del acceso a los recursos) se completen antes de llamar al completion handler.
     * - Parameter urlToRelease: La URL del recurso cuyo acceso security-scoped se debe detener. Debería ser la del video que se estaba reproduciendo.
     * - Parameter completion: Bloque a ejecutar cuando todas las ventanas han sido destruidas y los recursos liberados.
     */
    // Modificado para aceptar urlToRelease
    private func destroyDesktopWindowsInternal(urlToRelease: URL?, completion: (() -> Void)? = nil) {
        memoryLogger.info("💥 Iniciando destrucción de ventanas de escritorio internas.")
        let group = DispatchGroup()

        // Usar la urlToRelease pasada, que debería ser la del video que se estaba reproduciendo.
        let capturedUrlToStopAccess = urlToRelease // RENOMBRADO para claridad

        let windowsToClose = self.desktopVideoInstances 
        desktopVideoInstances.removeAll()
        let logMessage = "🧹 Instancias de DesktopVideoWindow eliminadas del seguimiento del manager. Procediendo a cerrarlas."
        memoryLogger.debug("\(logMessage)")

        if windowsToClose.isEmpty {
            memoryLogger.debug("💨 No hay ventanas de escritorio para destruir.")
            
            // Si no hay ventanas para cerrar, verificamos si hay una URL para liberar
            if capturedUrlToStopAccess == nil {
                // Si no hay ventanas NI URL, podemos terminar inmediatamente
                memoryLogger.info("✅ Limpieza de recursos completada (no hay ventanas ni URL para liberar).")
                completion?()
                return
            }
        } else {
            memoryLogger.info("🧹 Cerrando \(windowsToClose.count) ventana(s) de escritorio.")
            for (windowInstance, _) in windowsToClose {
                // El cierre de la ventana se asume síncrono o que no necesitamos esperar su finalización asíncrona aquí
                // para el propósito de este DispatchGroup, que se centra en safeStopSecurityScopedAccess.
                windowInstance.close() 
            }
            memoryLogger.info("✅ Todas las \(windowsToClose.count) ventanas han recibido la orden de cierre.")
        }

        // Entrar al grupo para la operación de detener el acceso al recurso con retraso.
        group.enter()
        DispatchQueue.main.asyncAfter(deadline: .now() + resourceReleaseDelay) {
            if let url = capturedUrlToStopAccess { // Usar la URL capturada/pasada
                memoryLogger.info("⏳ Intentando detener el acceso para la URL (retrasado): \(url.lastPathComponent)")
                self.safeStopSecurityScopedAccess(for: url)
            } else {
                memoryLogger.debug("💨 No hay URL de video (capturada/pasada) para detener el acceso (retrasado).")
            }
            group.leave()
        }

        group.notify(queue: .main) {
            // El log ahora reflejará la URL que realmente se intentó detener (si la hubo)
            if let url = capturedUrlToStopAccess { // Usar la URL capturada/pasada
                 memoryLogger.info("✅ Limpieza de recursos completada (destroyDesktopWindowsInternal) para \(url.lastPathComponent).")
            } else {
                 memoryLogger.info("✅ Limpieza de recursos completada (destroyDesktopWindowsInternal), no se especificó URL para detener.")
            }
            completion?()
        }
    }

    // MARK: - Screen Change Notifications
    
    private func setupScreenChangeNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if self?.isPlayingWallpaper == true {
                self?.restartWallpaper()
            }
        }
    }
    
    private func restartWallpaper() {
        guard currentVideo != nil else { return }
        stopWallpaper()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startWallpaper()
        }
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateThumbnail(for video: VideoFile) {
        guard let accessibleURL = resolveBookmark(for: video) else {
            print("❌ Error al generar thumbnail para \\(video.name): No se pudo resolver el bookmark o acceder a la URL.")
            // Considerar actualizar el estado del video para indicar que la miniatura falló
            // y posiblemente detener el acceso si se inició en resolveBookmark y no se detuvo.
            // Sin embargo, resolveBookmark debería manejar su propio stopAccessing en caso de fallo.
            return
        }

        print("⏳ Generando miniatura para: \(video.name) desde \(accessibleURL.path)")

        let asset = AVAsset(url: accessibleURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        generator.requestedTimeToleranceBefore = CMTime.zero
        generator.requestedTimeToleranceAfter = CMTime.zero
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        generator.generateCGImageAsynchronously(for: time) { [weak self] (cgImage: CGImage?, actualTime: CMTime, error: Error?) in
            // Es crucial detener el acceso al recurso aquí, independientemente del resultado.
            accessibleURL.stopAccessingSecurityScopedResource()
            print("🛑 Acceso detenido para \\(accessibleURL.lastPathComponent) después de intentar generar miniatura.")

            guard let self = self else { return }

            if let error = error {
                print("❌ Error generando miniatura para \(video.name): \(error.localizedDescription)")
                // Si el error es de tipo "decodificación" o "archivo no encontrado", podría ser útil registrarlo.
                if let nsError = error as NSError?, nsError.domain == AVFoundationErrorDomain {
                    print("  Detalles del error AVFoundation: code \(nsError.code), userInfo: \(nsError.userInfo)")
                }
                return
            }
            
            guard let cgImage = cgImage else {
                print("❌ Error generando miniatura para \\(video.name): CGImage es nil, sin error explícito.")
                return
            }
            
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)) // Usar tamaño real de la imagen generada
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) { // Usar .jpeg y añadir factor de compresión

                DispatchQueue.main.async {
                    if let index = self.videoFiles.firstIndex(where: { $0.id == video.id }) {
                        self.videoFiles[index].thumbnailData = jpegData
                        print("✅ Miniatura generada y asignada para \\(video.name)")
                        self.saveVideos() // Guardar videos después de actualizar la miniatura
                    } else {
                        print("⚠️ No se encontró el video \\(video.name) en videoFiles después de generar la miniatura.")
                    }
                }
            } else {
                print("❌ Error convirtiendo CGImage a Data para \\(video.name).")
            }
        }
    }

    // MARK: - Bookmark Resolution Helper

    /// Resuelve el bookmark de un archivo de video y retorna una URL accesible con permisos activos.
    /// - Parameter videoFile: El modelo de video a resolver.
    /// - Returns: URL accesible o nil si falla el acceso o el bookmark.
    func resolveBookmark(for videoFile: VideoFile) -> URL? {
        var mutableVideoFile = videoFile // Copia mutable para actualizar potencialmente bookmarkData

        // Intenta crear un bookmark si no existe
        if mutableVideoFile.bookmarkData == nil {
            print("⚠️ No hay bookmark data para: \\(mutableVideoFile.name). Intentando crear uno nuevo desde la URL original.")
            if mutableVideoFile.url.startAccessingSecurityScopedResource() { // Acceder a la URL original
                do {
                    let newBookmarkData = try mutableVideoFile.url.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    mutableVideoFile.bookmarkData = newBookmarkData // Actualizar la copia mutable

                    // Actualizar el videoFile real en el array videoFiles y guardar
                    if let index = videoFiles.firstIndex(where: { $0.id == mutableVideoFile.id }) {
                        videoFiles[index].bookmarkData = newBookmarkData
                        saveVideos() // Persistir el bookmark recién creado
                        print("✅ Nuevo bookmark creado y guardado para \\(mutableVideoFile.name) desde URL original.")
                    }
                    mutableVideoFile.url.stopAccessingSecurityScopedResource() // Detener el acceso a la URL ORIGINAL
                } catch {
                    print("❌ Error al crear nuevo bookmark para \(mutableVideoFile.name) desde URL original: \(error.localizedDescription)")
                    mutableVideoFile.url.stopAccessingSecurityScopedResource() // Detener el acceso a la URL ORIGINAL si la creación del bookmark falló
                    return nil // No se puede proceder sin un bookmark
                }
            } else {
                print("❌ Acceso directo a URL original falló para: \\(mutableVideoFile.name). No se puede crear bookmark.")
                return nil // No se puede proceder
            }
        }

        // Proceder con el bookmarkData existente o recién creado
        guard let bookmarkData = mutableVideoFile.bookmarkData else {
            print("❌ Error inesperado: bookmarkData sigue siendo nil para \\(mutableVideoFile.name) después del intento de creación.")
            return nil
        }

        var isStale = false
        do {
            var resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: URL.BookmarkResolutionOptions.withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("⚠️ Bookmark para \\(mutableVideoFile.name) está obsoleto. Intentando refrescarlo...")
                // Para refrescar, primero se debe poder acceder a la URL resuelta (aunque esté obsoleta)
                if resolvedURL.startAccessingSecurityScopedResource() {
                    if let newBookmarkData = try? resolvedURL.bookmarkData(options: URL.BookmarkCreationOptions.withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        if let index = videoFiles.firstIndex(where: { $0.id == mutableVideoFile.id }) {
                            videoFiles[index].bookmarkData = newBookmarkData
                            saveVideos() // Guardar el bookmark actualizado
                            print("✅ Bookmark refrescado y guardado para \\(mutableVideoFile.name)")
                            // Actualizar resolvedURL si el bookmark refrescado apunta a una nueva URL (poco común pero posible)
                            // Por ahora, asumimos que la URL resuelta original sigue siendo válida para el acceso después del refresco.
                        }
                    } else {
                        print("❌ No se pudo refrescar el bookmark para \\(mutableVideoFile.name). Se usará el obsoleto si es posible.")
                    }
                    // No detener el acceso aquí si vamos a usar resolvedURL.
                    // Si el refresco falló pero el acceso inicial a resolvedURL (obsoleta) funcionó,
                    // el startAccessingSecurityScopedResource más abajo lo confirmará.
                    // Si el refresco tuvo éxito, el startAccessing... más abajo usará la misma URL (o una nueva si cambió).
                    // Es más seguro detenerlo y volver a iniciarlo abajo.
                    resolvedURL.stopAccessingSecurityScopedResource()
                    // Re-resolver con el bookmarkData potencialmente actualizado (o el mismo si el refresco falló pero se guardó)
                    // Esto asegura que usemos el bookmark más reciente de videoFiles.
                    if let index = videoFiles.firstIndex(where: { $0.id == mutableVideoFile.id }),
                       let refreshedBookmarkData = videoFiles[index].bookmarkData {
                        var refreshedIsStale = false // Esta no debería ser obsoleta ahora
                        resolvedURL = try URL(resolvingBookmarkData: refreshedBookmarkData, options: URL.BookmarkResolutionOptions.withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &refreshedIsStale)
                        if refreshedIsStale {
                             print("‼️ Bookmark para \\(mutableVideoFile.name) sigue obsoleto inmediatamente después de refrescar.")
                        }
                    } else {
                         print("❌ No se pudo encontrar el video o bookmarkData después de intentar refrescar \\(mutableVideoFile.name).")
                         return nil
                    }

                } else {
                     print("❌ No se pudo iniciar acceso para refrescar el bookmark obsoleto de \\(mutableVideoFile.name). Se intentará usar el obsoleto.")
                }
            }

            if resolvedURL.startAccessingSecurityScopedResource() {
                print("✅ Acceso seguro obtenido para: \(resolvedURL.path)")
                return resolvedURL // Esta URL está "activa"
            } else {
                print("❌ No se pudo iniciar el acceso al security-scoped resource para URL resuelta: \(resolvedURL.path)")
                return nil
            }
        } catch {
            print("❌ Error al resolver bookmark para \(mutableVideoFile.name): \(error.localizedDescription)")
            // Considerar eliminar el bookmark inválido para que se intente recrear la próxima vez
            if let index = videoFiles.firstIndex(where: { $0.id == mutableVideoFile.id }) {
                if videoFiles[index].bookmarkData != nil { // Solo si realmente había un bookmark
                    videoFiles[index].bookmarkData = nil
                    saveVideos()
                    print("🗑️ Bookmark inválido eliminado para \\(mutableVideoFile.name). Se intentará recrear la próxima vez.")
                }
            }
            return nil
        }
    }
    
    // MARK: - Persistence
    
    private func saveVideos() {
        if let data = try? JSONEncoder().encode(videoFiles) {
            userDefaults.set(data, forKey: videosKey)
        }
    }
    
    private func loadSavedVideos() {
        if let data = userDefaults.data(forKey: videosKey),
           let videos = try? JSONDecoder().decode([VideoFile].self, from: data) {
            self.videoFiles = videos
            // Opcional: verificar y refrescar bookmarks al cargar si es necesario,
            // aunque resolveBookmark ya maneja la obsolescencia.
        }
    }

    private func saveCurrentVideo() {
        // Asegurarse de que currentVideo tenga la URL original, no la resuelta temporalmente,
        // o que el bookmarkData sea la fuente de verdad.
        // Si currentVideo.url se modifica con la URL resuelta, podría causar problemas al guardar/cargar.
        // Es mejor guardar la URL original y el bookmarkData por separado.
        // La estructura actual de VideoFile ya hace esto.
        if let video = currentVideo,
           let data = try? JSONEncoder().encode(video) {
            userDefaults.set(data, forKey: currentVideoKey)
        }
    }

    private func loadCurrentVideo() {
        if let data = userDefaults.data(forKey: currentVideoKey),
           let video = try? JSONDecoder().decode(VideoFile.self, from: data) {
            // Sólo establecer currentVideo si el video existe en la lista de videos
            // Esto previene intentar usar un video que ya no está en la lista
            if !videoFiles.isEmpty && videoFiles.contains(where: { $0.id == video.id }) {
                // Al cargar, la URL es la original. Necesitamos resolverla antes de usarla.
                // Esto se hará en setActiveVideo o startWallpaper.
                self.currentVideo = video
                print("✅ Cargado video actual: \(video.name)")
            } else {
                print("⚠️ El video guardado no se encuentra en la lista actual o la lista está vacía")
                self.currentVideo = nil
                // Eliminar la referencia guardada para evitar intentos futuros
                userDefaults.removeObject(forKey: currentVideoKey)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopWallpaper()
    }
    
    // MARK: - Utilidades de acceso security-scoped
    /**
     Inicia el acceso security-scoped de forma segura para una URL.
     - Parameter url: URL a la que se desea acceder.
     - Returns: true si el acceso fue exitoso, false en caso contrario.
     */
    private func safeStartSecurityScopedAccess(for url: URL) -> Bool {
        var success = false
        // Usar la cola de tracking para asegurar la consistencia de activeSecurityScopedURLs
        // y la serialización de las llamadas a startAccessingSecurityScopedResource.
        resourceTrackingQueue.sync(flags: .barrier) {
            // Siempre intentar iniciar el acceso. 
            // url.startAccessingSecurityScopedResource() es idempotente si el acceso ya está activo
            // (incrementa un contador de uso).
            if url.startAccessingSecurityScopedResource() {
                print("🔓 Acceso de seguridad INICIADO o YA ACTIVO para: \\(url.lastPathComponent)")
                // Añadir al set para nuestro tracking. Si ya estaba, no hay cambio.
                activeSecurityScopedURLs.insert(url.standardizedFileURL.path)
                success = true
            } else {
                print("❌ Falló al INICIAR acceso de seguridad para: \\(url.lastPathComponent)")
                // Si falla, asegurarse de que no esté (o se elimine) de nuestro tracking.
                activeSecurityScopedURLs.remove(url.standardizedFileURL.path)
                success = false
            }
        }
        return success
    }

    /**
     Detiene el acceso security-scoped de forma segura para una URL.
     - Parameter url: URL a la que se desea detener el acceso.
     */
    private func safeStopSecurityScopedAccess(for url: URL) {
        url.stopAccessingSecurityScopedResource()
        print("🔒 Acceso security-scoped detenido para: \(url.lastPathComponent)")
    }
    
    // MARK: - Testing y Debugging Utilities
    
    /// Limpia toda la lista de videos y carga un solo video para testing
    /// Esta función es útil para depuración y testing de problemas específicos
    func limpiarYCargarVideoUnico() {
    print("🧹 Iniciando limpieza y carga de video único para testing...")
    
    // Detener wallpaper si está corriendo
    if isPlayingWallpaper {
        stopWallpaper()
    }
    
    // Limpiar la lista actual
    videoFiles.removeAll()
    currentVideo = nil
    
    // Verificar ruta de testing
    let rutaTesting = "/Users/felipe/Livewall/"
    
    guard let enumerator = FileManager.default.enumerator(atPath: rutaTesting) else {
        print("❌ No se pudo acceder a la carpeta de testing: \(rutaTesting)")
        notificationManager.showError(message: "No se pudo acceder a la carpeta de testing")
        return
    }
    
    // Buscar el primer video válido
    for case let archivo as String in enumerator {
        if archivo.hasSuffix(".mp4") || archivo.hasSuffix(".mov") {
            let urlArchivo = URL(fileURLWithPath: rutaTesting + archivo)
            if FileManager.default.fileExists(atPath: urlArchivo.path) {
                print("🎯 Seleccionado video único para testing: \(archivo)")
                
                // Agregar solo este video
                addVideoFiles(urls: [urlArchivo])
                
                // Seleccionarlo automáticamente
                if let primerVideo = videoFiles.first {
                    setActiveVideo(primerVideo)
                    print("✅ Video único configurado para testing: \(primerVideo.name)")
                    notificationManager.showMessage(title: "Testing", message: "Video único cargado: \(primerVideo.name)")
                }
                
                // Guardar cambios
                saveVideos()
                return
            }
        }
    }
    
    print("⚠️ No se encontraron videos válidos en \(rutaTesting)")
    notificationManager.showError(message: "No se encontraron videos en la carpeta de testing")
}

    
    /// Regenera la miniatura para el video actual
    /// Útil cuando hay problemas con la generación de thumbnails
    func regenerarMiniaturaVideoActual() {
        guard let videoActual = currentVideo else {
            notificationManager.showError(message: "No hay video activo para regenerar miniatura")
            return
        }
        
        print("🔄 Regenerando miniatura para: \(videoActual.name)")
        
        // Limpiar miniatura actual
        if let index = videoFiles.firstIndex(where: { $0.id == videoActual.id }) {
            videoFiles[index].thumbnailData = nil
        }
        
        // Regenerar
        generateThumbnail(for: videoActual)
        
        notificationManager.showMessage(title: "Miniatura", message: "Regenerando miniatura para \(videoActual.name)")
    }
}
