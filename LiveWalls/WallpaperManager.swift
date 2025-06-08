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
                print("Archivo no soportado: \\(url.lastPathComponent)")
                continue
            }

            // Iniciar el acceso al security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("⚠️ No se pudo iniciar el acceso al security-scoped resource para: \\(url.path)")
                // Podrías mostrar un error al usuario aquí si es necesario
                continue
            }

            // Verificar que el archivo exista y sea accesible
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("Archivo no encontrado: \\(url.path)")
                url.stopAccessingSecurityScopedResource() // Detener el acceso si el archivo no existe
                continue
            }

            // Verificar que no esté ya en la lista
            guard !videoFiles.contains(where: { $0.url.path == url.path }) else { // Comparar por path para evitar problemas con bookmarks
                print("Video ya existe: \\(url.lastPathComponent)")
                url.stopAccessingSecurityScopedResource() // Detener el acceso si ya existe
                continue
            }

            var bookmarkData: Data?
            do {
                bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                print("🔖 Bookmark creado para: \\(url.lastPathComponent)")
            } catch {
                print("❌ Error al crear bookmark para \(url.path): \(error.localizedDescription)")
                url.stopAccessingSecurityScopedResource() // Detener el acceso si falla la creación del bookmark
                continue // No añadir el video si no se puede crear el bookmark
            }
            
            // Es importante detener el acceso después de crear el bookmark si no se va a usar la URL inmediatamente.
            // Se volverá a iniciar el acceso cuando se necesite reproducir el video.
            url.stopAccessingSecurityScopedResource()

            let videoFile = VideoFile(url: url, bookmarkData: bookmarkData) // Guardar el bookmarkData
            videoFiles.append(videoFile)
            generateThumbnail(for: videoFile) // generateThumbnail también necesitará resolver el bookmark
            print("Video agregado: \\(videoFile.name)")
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

        stopWallpaper() // Destruye ventanas antiguas, lo que debería llamar a stopAccessingSecurityScopedResource en URL antiguas
        isPlayingWallpaper = true

        createDesktopWindows(for: videoToPlay, accessibleURL: accessibleURL) // Pasar la URL accesible
        notificationManager.showWallpaperStarted(videoName: videoToPlay.name)

        UserDefaults.standard.set(true, forKey: "AutoStartWallpaper")
    }
    
    func stopWallpaper() {
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
    
    private func destroyDesktopWindows() {
        print("💥 Destruyendo \(desktopVideoInstances.count) ventana(s) de video de escritorio...")
        
        // Procesar las ventanas en lotes para evitar problemas de concurrencia
        let instances = desktopVideoInstances
        desktopVideoInstances.removeAll() // Clear the main list immediately
        
        for instance in instances {
            // Usar DispatchQueue para asegurar que las operaciones se ejecuten secuencialmente en el hilo principal
            DispatchQueue.main.async {
                // Cerrar la ventana (esto llamará al método close() mejorado en DesktopVideoWindow)
                instance.window.close()
                
                // Introducir un retraso antes de detener el acceso al recurso
                DispatchQueue.main.asyncAfter(deadline: .now() + self.resourceReleaseDelay) { // 100ms delay
                    // Solo detener el acceso si la URL todavía está "viva" y asociada con esta instancia.
                    // Esta verificación es más conceptual ya que 'instance' es una copia.
                    // El principal beneficio es el retraso en sí.
                    instance.accessibleURL.stopAccessingSecurityScopedResource()
                    print("🛑 Acceso detenido con retraso para \(instance.accessibleURL.lastPathComponent) al destruir la instancia de la ventana.")
                }
            }
        }
        
        print("🗑️ Todas las instancias de ventanas de video de escritorio programadas para cierre y liberación de recursos.")
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

    private func resolveBookmark(for videoFile: VideoFile) -> URL? {
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
