// Implementación unificada de DesktopVideoWindowMejorada
// Esta clase reemplaza a DesktopVideoWindow y debe ser usada en todo el proyecto.

import Cocoa
import CoreGraphics
import AVFoundation
import os.log
import Foundation
import AppKit

// Logger específico para debugging de memoria
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

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
    private var isClosing: Bool = false
    private var isPlayerSetupInProgress: Bool = false
    private var isBeingTornDown: Bool = false
    private let setupLock = NSLock()
    private let cleanupLock = NSLock()
    private let setupQueue = DispatchQueue(label: "com.livewalls.window.setup", qos: .userInitiated)
    private let cleanupQueue = DispatchQueue(label: "com.livewalls.window.cleanup", qos: .userInitiated)

    // Definición de la propiedad playerItem
    private var playerItem: AVPlayerItem?

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
        self.styleMask = [.borderless, .fullSizeContentView]
        
        // Optimizaciones adicionales
        self.acceptsMouseMovedEvents = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false // Cambiado a false para controlar el ciclo de vida
        self.hidesOnDeactivate = false
        self.isExcludedFromWindowsMenu = true
        self.showsResizeIndicator = false
        self.showsToolbarButton = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.toolbar = nil
    }

    private func setupPlayer(with url: URL) async {
        await withCheckedContinuation { continuation in
            setupLock.lock()
            guard !isPlayerSetupInProgress, !isBeingTornDown else {
                setupLock.unlock()
                memoryLogger.warning("⚠️ Setup de player cancelado - ya en progreso o siendo destruido")
                continuation.resume()
                return
            }
            isPlayerSetupInProgress = true
            setupLock.unlock()

            let asset = AVURLAsset(url: url)
            Task {
                do {
                    let (isPlayable, _) = try await asset.load(.isPlayable, .tracks)
                    
                    guard isPlayable else {
                        throw NSError(domain: "com.livewalls.error", code: -1, userInfo: [NSLocalizedDescriptionKey: "El video no es reproducible"])
                    }

                    await MainActor.run {
                        setupLock.lock()
                        defer { 
                            setupLock.unlock()
                            self.isPlayerSetupInProgress = false
                        }
                        
                        guard !isBeingTornDown else {
                            memoryLogger.warning("⚠️ Setup cancelado: ventana siendo destruida")
                            continuation.resume()
                            return
                        }

                        // Crear componentes en orden específico
                        let newPlayerItem = AVPlayerItem(asset: asset)
                        let newPlayer = AVPlayer(playerItem: newPlayerItem)
                        
                        // Configuración optimizada para reproducción en segundo plano
                        newPlayer.actionAtItemEnd = .none
                        newPlayer.volume = 0.0
                        newPlayer.automaticallyWaitsToMinimizeStalling = false
                        newPlayer.isMuted = true
                        newPlayer.rate = 1.0 // Asegurar que la velocidad sea 1.0
                        
                        // Configurar playerLayer con optimizaciones
                        let newPlayerLayer = AVPlayerLayer(player: newPlayer)
                        newPlayerLayer.videoGravity = .resizeAspectFill
                        newPlayerLayer.frame = self.contentView?.bounds ?? .zero
                        newPlayerLayer.isOpaque = true
                        newPlayerLayer.backgroundColor = CGColor.black
                        newPlayerLayer.masksToBounds = true
                        newPlayerLayer.shouldRasterize = true // Optimizar renderizado
                        newPlayerLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 1.0
                        newPlayerLayer.drawsAsynchronously = true // Renderizado asíncrono

                        // Añadir layer a la vista
                        if let contentView = self.contentView {
                            if contentView.layer == nil {
                                contentView.wantsLayer = true
                            }
                            contentView.layer?.addSublayer(newPlayerLayer)
                        }

                        // Configurar observadores
                        setupObservers(player: newPlayer, playerItem: newPlayerItem)

                        // Guardar referencias
                        self.player = newPlayer
                        self.playerItem = newPlayerItem
                        self.playerLayer = newPlayerLayer

                        // Iniciar reproducción
                        newPlayer.play()
                        
                        memoryLogger.info("✅ Player configurado exitosamente para: \(url.lastPathComponent)")
                        continuation.resume()
                    }
                } catch {
                    memoryLogger.error("❌ Error configurando player: \(error.localizedDescription)")
                    await MainActor.run {
                        self.setupLock.lock()
                        self.isPlayerSetupInProgress = false
                        self.setupLock.unlock()
                        
                        self.cleanupPlayer { [weak self] in
                            self?.showErrorInWindow("Error cargando video: \(error.localizedDescription)")
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func setupObservers(player: AVPlayer, playerItem: AVPlayerItem) {
        // Observar estado del playerItem
        playerItemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                memoryLogger.info("✅ PlayerItem listo para reproducir")
                player.play()
            case .failed:
                memoryLogger.error("❌ PlayerItem falló: \(item.error?.localizedDescription ?? "Error desconocido")")
                self.cleanupPlayer()
            case .unknown:
                memoryLogger.warning("⚠️ PlayerItem en estado desconocido")
            @unknown default:
                memoryLogger.warning("⚠️ PlayerItem en estado no manejado")
            }
        }

        // Observar tasa de reproducción
        playerRateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            if player.rate == 0 && !self.isClosing {
                memoryLogger.warning("⚠️ Player se detuvo inesperadamente")
                player.play()
            }
        }

        // Observar fin de reproducción
        playerItemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.isClosing {
                memoryLogger.info("🔄 Video llegó al final, reiniciando...")
                player.seek(to: .zero)
                player.play()
            }
        }
    }

    /// Limpia de manera segura todos los recursos del player
    /// Basado en las mejores prácticas de Swift Foundation para concurrencia
    private func cleanupPlayer(completion: @escaping () -> Void = {}) {
        // Usar defer para garantizar unlock del lock
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        
        guard !isBeingTornDown else {
            completion()
            return
        }
        isBeingTornDown = true
        
        // Capturar referencias ANTES de limpiar para thread safety
        let components = (
            player: self.player,
            playerLayer: self.playerLayer,
            playerItem: self.playerItem,
            statusObserver: self.playerItemStatusObserver,
            rateObserver: self.playerRateObserver,
            endObserver: self.playerItemDidPlayToEndObserver
        )
        
        // Limpiar referencias atómicamente
        self.player = nil
        self.playerItem = nil
        self.playerLayer = nil
        self.playerItemStatusObserver = nil
        self.playerRateObserver = nil
        self.playerItemDidPlayToEndObserver = nil
        
        // Realizar limpieza asíncrona para evitar deadlocks
        let performCleanupAsync = {
            // Limpiar observadores PRIMERO
            components.statusObserver?.invalidate()
            components.rateObserver?.invalidate()
            
            if let observer = components.endObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            
            // Detener player ANTES de remover layer
            components.player?.pause()
            components.player?.replaceCurrentItem(with: nil)
            
            // Remover layer del superlayer
            components.playerLayer?.removeFromSuperlayer()
            
            memoryLogger.info("🧹 Player limpiado exitosamente")
            
            // Ejecutar completion en el hilo principal
            DispatchQueue.main.async {
                completion()
            }
        }
        
        // Ejecutar limpieza de manera thread-safe
        if Thread.isMainThread {
            // Si estamos en el hilo principal, ejecutar asíncronamente para evitar bloqueos
            DispatchQueue.main.async(execute: performCleanupAsync)
        } else {
            // Si estamos en otro hilo, ejecutar directamente
            performCleanupAsync()
        }
    }

    /// Cierra la ventana y libera los recursos asociados.
    public func close(completion: @escaping () -> Void = {}) {
        // Evitar cierre múltiple
        if isClosing { 
            completion()
            return 
        }
        isClosing = true
        
        memoryLogger.info("🚪 Cerrando ventana de video...")
        
        // Limpiar recursos antes de cerrar la ventana
        cleanupPlayer { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            
            // Cerrar la ventana en el hilo principal
            DispatchQueue.main.async { [weak self] in
                self?.performClose()
                completion()
            }
        }
    }
    
    /// Método privado para cerrar la ventana
    private func performClose() {
        super.close()
    }
    
    /// Override del método close() original para mantener compatibilidad
    public override func close() {
        close(completion: {})
    }

    deinit {
        memoryLogger.info("🧹 Deinicializando ventana de video")
        // Asegurar limpieza final si no se hizo antes
        if !isBeingTornDown {
            cleanupPlayer()
        }
    }

    // MARK: - Public API para acceso al reproductor
    
    /// Obtiene el tiempo actual de reproducción del video
    /// - Returns: CMTime actual del reproductor o nil si no hay reproductor activo
    public func getCurrentTime() -> CMTime? {
        return player?.currentTime()
    }
    
    /// Obtiene el estado actual del reproductor
    /// - Returns: Velocidad de reproducción actual (0.0 = pausado, 1.0 = reproduciendo normal)
    public func getPlaybackRate() -> Float? {
        return player?.rate
    }
    
    /// Obtiene la duración total del video actual
    /// - Returns: CMTime con la duración total o nil si no está disponible
    public func getTotalDuration() -> CMTime? {
        return player?.currentItem?.duration
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
