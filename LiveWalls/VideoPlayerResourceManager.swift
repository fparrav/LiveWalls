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
    private let cleanupLock = NSLock()
    
    // MARK: - Referencias débiles para prevenir retain cycles
    private weak var player: AVPlayer?
    private weak var playerItem: AVPlayerItem?
    private weak var playerLayer: AVPlayerLayer?
    
    init() {
        Self.logger.info("🔧 VideoPlayerResourceManager inicializado")
    }
    
    /// Configura observadores seguros para AVPlayer usando las mejores prácticas de Swift
    func setupSafeObservers(player: AVPlayer, playerItem: AVPlayerItem, playerLayer: AVPlayerLayer) {
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        
        guard !isCleaningUp else {
            Self.logger.error("⚠️ Intento de configurar observadores durante limpieza")
            return
        }
        
        self.player = player
        self.playerItem = playerItem
        self.playerLayer = playerLayer
        
        // 1. Observador de estado usando NSKeyValueObservation (Swift moderno)
        let statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
            guard let self = self else { return }
            
            self.cleanupLock.lock()
            defer { self.cleanupLock.unlock() }
            
            guard !self.isCleaningUp else { return }
            
            DispatchQueue.main.async {
                self.handlePlayerItemStatusChange(item: item, status: item.status)
            }
        }
        observations.append(statusObservation)
        
        // 2. Observador de buffer usando NSKeyValueObservation
        let bufferObservation = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, change in
            guard let self = self else { return }
            
            self.cleanupLock.lock()
            defer { self.cleanupLock.unlock() }
            
            guard !self.isCleaningUp else { return }
            
            Self.logger.debug("📊 Buffer state changed - empty: \(item.isPlaybackBufferEmpty)")
        }
        observations.append(bufferObservation)
        
        // 3. Observador de fin de reproducción usando NotificationCenter
        let endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEnd,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            self.cleanupLock.lock()
            defer { self.cleanupLock.unlock() }
            
            guard !self.isCleaningUp else { return }
            
            self.handlePlaybackEnd()
        }
        notificationObservers.append(endObserver)
        
        // 4. Observador de fallos
        let failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            self.cleanupLock.lock()
            defer { self.cleanupLock.unlock() }
            
            guard !self.isCleaningUp else { return }
            
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                Self.logger.error("❌ Error de reproducción: \(error.localizedDescription)")
            }
        }
        notificationObservers.append(failedObserver)
    }
    
    /// Limpia todos los recursos de forma segura
    func cleanupAllResources() {
        cleanupLock.lock()
        guard !isCleaningUp else {
            cleanupLock.unlock()
            return
        }
        isCleaningUp = true
        cleanupLock.unlock()
        
        Self.logger.info("🧹 Iniciando limpieza de recursos...")
        
        // Ejecutar limpieza en queue dedicada
        cleanupQueue.async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                // 1. Remover observadores
                self.observations.forEach { $0.invalidate() }
                self.observations.removeAll()
                
                self.notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
                self.notificationObservers.removeAll()
                
                // 2. Limpiar PlayerLayer
                if let layer = self.playerLayer {
                    DispatchQueue.main.async {
                        layer.player = nil
                        layer.removeFromSuperlayer()
                    }
                    Self.logger.debug("🎭 PlayerLayer desconectado")
                }
                
                // 3. Limpiar Player
                if let currentPlayer = self.player {
                    DispatchQueue.main.async {
                        currentPlayer.pause()
                        currentPlayer.replaceCurrentItem(with: nil)
                    }
                    Self.logger.debug("🎮 Player limpiado")
                }
                
                // 4. Cancelar carga del asset
                if let item = self.playerItem {
                    item.asset.cancelLoading()
                    Self.logger.debug("🎬 Asset loading cancelado")
                }
                
                // 5. Limpiar referencias
                self.player = nil
                self.playerItem = nil
                self.playerLayer = nil
            }
            
            Self.logger.info("✅ Limpieza de recursos completada")
        }
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
        cleanupAllResources()
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
