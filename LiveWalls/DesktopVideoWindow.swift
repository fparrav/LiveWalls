import Cocoa
import AVFoundation
import AVKit

class DesktopVideoWindow: NSWindow {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoURL: URL
    private var isSecurityScoped: Bool = false // Nueva propiedad

    // Modificar el inicializador para aceptar isSecurityScoped
    init(screen: NSScreen, videoURL: URL, isSecurityScoped: Bool = false) {
        self.videoURL = videoURL
        self.isSecurityScoped = isSecurityScoped // Asignar
        
        let contentRect = screen.frame
        
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow(for: screen)
        setupPlayer(with: videoURL)
    }

    private func setupWindow(for screen: NSScreen) {
        print("🖥️ Configurando ventana para pantalla: \(screen.localizedName)")
        print("📐 Frame de pantalla: \(screen.frame)")
        
        // Configuración de la ventana para que aparezca detrás del escritorio
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.backgroundColor = NSColor.clear
        
        // Posicionar la ventana en la pantalla correcta
        self.setFrame(screen.frame, display: true)
        
        // Asegurar que aparezca en todos los espacios de trabajo
        self.collectionBehavior.insert(.canJoinAllSpaces)
        
        print("✅ Ventana configurada en nivel: \(self.level.rawValue)")
        print("🔧 Collection behavior: \(self.collectionBehavior)")
    }
    
    private func setupPlayer(with url: URL) {
        print("🎬 Configurando reproductor para URL: \(url.path) (SecurityScoped: \(isSecurityScoped))")
        let asset = AVURLAsset(url: url) // No se necesitan opciones especiales aquí si ya se accedió

        // Verificar que el archivo existe antes de intentar reproducirlo
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Error: Archivo de video no encontrado: \(url.path)")
            return
        }

