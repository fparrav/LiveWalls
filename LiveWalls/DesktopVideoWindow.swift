import Cocoa
import CoreGraphics
import AVFoundation
import AVKit
import os.log

// Logger específico para debugging de memoria
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

// Extensiones para compatibilidad con versiones anteriores de macOS
extension AVAsset {
    // Propiedad computada para acceder a `isPlayable` de forma segura en versiones anteriores
    var isPlayableDeprecated: Bool {
        if #available(macOS 13.0, *) {
            // En macOS 13+ podríamos intentar cargarla asíncronamente si fuera necesario,
            // pero para este contexto, si no está cargada, asumimos que no es directamente consultable aquí.
            // La lógica principal ya usa el API asíncrono.
            return false // O manejar de otra forma si es necesario un valor síncrono.
        } else {
            var error: NSError?
            let status = self.statusOfValue(forKey: "playable", error: &error)
            if status == .loaded {
                return self.isPlayable // Acceso directo después de cargar
            } else {
                // Podrías registrar el error o el estado si no está cargado.
                // print("Warning: 'playable' key not loaded for AVAsset in isPlayableDeprecated. Status: \\(status.rawValue)")
                return false // O un valor por defecto apropiado
            }
        }
    }

    // Propiedad computada para acceder a `tracks` de forma segura
    var tracksDeprecated: [AVAssetTrack] {
        if #available(macOS 13.0, *) {
            return [] // Similar a isPlayableDeprecated, la lógica principal usa API asíncrono.
        } else {
            var error: NSError?
            let status = self.statusOfValue(forKey: "tracks", error: &error)
            if status == .loaded {
                return self.tracks
            } else {
                // print("Warning: 'tracks' key not loaded for AVAsset in tracksDeprecated. Status: \\(status.rawValue)")
                return []
            }
        }
    }
}

extension AVAssetTrack {
    // Propiedad computada para `naturalSize`
    var naturalSizeDeprecated: CGSize {
        if #available(macOS 13.0, *) {
            return .zero // La lógica principal usa API asíncrono.
        } else {
            var error: NSError?
            let status = self.statusOfValue(forKey: "naturalSize", error: &error)
            if status == .loaded {
                return self.naturalSize
            }
            return .zero
        }
    }

    // Propiedad computada para `isPlayable` de la pista
    var isPlayableDeprecated: Bool {
        if #available(macOS 13.0, *) {
            return false // La lógica principal usa API asíncrono.
        } else {
            var error: NSError?
            let status = self.statusOfValue(forKey: "playable", error: &error)
            if status == .loaded {
                return self.isPlayable
            }
            return false
        }
    }
}


class DesktopVideoWindow: NSWindow {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoURL: URL
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerRateObserver: NSKeyValueObservation?
    private var playerItem: AVPlayerItem?
    private var isClosing: Bool = false

    init(screen: NSScreen, videoURL: URL) {
        self.videoURL = videoURL
        
        let contentRect = screen.frame
        
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        setupWindow(for: screen)
        Task {
            await setupPlayer(with: videoURL)
        }
    }

    private func setupWindow(for screen: NSScreen) {
        print("🖥️ Configurando ventana para pantalla: \(screen.localizedName)")
        // Corrección: Usar el enum moderno para el nivel de la ventana de escritorio
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.backgroundColor = NSColor.clear // Fondo transparente
        self.setFrame(screen.frame, display: true)
        // self.collectionBehavior.insert(.canJoinAllSpaces) // Redundante si ya está en la inicialización
    }
    
    private func setupPlayer(with url: URL) async {
        print("🎬 Configurando reproductor para URL: \(url.path)")
        let asset = AVURLAsset(url: url)

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Error: Archivo de video no encontrado: \(url.path)")
            await MainActor.run { self.showErrorInWindow("Archivo no encontrado: \(url.lastPathComponent)") }
            return
        }

