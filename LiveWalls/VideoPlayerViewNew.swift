import SwiftUI
import AVFoundation
import AVKit

/// Nueva implementación de VideoPlayerView que evita los problemas de gestión de memoria
/// usando un patrón de arquitectura más seguro
struct VideoPlayerViewNew: NSViewRepresentable {
    let url: URL
    let shouldLoop: Bool
    let aspectFill: Bool
    
    init(url: URL, shouldLoop: Bool = true, aspectFill: Bool = true) {
        self.url = url
        self.shouldLoop = shouldLoop
        self.aspectFill = aspectFill
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        private var playerView: AVPlayerView?
        private var player: AVPlayer?
        private var playerItem: AVPlayerItem?
        private var loopObserver: NSObjectProtocol?
        private let syncQueue = DispatchQueue(label: "video.sync", qos: .userInitiated)
        
        override init() {
            super.init()
            print("🎬 Nuevo Coordinator creado")
        }
        
        func setupPlayer(for url: URL, shouldLoop: Bool, aspectFill: Bool) {
            syncQueue.async { [weak self] in
                self?.cleanupCurrentPlayer()
                self?.createNewPlayer(for: url, shouldLoop: shouldLoop, aspectFill: aspectFill)
            }
        }
        
        private func cleanupCurrentPlayer() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                print("🧹 Limpiando player actual...")
                
                // Remover observer de loop
                if let observer = self.loopObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.loopObserver = nil
                }
                
                // Limpiar player
                self.player?.pause()
                self.player?.replaceCurrentItem(with: nil)
                self.player = nil
                
                // Limpiar playerItem
                self.playerItem = nil
                
                // Limpiar playerView
                self.playerView?.player = nil
                
                print("✅ Player limpiado")
            }
        }
        
        private func createNewPlayer(for url: URL, shouldLoop: Bool, aspectFill: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                print("🎬 Creando nuevo player para: \(url.lastPathComponent)")
                
                // Verificar que el archivo existe
                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("❌ Error: Archivo de video no encontrado: \(url.path)")
                    return
                }
                
                // Crear componentes en orden específico para evitar retención circular
                let asset = AVURLAsset(url: url)
                let newPlayerItem = AVPlayerItem(asset: asset)
                let newPlayer = AVPlayer(playerItem: newPlayerItem)
                
                // Configurar player antes de asignar
                newPlayer.isMuted = true
                
                // Configurar playerView si existe
                if let playerView = self.playerView {
                    playerView.player = newPlayer
                    playerView.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
                    playerView.controlsStyle = .none
                    playerView.showsFrameSteppingButtons = false
                    playerView.showsSharingServiceButton = false
                    playerView.showsFullScreenToggleButton = false
                }
                
                // Guardar referencias después de configurar
                self.player = newPlayer
                self.playerItem = newPlayerItem
                
                // Configurar loop si es necesario
                if shouldLoop {
                    self.setupLooping(for: newPlayer)
                }
                
                // Iniciar reproducción
                newPlayer.play()
                
                print("✅ Nuevo player configurado correctamente")
            }
        }
        
        private func setupLooping(for player: AVPlayer) {
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak player] _ in
                print("🔄 Video terminó, reiniciando...")
                player?.seek(to: .zero)
                player?.play()
            }
            self.loopObserver = observer
        }
        
        func updatePlayerView(_ playerView: AVPlayerView) {
            self.playerView = playerView
        }
        
        func cleanup() {
            print("🧹 Limpieza final del coordinator...")
            syncQueue.async { [weak self] in
                self?.cleanupCurrentPlayer()
            }
        }
        
        deinit {
            print("🔄 Coordinator deinitializing...")
            cleanup()
            print("🔄 Coordinator deinitializado")
        }
    }
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        
        print("🎬 Creando nueva AVPlayerView")
        
        // Configurar el playerView
        context.coordinator.updatePlayerView(playerView)
        context.coordinator.setupPlayer(for: url, shouldLoop: shouldLoop, aspectFill: aspectFill)
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        print("🔄 Actualizando NSView para: \(url.lastPathComponent)")
        
        // Verificar si la URL cambió
        if let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL != url {
            
            print("🎯 URL cambió de \(currentURL.lastPathComponent) a \(url.lastPathComponent)")
            context.coordinator.setupPlayer(for: url, shouldLoop: shouldLoop, aspectFill: aspectFill)
        }
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        print("🧹 Desmontando NSView...")
        coordinator.cleanup()
        nsView.player = nil
        print("✅ NSView desmontado correctamente")
    }
}

// Mantener compatibilidad con el código existente
typealias VideoPlayerView = VideoPlayerViewNew