        // Verificar el tamaño del archivo
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[FileAttributeKey.size] as? NSNumber {
                print("📁 Tamaño del archivo: \(ByteCountFormatter.string(fromByteCount: fileSize.int64Value, countStyle: .file))")
            }
        } catch {
            print("⚠️ No se pudo obtener información del archivo: \(error)")
        }

        // Crear el asset y verificar que es válido
        print("🔍 AVAsset creado. URL: \(url.path)")

        // Usar la API moderna de AVFoundation (macOS 13+)
        if #available(macOS 13.0, *) {
            Task {
                do {
                    let _ = try await asset.load(.isPlayable)
                    let _ = try await asset.load(.duration)
                    let _ = try await asset.load(.tracks)
                    print("🔎 isPlayable: \(asset.isPlayable)")
                    print("🔎 duration: \(asset.duration.seconds) segundos")
                    let videoTracks = try await asset.load(.tracks)
                    let videoTracksFiltered = videoTracks.filter { $0.mediaType == .video }
                    print("🔎 tracks: total=\(videoTracks.count), video=\(videoTracksFiltered.count)")
                    if !asset.isPlayable {
                        print("❌ El video no es reproducible (isPlayable == false)")
                        return
                    }
                    if videoTracksFiltered.isEmpty {
                        print("❌ No se encontraron pistas de video")
                        return
                    }
                    self.configurePlayerWithAsset(asset)
                } catch {
                    print("❌ Error al cargar propiedades del asset: \(error.localizedDescription)")
                }
            }
        } else {
            // Compatibilidad con versiones anteriores
            asset.loadValuesAsynchronously(forKeys: ["playable", "duration", "tracks"]) { [weak self] in
                DispatchQueue.main.async {
                    var error: NSError?
                    let playableStatus = asset.statusOfValue(forKey: "playable", error: &error)
                    print("🔎 playableStatus: \(playableStatus.rawValue) (\(playableStatus == .loaded ? "loaded" : playableStatus == .failed ? "failed" : playableStatus == .loading ? "loading" : "unknown"))")
                    if let error = error {
                        print("❌ Error al cargar 'playable': \(error.localizedDescription)")
                    }
                    let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
                    print("🔎 durationStatus: \(durationStatus.rawValue)")
                    if let error = error {
                        print("❌ Error al cargar 'duration': \(error.localizedDescription)")
                    }
                    let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &error)
                    print("🔎 tracksStatus: \(tracksStatus.rawValue)")
                    if let error = error {
                        print("❌ Error al cargar 'tracks': \(error.localizedDescription)")
                    }
                    self?.configurePlayerWithAsset(asset)
                }
            }
        }
    }
    
    private func configurePlayerWithAsset(_ asset: AVAsset) {
        // Verificar pistas de video
        let videoTracks = asset.tracks(withMediaType: .video)
        print("✅ Asset válido con \(videoTracks.count) pista(s) de video")
        for (i, track) in videoTracks.enumerated() {
            print("  - Track[\(i)]: id=\(track.trackID), naturalSize=\(track.naturalSize), isPlayable=\(track.isPlayable)")
        }

        // Crear el reproductor de video
        playerLayer = AVPlayerLayer()

        // Crear el playerItem con configuración optimizada
        let playerItem = AVPlayerItem(asset: asset)

        // Observar errores del playerItem
        NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: playerItem, queue: .main) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("❌ AVPlayerItemFailedToPlayToEndTime: \(error.localizedDescription)")
            } else {
                print("❌ AVPlayerItemFailedToPlayToEndTime: error desconocido")
            }
        }

        // Configurar buffer y rendimiento
        if #available(macOS 10.15, *) {
            playerItem.preferredForwardBufferDuration = 3.0
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        }

        // Observar el estado del playerItem
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        playerItem.addObserver(self, forKeyPath: "error", options: [.new], context: nil)

        // Crear el player
        player = AVPlayer(playerItem: playerItem)

        // Configurar el playerLayer
        playerLayer?.player = player
        playerLayer?.videoGravity = .resizeAspectFill

        // Las siguientes propiedades no existen en AVPlayerLayer y deben eliminarse:
        // if #available(macOS 10.15, *) {
        //     // playerLayer?.updatesNowPlayingInfoCenter = false // Eliminar
        //     // playerLayer?.allowsPictureInPicturePlayback = false // Eliminar
        // }

        // Configurar el contenido de la ventana
        self.contentView?.layer = playerLayer
        self.contentView?.wantsLayer = true

        // Configurar reproducción en loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.restartVideo()
        }

        // Silenciar el video
        player?.isMuted = true

        print("🎬 Iniciando reproducción del video...")
    }
    
    private func restartVideo() {
        guard let player = player else { return }
        player.seek(to: .zero) { [weak self] _ in
            self?.player?.play() // Corregido: usar encadenamiento opcional
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let playerItem = object as? AVPlayerItem {
                switch playerItem.status {
                case .readyToPlay:
                    print("✅ Video listo para reproducir")
                    player?.play() // Corregido: usar encadenamiento opcional
                case .failed:
                    if let error = playerItem.error {
                        print("❌ Error en playerItem: \(error.localizedDescription)")
                    } else {
                        print("❌ Error desconocido en playerItem")
                    }
                case .unknown:
                    print("⏳ Estado desconocido del video")
                @unknown default:
                    print("❓ Estado no manejado del video")
                }
            }
        } else if keyPath == "error" {
            if let playerItem = object as? AVPlayerItem, let error = playerItem.error {
                print("❌ Error en reproducción: \(error.localizedDescription)")
            }
        }
    }
    
    override func close() {
        print("🔄 Cerrando ventana de video para escritorio")
        
        // Limpiar observadores
        NotificationCenter.default.removeObserver(self)
        
        if let playerItem = player?.currentItem {
            playerItem.removeObserver(self, forKeyPath: "status")
            playerItem.removeObserver(self, forKeyPath: "error")
        }
        
        // Detener reproducción
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        super.close()
    }
    
    // Prevenir que la ventana se muestre en Mission Control o App Exposé
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    // Asegurar que la ventana mantenga su posición
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard let screen = self.screen else {
            super.setFrame(frameRect, display: flag)
            return
        }
        
        // Forzar que la ventana mantenga el frame de la pantalla
        super.setFrame(screen.frame, display: flag)
    }
    
    deinit {
        print("🗑️ DesktopVideoWindow deinit para URL: \\(videoURL.path)")
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        // Detener el acceso al recurso de ámbito de seguridad si esta ventana lo gestionaba
        if isSecurityScoped {
            videoURL.stopAccessingSecurityScopedResource() // Corregido: no se asigna a una constante ni se usa su (inexistente) valor de retorno
            print("🛑 Llamada a stopAccessingSecurityScopedResource para \\(videoURL.path) en deinit.")
        }
        NotificationCenter.default.removeObserver(self)
    }
}
