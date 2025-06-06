import SwiftUI
import AVFoundation
import AppKit
import UserNotifications

class WallpaperManager: ObservableObject {
    @Published var videoFiles: [VideoFile] = []
    @Published var currentVideo: VideoFile?
    @Published var isPlayingWallpaper = false
    
    // private var desktopWindows: [DesktopVideoWindow] = [] // Modificado
    private var desktopVideoInstances: [(window: DesktopVideoWindow, accessibleURL: URL)] = [] // Nuevo
    private let userDefaults = UserDefaults.standard
    private let videosKey = "SavedVideos"
    private let currentVideoKey = "CurrentVideo"
    private let notificationManager = NotificationManager.shared
    
    // MARK: - Security-Scoped Resource Tracking
    /// Tracking de URLs que tienen acceso security-scoped activo para prevenir double-stop crashes
    private var activeSecurityScopedURLs: Set<URL> = []
    private let resourceTrackingQueue = DispatchQueue(label: "security.resources", attributes: .concurrent)
    
    init() {
        loadSavedVideos()
        loadCurrentVideo()
        setupScreenChangeNotifications()
        
        // Para testing: cargar videos automáticamente si la lista está vacía
        if videoFiles.isEmpty {
            loadTestingVideos()
        }
        
        // Auto-start si estaba activo previamente
        if UserDefaults.standard.bool(forKey: "AutoStartWallpaper") && currentVideo != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startWallpaper()
            }
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
                bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
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
        // Desactivar el video anterior
        if let currentIndex = videoFiles.firstIndex(where: { $0.isActive }) {
            videoFiles[currentIndex].isActive = false
        }