        if #available(macOS 13.0, *) {
            do {
                // Cargar propiedades necesarias del asset
                let (isPlayable, duration, tracks) = try await asset.load(.isPlayable, .duration, .tracks)

                print("🔎 Asset isPlayable (macOS 13+): \(isPlayable)")
                print("🔎 Asset duration (macOS 13+): \(duration.seconds) segundos")
                print("🔎 Asset total tracks (macOS 13+): \(tracks.count)")

                if !isPlayable {
                    print("❌ El video no es reproducible (asset.isPlayable == false, macOS 13+)")
                    await MainActor.run { self.showErrorInWindow("Video no reproducible (13+): \(url.lastPathComponent)") }
                    return
                }

                let videoTracks = tracks.filter { $0.mediaType == .video }
                if videoTracks.isEmpty {
                    print("❌ No se encontraron pistas de video en el asset (macOS 13+)")
                    await MainActor.run { self.showErrorInWindow("Sin pistas de video (13+): \(url.lastPathComponent)") }
                    return
                }
                
                var loadedTrackDetails: [(track: AVAssetTrack, naturalSize: CGSize, isPlayable: Bool)] = []
                for track in videoTracks {
                    let (naturalSize, isTrackPlayable) = try await track.load(.naturalSize, .isPlayable)
                    print("  - Pista ID \(track.trackID) (macOS 13+): naturalSize=\(naturalSize), isPlayable=\(isTrackPlayable)")
                    if isTrackPlayable { 
                        loadedTrackDetails.append((track, naturalSize, isTrackPlayable))
                    }
                }

                if loadedTrackDetails.isEmpty {
                    print("❌ Ninguna de las pistas de video filtradas es reproducible individualmente (macOS 13+).")
                    await MainActor.run { self.showErrorInWindow("Pistas no reproducibles (13+): \(url.lastPathComponent)") }
                    return
                }
                
                await MainActor.run {
                    self.configurePlayerWithAsset(asset, trackDetails: loadedTrackDetails)
                }

            } catch {
                print("❌ Error al cargar propiedades del asset o pistas (macOS 13+): \(error.localizedDescription)")
                 await MainActor.run { self.showErrorInWindow("Error carga (13+): \(error.localizedDescription.prefix(30))... \(url.lastPathComponent)") }
            }
        } else {
            // Ruta heredada para macOS < 13.0
            asset.loadValuesAsynchronously(forKeys: ["playable", "duration", "tracks"]) { [weak self] in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    var error: NSError?
                    let playableStatus = asset.statusOfValue(forKey: "playable", error: &error)
                    
                    if playableStatus == .failed || error != nil || !asset.isPlayableDeprecated {
                        let errorDesc = error?.localizedDescription ?? "No reproducible (legacy)"
                        print("❌ El video no es reproducible o error al cargar 'playable' (legacy): \(errorDesc) para \(url.lastPathComponent)")
                        self.showErrorInWindow("No reproducible (legacy): \(errorDesc.prefix(30))... \(url.lastPathComponent)")
                        return
                    }

                    // Comprobar estado de 'duration'
                    let durationStatus = asset.statusOfValue(forKey: "duration", error: &error)
                    if durationStatus == .failed || error != nil {
                        print("⚠️ Error al cargar 'duration' (legacy): \(error?.localizedDescription ?? "Unknown error") para \(url.lastPathComponent)")
                        // No es fatal, podemos continuar
                    } else if durationStatus == .loaded {
                        print("🔎 Asset duration (legacy): \(asset.duration.seconds) segundos")
                    }
                    
                    // Comprobar estado de 'tracks'
                    let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &error)
                    if tracksStatus == .failed || error != nil {
                         print("❌ Error al cargar 'tracks' (legacy): \(error?.localizedDescription ?? "Unknown error") para \(url.lastPathComponent)")
                         self.showErrorInWindow("Error pistas (legacy): \((error?.localizedDescription ?? "Unknown error").prefix(30))... \(url.lastPathComponent)")
                         return 
                    }

                    let videoTracksLegacy = asset.tracksDeprecated.filter { $0.mediaType == .video }
                    if videoTracksLegacy.isEmpty {
                        print("❌ No se encontraron pistas de video (legacy) para \(url.lastPathComponent)")
                        self.showErrorInWindow("Sin pistas (legacy): \(url.lastPathComponent)")
                        return
                    }
                    
                    var legacyTrackDetails: [(track: AVAssetTrack, naturalSize: CGSize, isPlayable: Bool)] = []
                    for track in videoTracksLegacy {
                        let naturalSize = track.naturalSizeDeprecated
                        let isTrackPlayable = track.isPlayableDeprecated
                        print("  - Pista ID \(track.trackID) (legacy): naturalSize=\(naturalSize), isPlayable=\(isTrackPlayable)")
                        if isTrackPlayable {
                             legacyTrackDetails.append((track, naturalSize, isTrackPlayable))
                        }
                    }
                    
                    if legacyTrackDetails.isEmpty {
                        print("❌ Ninguna de las pistas de video filtradas es reproducible (legacy) para \(url.lastPathComponent)")
                        self.showErrorInWindow("Pistas no reproducibles (legacy): \(url.lastPathComponent)")
                        return
                    }
                    self.configurePlayerWithAsset(asset, trackDetails: legacyTrackDetails)
                }
            }
        }
    }
    
    private func configurePlayerWithAsset(_ asset: AVAsset, trackDetails: [(track: AVAssetTrack, naturalSize: CGSize, isPlayable: Bool)]) {
        print("✅ Configurando AVPlayer con \(trackDetails.count) pista(s) de video válidas para \(videoURL.lastPathComponent).")
        // Simplemente usamos el primer track válido, podríamos tener lógica más compleja si es necesario
        guard !trackDetails.isEmpty else {
            print("❌ No hay pistas de video válidas para configurar el reproductor.")
            showErrorInWindow("Sin pistas válidas: \(videoURL.lastPathComponent)")
            return
        }
        print("  -> Usando Pista ID \(trackDetails.first!.track.trackID): naturalSize=\(trackDetails.first!.naturalSize), isPlayable=\(trackDetails.first!.isPlayable)")

        // Crear y retener el playerItem
        playerItem = AVPlayerItem(asset: asset)
        guard let playerItem = playerItem else { return }
        
        player = AVPlayer(playerItem: playerItem)
        player?.actionAtItemEnd = .none 

        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.frame = self.contentView?.bounds ?? .zero
        
        self.contentView?.layer = playerLayer
        self.contentView?.wantsLayer = true

        // Observador para el estado del player item (ready to play)
        playerItemStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] (item: AVPlayerItem, _: NSKeyValueObservedChange<AVPlayerItem.Status>) in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                print("▶️ Video \(self.videoURL.lastPathComponent) listo para reproducir. Iniciando.")
                self.player?.play()
                self.playerRateObserver = self.player?.observe(\.rate, options: [.new]) { (player: AVPlayer, _: NSKeyValueObservedChange<Float>) in
                    if player.rate == 0 && player.error == nil && item.isPlaybackLikelyToKeepUp {
                         // Puede ser una pausa o el final del video si actionAtItemEnd no es .none
                         // print("ℹ️ Tasa de reproducción es 0 para \(self.videoURL.lastPathComponent)")
                    } else if let error = player.error {
                        print("‼️ Error en el reproductor durante la reproducción: \(error.localizedDescription) para \(self.videoURL.lastPathComponent)")
                        self.showErrorInWindow("Error reprod.: \(error.localizedDescription.prefix(30)) \(self.videoURL.lastPathComponent)")
                    }
                }
            case .failed:
                print("❌ Falló la carga del PlayerItem para \(self.videoURL.lastPathComponent): \(item.error?.localizedDescription ?? "Error desconocido")")
                self.showErrorInWindow("Error Item: \((item.error?.localizedDescription ?? "Desconocido").prefix(30)) \(self.videoURL.lastPathComponent)")
            case .unknown:
                print("❓ Estado desconocido del PlayerItem para \(self.videoURL.lastPathComponent)")
            @unknown default:
                print("❓ Estado desconocido (default) del PlayerItem para \\(self.videoURL.lastPathComponent)")
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTime(notification:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        player?.isMuted = true
        print("🎧 Reproductor silenciado.")
        print("⏳ AVPlayer configurado para \(videoURL.lastPathComponent). Esperando estado 'readyToPlay' para iniciar reproducción...")
    }
    
    @objc private func playerItemDidPlayToEndTime(notification: NSNotification) {
        guard !isClosing else { return }
        guard let playerItem = notification.object as? AVPlayerItem else { return }
        // Asegurarse de que la notificación es para el item actual
        if playerItem == self.player?.currentItem {
            print("🔄 Video \(videoURL.lastPathComponent) llegó al final. Reiniciando.")
            restartVideo()
        }
    }

    private func restartVideo() {
        guard !isClosing else { return }
        guard let player = player else { 
            print("⚠️ restartVideo llamado pero player es nil para \(videoURL.lastPathComponent).")
            return
        }
        player.seek(to: .zero) { [weak self] success in
            guard let self = self, !self.isClosing else { return }
            if success {
                print("⏪ Video \(self.videoURL.lastPathComponent) reiniciado a cero. Reproduciendo.")
                self.player?.play() // Asegurarse de que se reproduzca después de buscar
            } else {
                print("⚠️ Fallo al buscar el inicio del video para reiniciar: \(self.videoURL.lastPathComponent).")
            }
        }
    }

    override func close() {
        print("🛑 Cerrando DesktopVideoWindow para \(videoURL.lastPathComponent)")
        
        // Marcar que estamos cerrando para evitar operaciones concurrentes
        isClosing = true
        
        // CRITICAL: Limpiar en el orden correcto para evitar crashes
        cleanupResources()
        
        super.close() // Llama al close de NSWindow
        print("🗑️ DesktopVideoWindow para \(videoURL.lastPathComponent) cerrado y recursos liberados.")
    }
    
    private func cleanupResources() {
        memoryLogger.info("🧹 Iniciando limpieza de recursos para \(self.videoURL.lastPathComponent)")
        
        // 1. Pausar el player inmediatamente
        player?.pause()
        memoryLogger.debug("⏸️ Player pausado")
        
        // 2. Invalidar observadores KVO ANTES de cualquier otra limpieza
        if let observer = playerItemStatusObserver {
            observer.invalidate()
            playerItemStatusObserver = nil
            memoryLogger.debug("🔍 Observer de status invalidado")
        }
        
        if let observer = playerRateObserver {
            observer.invalidate()
            playerRateObserver = nil
            memoryLogger.debug("🔍 Observer de rate invalidado")
        }
        
        // 3. Eliminar observadores de NotificationCenter de forma específica
        if let currentPlayerItem = playerItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: currentPlayerItem
            )
            memoryLogger.debug("📢 Observador de notificación removido para playerItem específico")
        }
        // Remover cualquier otro observador de este objeto
        NotificationCenter.default.removeObserver(self)
        memoryLogger.debug("📢 Todos los observadores de notificación removidos")
        
        // 4. Limpiar la capa del player ANTES de limpiar el player
        if let layer = playerLayer {
            // Detener cualquier animación en la capa
            layer.removeAllAnimations()
            // Desconectar el player de la capa
            layer.player = nil
            // Remover de la supercapa
            layer.removeFromSuperlayer()
            playerLayer = nil
            memoryLogger.debug("🎭 PlayerLayer limpiado y desconectado")
        }
        
        // 5. Limpiar el player y playerItem de forma segura
        if let currentPlayer = player {
            // Reemplazar el item actual con nil para liberar referencias
            currentPlayer.replaceCurrentItem(with: nil)
            player = nil
            memoryLogger.debug("🎮 Player limpiado y referencias liberadas")
        }
        
        // 6. Limpiar playerItem explícitamente
        if playerItem != nil {
            playerItem = nil
            memoryLogger.debug("🎬 PlayerItem reference eliminada")
        }
        
        // 7. Limpiar la vista de contenido
        if let content = contentView {
            content.layer = nil
            content.wantsLayer = false
            memoryLogger.debug("🖼️ ContentView layer limpiado")
        }
        
        memoryLogger.info("✅ Limpieza de recursos completada para \(self.videoURL.lastPathComponent)")
    }
    
    deinit {
        memoryLogger.info("🧹 deinit DesktopVideoWindow para \(self.videoURL.lastPathComponent)")
        
        // Asegurarse de que la limpieza se haya realizado
        if !isClosing {
            memoryLogger.warning("⚠️ deinit llamado sin close() previo. Ejecutando limpieza de emergencia.")
            cleanupResources()
        }
        
        // Los observadores KVO se invalidan automáticamente en deinit si no se hizo antes,
        // pero es buena práctica hacerlo explícitamente.
        playerItemStatusObserver?.invalidate()
        playerRateObserver?.invalidate()
        
        memoryLogger.info("✅ deinit completado para \(self.videoURL.lastPathComponent)")
    }
    
    private func showErrorInWindow(_ message: String) {
        // Crear una etiqueta de texto para mostrar el mensaje de error
        // Esta es una forma simple, podría mejorarse.
        guard let contentView = self.contentView else { return }
        
        // Limpiar errores anteriores
        for subview in contentView.subviews {
            if subview is NSTextField {
                subview.removeFromSuperview()
            }
        }
        
        let errorLabel = NSTextField(labelWithString: message)
        errorLabel.textColor = .white
        errorLabel.backgroundColor = .black.withAlphaComponent(0.7)
        errorLabel.alignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.maximumNumberOfLines = 0 // Permitir múltiples líneas
        errorLabel.lineBreakMode = .byWordWrapping
        
        contentView.addSubview(errorLabel)
        
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        ])
        print("⚠️ Mostrando error en ventana: \(message)")
    }
}
