// Implementación unificada de DesktopVideoWindowMejorada
// Esta clase reemplaza a DesktopVideoWindow y debe ser usada en todo el proyecto.

import Cocoa
import CoreGraphics
import AVFoundation
import os.log

// Logger específico para debugging de memoria
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

// MARK: - Delegate Protocol para comunicación con WallpaperManager

/// Protocol para manejar el ciclo de vida de DesktopVideoWindowMejorada
/// Permite al WallpaperManager recibir notificaciones sobre el estado de las ventanas
public protocol DesktopVideoWindowDelegate: AnyObject {
    /// Se llama cuando la ventana está a punto de cerrarse
    /// - Parameters:
    ///   - window: La ventana que se va a cerrar
    ///   - url: URL del video asociado con la ventana
    func windowWillClose(_ window: DesktopVideoWindowMejorada, withURL url: URL)
    
    /// Se llama después de que la ventana se ha cerrado completamente
    /// - Parameters:
    ///   - window: La ventana que se cerró
    ///   - url: URL del video asociado con la ventana
    func windowDidClose(_ window: DesktopVideoWindowMejorada, withURL url: URL)
}

// Extensiones para compatibilidad con versiones anteriores de macOS
extension AVAsset {
    var isPlayableDeprecated: Bool {
        if #available(macOS 13.0, *) {
            return false
        } else {
            var error: NSError?
            let status = self.statusOfValue(forKey: "playable", error: &error)
            if status == .loaded {
                return self.isPlayable
            } else {
                return false
            }
        }
    }
    var tracksDeprecated: [AVAssetTrack] {
        if #available(macOS 13.0, *) {
            return []
        } else {
            var error: NSError?
            let status = self.statusOfValue(forKey: "tracks", error: &error)
            if status == .loaded {
                return self.tracks
            } else {
                return []
            }
        }
    }
}