        // Activar el nuevo video
        if let newIndex = videoFiles.firstIndex(where: { $0.id == video.id }) {
            videoFiles[newIndex].isActive = true
            currentVideo = videoFiles[newIndex] // currentVideo.url es original, bookmarkData debería estar presente o se creará
            saveCurrentVideo() // Guarda currentVideo con su URL original y bookmarkData

            if isPlayingWallpaper {
                // Si el fondo de pantalla ya se estaba reproduciendo, detén el anterior y comienza el nuevo.
                startWallpaper() // Esto resolverá el marcador para el nuevo currentVideo
            }
            // Si no isPlayingWallpaper, el video simplemente se selecciona. La UI podría mostrar su nombre/miniatura.
            // La generación de miniaturas debe tener su propio manejo robusto de marcadores.
        }
    }
    
    // MARK: - Wallpaper Control
    
    func startWallpaper() {
        guard let videoToPlay = currentVideo else {
            notificationManager.showError(message: "No hay ningún video seleccionado")
            return
        }

        guard let accessibleURL = resolveBookmark(for: videoToPlay) else {
            notificationManager.showError(message: "No se pudo acceder al archivo de video: \\(videoToPlay.name). Por favor, selecciónelo de nuevo o verifique los permisos.")
            return // Salir si no se puede acceder
        }

        // Verificar que el archivo existe (usando accessibleURL.path)
        guard FileManager.default.fileExists(atPath: accessibleURL.path) else {
            notificationManager.showError(message: "El archivo de video no se encuentra: \(videoToPlay.name) (ruta accesible: \(accessibleURL.path))")
            accessibleURL.stopAccessingSecurityScopedResource() // Detener el acceso si el archivo no existe en la ruta resuelta
            return
        }

        // Primero desactivar el flag isPlayingWallpaper antes de stopWallpaper para evitar 
        // posibles confusiones durante la transición
        let wasPlaying = isPlayingWallpaper
        isPlayingWallpaper = false
        
        // Usar un DispatchQueue para asegurar que la destrucción ocurra antes de crear nuevas ventanas
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.destroyDesktopWindows() // Libera ventanas existentes
            
            // Verificar nuevamente que accessibleURL es válido después de destruir las ventanas
            if FileManager.default.fileExists(atPath: accessibleURL.path) {
                self.isPlayingWallpaper = true
                self.createDesktopWindows(for: videoToPlay, accessibleURL: accessibleURL)
                self.notificationManager.showWallpaperStarted(videoName: videoToPlay.name)
                UserDefaults.standard.set(true, forKey: "AutoStartWallpaper")
            } else if wasPlaying {
                // Si estaba reproduciendo y la URL ya no es válida
                self.notificationManager.showError(message: "No se pudo acceder al archivo durante el cambio de wallpaper")
                UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
            }
        }
    }
    
    /// Detiene el wallpaper y destruye las ventanas de escritorio.
    /// Agrega log defensivo con stack trace para depuración.
    func stopWallpaper() {
        print("🛑 [stopWallpaper] llamado. Stack trace:\n\(Thread.callStackSymbols.joined(separator: "\n"))")
        isPlayingWallpaper = false
        destroyDesktopWindows()
        notificationManager.showWallpaperStopped()
        // Guardar preferencia de auto-start
        UserDefaults.standard.set(false, forKey: "AutoStartWallpaper")
    }
    
    func toggleWallpaper() {
        if isPlayingWallpaper {
            stopWallpaper()
        } else {
            startWallpaper()
        }
    }
    
    // MARK: - Desktop Windows Management
    
    private func createDesktopWindows(for video: VideoFile, accessibleURL: URL) { // Modificado para aceptar accessibleURL
        let screens = NSScreen.screens
        print("🖥️ Creando ventanas para \(screens.count) pantalla(s)")
        
        // Limpiar instancias antiguas antes de crear nuevas (aunque stopWallpaper ya debería haberlo hecho)
        // Esto es una doble seguridad, pero la lógica principal está en stopWallpaper -> destroyDesktopWindows
        if !desktopVideoInstances.isEmpty {
            print("⚠️ createDesktopWindows llamado pero desktopVideoInstances no estaba vacío. Limpiando primero.")
            destroyDesktopWindows()
        }

        for (index, screen) in screens.enumerated() {
            print("📺 Pantalla \(index + 1): \(screen.localizedName) - \(screen.frame)")
            let window = DesktopVideoWindow(screen: screen, videoURL: accessibleURL)
            // desktopWindows.append(window) // Modificado
            self.desktopVideoInstances.append((window: window, accessibleURL: accessibleURL)) // Nuevo, usando self para claridad
            
            window.orderBack(nil)
            print("✅ Ventana \(index + 1) creada y posicionada")
        }
        
        // print("🎬 Total de ventanas creadas: \\(desktopWindows.count)") // Modificado
        print("🎬 Total de ventanas creadas: \(desktopVideoInstances.count)") // Nuevo
    }
    
    /// Destruye todas las ventanas de video de escritorio de forma segura.
    /// Ahora cada ventana es responsable de liberar su propio acceso security-scoped.
    /// Destruye todas las ventanas de video de escritorio de forma segura.
    /// Agrega log defensivo con stack trace para depuración.
    private func destroyDesktopWindows() {
        print("💥 [destroyDesktopWindows] llamado. Stack trace:\n\(Thread.callStackSymbols.joined(separator: "\n"))")
        print("💥 Destruyendo \(desktopVideoInstances.count) ventana(s) de video de escritorio...")
        // Crear una copia local para evitar problemas de concurrencia
        let instances = desktopVideoInstances
        // Limpiar la colección principal primero para evitar referencias circulares
        desktopVideoInstances.removeAll()
        // Destruir ventanas una a una con logs defensivos y control de excepciones
        DispatchQueue.main.async {
            for (i, instance) in instances.enumerated() {
                // Verificar si la ventana es válida y está visible antes de cerrarla
                guard let window = instance.window as NSWindow? else {
                    print("[destroyDesktopWindows] Ventana #\(i+1) ya era nula")
                    continue
                }
                // Solo intentar cerrar ventanas que no estén ya liberadas
                if window.isReleasedWhenClosed == false || window.isVisible {
                    print("[destroyDesktopWindows] Cerrando ventana #\(i+1) para: \(instance.accessibleURL.lastPathComponent)")
                    // Control de excepciones por seguridad
                    autoreleasepool {
                        window.close()
                    }
                    print("[destroyDesktopWindows] Ventana #\(i+1) cerrada")
                    // Darle tiempo al sistema para procesar el cierre antes de continuar
                    if i < instances.count - 1 {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                } else {
                    print("[destroyDesktopWindows] Ventana #\(i+1) ya estaba cerrada o liberada")
                }
            }
            print("🗑️ Todas las instancias de ventanas de video de escritorio eliminadas.")
        }
    }
    
    // MARK: - Security-Scoped Resource Management
    
    /// Inicia acceso security-scoped y trackea la URL para prevenir double-start
    /// - Parameter url: URL a la que se quiere acceder
    /// - Returns: true si el acceso fue iniciado exitosamente
    private func safeStartSecurityScopedAccess(for url: URL) -> Bool {
        return resourceTrackingQueue.sync {
            // Verificar si ya tiene acceso activo
            if activeSecurityScopedURLs.contains(url) {
                print("⚠️ Security-scoped access ya está activo para: \(url.lastPathComponent)")
                return true // Consideramos que ya está disponible
            }
            
            // Intentar iniciar el acceso
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Falló startAccessingSecurityScopedResource para: \(url.lastPathComponent)")
                return false
            }
            
            // Agregar al tracking si fue exitoso
            activeSecurityScopedURLs.insert(url)
            print("✅ Security-scoped access iniciado y trackeado para: \(url.lastPathComponent)")
            return true
        }
    }
    
    /// Detiene acceso security-scoped de forma segura y actualiza el tracking
    /// - Parameter url: URL cuyo acceso se quiere detener
    private func safeStopSecurityScopedAccess(for url: URL) {
        resourceTrackingQueue.sync {
            // Solo detener si realmente está activo
            guard activeSecurityScopedURLs.contains(url) else {
                print("⚠️ Intento de detener security-scoped access que no estaba activo para: \(url.lastPathComponent)")
                return
            }
            
            // Usar autoreleasepool para prevenir memory corruption durante la liberación
            autoreleasepool {
                url.stopAccessingSecurityScopedResource()
                activeSecurityScopedURLs.remove(url)
                print("🛑 Security-scoped access detenido y removido del tracking para: \(url.lastPathComponent)")
            }
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
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        
        generator.generateCGImageAsynchronously(for: time) { [weak self] cgImage, actualTime, error in
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
                    let newBookmarkData = try mutableVideoFile.url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
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
            var resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("⚠️ Bookmark para \\(mutableVideoFile.name) está obsoleto. Intentando refrescarlo...")
                // Para refrescar, primero se debe poder acceder a la URL resuelta (aunque esté obsoleta)
                if resolvedURL.startAccessingSecurityScopedResource() {
                    if let newBookmarkData = try? resolvedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
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
                        resolvedURL = try URL(resolvingBookmarkData: refreshedBookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &refreshedIsStale)
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
            // Al cargar, la URL es la original. Necesitamos resolverla antes de usarla.
            // Esto se hará en setActiveVideo o startWallpaper.
            self.currentVideo = video
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopWallpaper()
    }
}
