import Foundation
import AVFoundation
import AppKit
import os.log

/// Gestor especializado para recursos de video que previene crashes y leaks de memoria
/// Implementa las mejores prácticas para AVPlayer en Swift/SwiftUI
final class VideoPlayerResourceManager {
    
    // MARK: - Logger especializado
    private static let logger = Logger(subsystem: "com.livewalls.app", category: "VideoResourceManager")
    
    // MARK: - Gestión de observadores seguros
    private var observations: [NSKeyValueObservation] = []
    private var notificationObservers: [NSObjectProtocol] = []
    
    // MARK: - Estado de limpieza
    private var isCleaningUp = false
    private let cleanupQueue = DispatchQueue(label: "video.cleanup", qos: .utility)
    
    // MARK: - Referencias débiles para prevenir retain cycles
    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?
    private weak var playerLayer: AVPlayerLayer?
    
    init() {
        Self.logger.info("🔧 VideoPlayerResourceManager inicializado")
    }
    
    /// Configura observadores seguros para AVPlayer usando las mejores prácticas de Swift
    func setupSafeObservers(player: AVPlayer, playerItem: AVPlayerItem, playerLayer: AVPlayerLayer) {
        self.player = player
        self.playerItem = playerItem
        self.playerLayer = playerLayer
        
        // 1. Observador de estado usando NSKeyValueObservation (Swift moderno)
        let statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            guard let self = self, !self.isCleaningUp else { return }
            
            DispatchQueue.main.async {
                self.handlePlayerItemStatusChange(item: item, status: item.status)
            }
        }
        observations.append(statusObservation)
        
        // 2. Observador de buffer usando NSKeyValueObservation
        let bufferObservation = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, change in
            guard let self = self, !self.isCleaningUp else { return }
            Self.logger.debug("📊 Buffer state changed - empty: \(item.isPlaybackBufferEmpty)")
        }
        observations.append(bufferObservation)
        
        // 3. Observador de fin de reproducción usando NotificationCenter
        let endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEnd,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, !self.isCleaningUp else { return }
            self.handlePlaybackEnd()
        }
        notificationObservers.append(endObserver)
        
        // 4. Observador de fallos
        let failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, !self.isCleaningUp else { return }
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                Self.logger.error("❌ Player falló: \(error.localizedDescription)")
            }
        }
        notificationObservers.append(failedObserver)
        
        Self.logger.info("✅ Observadores seguros configurados")
    }
    
    /// Limpieza segura y completa de todos los recursos
    func cleanupAllResources() {
        guard !isCleaningUp else {
            Self.logger.warning("⚠️ Limpieza ya en progreso, ignorando llamada duplicada")
            return
        }
        
        isCleaningUp = true
        Self.logger.info("🧹 Iniciando limpieza completa de recursos de video")
        
        cleanupQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Pausar reproductor inmediatamente
            DispatchQueue.main.sync {
                self.player?.pause()
                Self.logger.debug("⏸️ Reproductor pausado")
            }
            
            // 2. Limpiar observadores KVO de forma segura
            self.observations.forEach { observation in
                observation.invalidate()
            }
            self.observations.removeAll()
            Self.logger.debug("👁️ Observadores KVO limpiados")
            
            // 3. Limpiar observadores de NotificationCenter
            self.notificationObservers.forEach { observer in
                NotificationCenter.default.removeObserver(observer)
            }
            self.notificationObservers.removeAll()
            Self.logger.debug("📢 Observadores de notificaciones limpiados")
            
            // 4. Limpiar en el hilo principal
            DispatchQueue.main.async {
                self.cleanupPlayerResources()
                self.isCleaningUp = false
                Self.logger.info("✅ Limpieza completa finalizada")
            }
        }
    }
    
    private func cleanupPlayerResources() {
        // 1. Limpiar PlayerLayer
        if let layer = playerLayer {
            layer.player = nil
            layer.removeFromSuperlayer()
            Self.logger.debug("🎭 PlayerLayer desconectado")
        }
        
        // 2. Limpiar Player de forma segura
        if let currentPlayer = player {
            currentPlayer.replaceCurrentItem(with: nil)
            currentPlayer.pause()
            Self.logger.debug("🎮 Player limpiado")
        }
        
        // 3. Cancelar carga del asset si está en progreso
        if let item = playerItem {
            item.asset.cancelLoading()
            Self.logger.debug("🎬 Asset loading cancelado")
        }
        
        // 4. Limpiar referencias débiles
        self.player = nil
        self.playerItem = nil
        self.playerLayer = nil
    }
    
    // MARK: - Handlers de eventos
    
    private func handlePlayerItemStatusChange(item: AVPlayerItem, status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            Self.logger.info("✅ Player listo para reproducir")
            player?.play()
            
        case .failed:
            if let error = item.error {
                Self.logger.error("❌ Player falló: \(error.localizedDescription)")
            }
            
        case .unknown:
            Self.logger.debug("❓ Estado de player desconocido")
            
        @unknown default:
            Self.logger.warning("⚠️ Estado de player no manejado: \(status.rawValue)")
        }
    }
    
    private func handlePlaybackEnd() {
        Self.logger.info("🔄 Reproducción terminada, reiniciando...")
        player?.seek(to: .zero)
        player?.play()
    }
    
    deinit {
        Self.logger.info("🧹 Deinicializando VideoPlayerResourceManager")
        if !isCleaningUp {
            cleanupAllResources()
        }
    }
}

// MARK: - Extensión para configuración segura de AVPlayer

extension AVPlayer {
    
    /// Configuración segura para wallpaper con mejores prácticas
    func configurarParaWallpaper() {
        // Configuración optimizada para background playback
        self.actionAtItemEnd = .none
        self.automaticallyWaitsToMinimizeStalling = false
        
        // Volumen silenciado para wallpaper
        self.volume = 0.0
        self.isMuted = true
        
        // Configuración de rate para suavidad
        self.rate = 1.0
    }
}

extension AVPlayerLayer {
    
    /// Configuración segura para display en ventana de escritorio
    func configurarParaEscritorio(frame: CGRect) {
        self.frame = frame
        self.videoGravity = .resizeAspectFill
        self.isOpaque = true
        
        // Optimizaciones para rendimiento
        self.backgroundColor = CGColor.black
        self.masksToBounds = true
    }
}