extension AVAssetTrack {
    var naturalSizeDeprecated: CGSize {
        if #available(macOS 13.0, *) {
            return .zero
        } else {
            var error: NSError?
            let status = self.statusOfValue(forKey: "naturalSize", error: &error)
            if status == .loaded {
                return self.naturalSize
            }
            return .zero
        }
    }
    var isPlayableDeprecated: Bool {
        if #available(macOS 13.0, *) {
            return false
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

/// Ventana de video de escritorio mejorada y unificada
public class DesktopVideoWindowMejorada: NSWindow {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoURL: URL
    private var urlSecurityScoped: URL?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerRateObserver: NSKeyValueObservation?
    private var playerItemDidPlayToEndObserver: NSObjectProtocol?
    private var playerItem: AVPlayerItem?
    private var isClosing: Bool = false
    private var isPlayerSetupInProgress: Bool = false
    private var isBeingTornDown: Bool = false
    
    // MARK: - Delegate para comunicación con WallpaperManager
    weak var wallpaperDelegate: DesktopVideoWindowDelegate?

    /// Inicializa la ventana con la pantalla y la URL de video accesible (security-scoped activa).
    /// IMPORTANTE: La ventana NO toma ownership del acceso security-scoped. 
    /// El WallpaperManager es responsable de gestionar el ciclo de vida del acceso.
    /// - Parameters:
    ///   - screen: Pantalla destino.
    ///   - videoURL: URL del video con acceso security-scoped activo.
    public init(screen: NSScreen, videoURL: URL) {
        self.videoURL = videoURL
        self.urlSecurityScoped = nil
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
        memoryLogger.info("🖥️ Configurando ventana para pantalla: \(screen.localizedName)")
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.backgroundColor = NSColor.clear
        self.setFrame(screen.frame, display: true)
    }

    private func setupPlayer(with url: URL) async {
        await MainActor.run { self.isPlayerSetupInProgress = true }
        defer {
            Task { @MainActor in self.isPlayerSetupInProgress = false }
        }
        let asset = AVURLAsset(url: url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            await MainActor.run {
                if self.isClosing { return }
                self.showErrorInWindow("Archivo no encontrado: \(url.lastPathComponent)")
            }
            return
        }
        if #available(macOS 13.0, *) {
            do {
                let (_, _, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
                let videoTracks = tracks.filter { $0.mediaType == .video }
                var loadedTrackDetails: [(track: AVAssetTrack, naturalSize: CGSize, isPlayable: Bool)] = []
                for track in videoTracks {
                    let (naturalSize, isTrackPlayable) = try await track.load(.naturalSize, .isPlayable)
                    if isTrackPlayable {
                        loadedTrackDetails.append((track, naturalSize, isTrackPlayable))
                    }
                }
                if loadedTrackDetails.isEmpty {
                    await MainActor.run {
                        if self.isClosing { return }
                        self.showErrorInWindow("Pistas no reproducibles (13+): \(url.lastPathComponent)")
                    }
                    return
                }
                await MainActor.run {
                    if self.isClosing { return }
                    self.configurePlayerWithAsset(asset, trackDetails: loadedTrackDetails)
                }
            } catch {
                await MainActor.run {
                    if self.isClosing { return }
                    self.showErrorInWindow("Error carga (13+): \(error.localizedDescription.prefix(30))... \(url.lastPathComponent)")
                }
            }
        } else {
            asset.loadValuesAsynchronously(forKeys: ["playable", "duration", "tracks"]) { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if self.isClosing { return }
                    var error: NSError?
                    let playableStatus = asset.statusOfValue(forKey: "playable", error: &error)
                    if playableStatus == .failed || error != nil || !asset.isPlayableDeprecated {
                        self.showErrorInWindow("No reproducible (legacy): \(error?.localizedDescription ?? "No reproducible")... \(url.lastPathComponent)")
                        return
                    }
                    let videoTracksLegacy = asset.tracksDeprecated.filter { $0.mediaType == .video }
                    if videoTracksLegacy.isEmpty {
                        self.showErrorInWindow("Sin pistas (legacy): \(url.lastPathComponent)")
                        return
                    }
                    var legacyTrackDetails: [(track: AVAssetTrack, naturalSize: CGSize, isPlayable: Bool)] = []
                    for track in videoTracksLegacy {
                        let naturalSize = track.naturalSizeDeprecated
                        let isTrackPlayable = track.isPlayableDeprecated
                        if isTrackPlayable {
                            legacyTrackDetails.append((track, naturalSize, isTrackPlayable))
                        }
                    }
                    if legacyTrackDetails.isEmpty {
                        self.showErrorInWindow("Pistas no reproducibles (legacy): \(url.lastPathComponent)")
                        return
                    }
                    self.configurePlayerWithAsset(asset, trackDetails: legacyTrackDetails)
                }
            }
        }
    }

    private func configurePlayerWithAsset(_ asset: AVAsset, trackDetails: [(track: AVAssetTrack, naturalSize: CGSize, isPlayable: Bool)]) {
        guard !trackDetails.isEmpty else {
            showErrorInWindow("Sin pistas válidas: \(videoURL.lastPathComponent)")
            return
        }
        let newPlayerItem = AVPlayerItem(asset: asset)
        playerItem = newPlayerItem
        player = AVPlayer(playerItem: newPlayerItem)
        player?.actionAtItemEnd = .none
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.frame = self.contentView?.bounds ?? .zero
        self.contentView?.layer = playerLayer
        self.contentView?.wantsLayer = true
        playerItemStatusObserver = newPlayerItem.observe(\.status, options: [.new, .initial]) { [weak self] (item: AVPlayerItem, _: NSKeyValueObservedChange<AVPlayerItem.Status>) in
            guard let self = self, !self.isClosing, self.player != nil, self.playerItem === item else { return }
            switch item.status {
            case .readyToPlay:
                self.player?.play()
                self.playerRateObserver = self.player?.observe(\.rate, options: [.new]) { [weak self] (player: AVPlayer, _: NSKeyValueObservedChange<Float>) in
                    guard let self = self, !self.isClosing else { return }
                    if player.rate == 0 && player.error == nil && item.isPlaybackLikelyToKeepUp {
                        // Puede ser una pausa o el final del video si actionAtItemEnd no es .none
                    } else if let error = player.error {
                        self.showErrorInWindow("Error reprod.: \(error.localizedDescription.prefix(30)) \(self.videoURL.lastPathComponent)")
                    }
                }
            case .failed:
                self.showErrorInWindow("Error Item: \((item.error?.localizedDescription ?? "Desconocido").prefix(30)) \(self.videoURL.lastPathComponent)")
            case .unknown:
                break
            @unknown default:
                break
            }
        }
        playerItemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleVideoEndNotification()
        }
        player?.isMuted = true
    }

    private func handleVideoEndNotification() {
        guard !isClosing else { return }
        guard self.player?.currentItem != nil else { return }
        self.restartVideo()
    }

    private func restartVideo() {
        guard !isClosing else { return }
        guard let player = player else { return }
        player.seek(to: .zero) { [weak self] success in
            guard let self = self, !self.isClosing else { return }
            if success {
                self.player?.play()
            }
        }
    }

    public override func close() {
        memoryLogger.info("🛑 [close] Iniciando cierre de DesktopVideoWindowMejorada para \(self.videoURL.lastPathComponent)")
        guard !isClosing else {
            memoryLogger.warning("⚠️ [close] Llamado a close() mientras ya se estaba cerrando para \(self.videoURL.lastPathComponent)")
            return
        }
        isClosing = true
        
        // Notificar al delegate ANTES de cerrar
        wallpaperDelegate?.windowWillClose(self, withURL: videoURL)
        
        // Limpiar recursos antes del cierre
        cleanupResources()
        
        // Cerrar la ventana
        super.close()
        
        // Notificar al delegate DESPUÉS de cerrar
        wallpaperDelegate?.windowDidClose(self, withURL: videoURL)
        
        memoryLogger.info("✅ [close] DesktopVideoWindowMejorada cerrada correctamente para \(self.videoURL.lastPathComponent)")
    }

    func cleanupResources() {
        isBeingTornDown = true
        player?.pause()
        if let playerItemStatusObserver = playerItemStatusObserver {
            playerItemStatusObserver.invalidate()
            self.playerItemStatusObserver = nil
        }
        if let endObserver = playerItemDidPlayToEndObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.playerItemDidPlayToEndObserver = nil
        }
        if let playerRateObserver = playerRateObserver {
            playerRateObserver.invalidate()
            self.playerRateObserver = nil
        }
        if let playerLayer = playerLayer {
            playerLayer.player = nil
            playerLayer.removeFromSuperlayer()
            self.playerLayer = nil
        }
        if let player = player {
            player.replaceCurrentItem(with: nil)
            self.player = nil
        }
        if playerItem != nil {
            self.playerItem = nil
        }
        if let contentView = self.contentView {
            contentView.layer = nil
            contentView.wantsLayer = false
        }
        isBeingTornDown = false
        memoryLogger.info("✅ Limpieza de recursos completada para \(self.videoURL.lastPathComponent)")
    }

    deinit {
        memoryLogger.info("🧹 [deinit] Iniciando deinit para DesktopVideoWindowMejorada de \(self.videoURL.lastPathComponent)")
        if !isClosing {
            memoryLogger.warning("⚠️ [deinit] Llamado sin cierre previo. Ejecutando limpieza de emergencia.")
            cleanupResources()
        }
        memoryLogger.info("✅ [deinit] Completado para DesktopVideoWindowMejorada de \(self.videoURL.lastPathComponent)")
    }

    private func showErrorInWindow(_ message: String) {
        guard let contentView = self.contentView else { return }
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
        errorLabel.maximumNumberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        contentView.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        ])
        memoryLogger.warning("⚠️ Mostrando error en ventana: \(message)")
    }
}
