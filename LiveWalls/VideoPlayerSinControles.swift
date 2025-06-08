import SwiftUI
import AVKit
import AVFoundation

/// Componente de video player personalizado sin controles visibles
/// Utilizado para vista previa de videos en la interfaz principal
struct VideoPlayerSinControles: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        let player = AVPlayer(url: url)
        
        // Configurar el player view para ocultar todos los controles
        playerView.player = player
        playerView.controlsStyle = .none // Ocultar controles completamente
        playerView.showsFrameSteppingButtons = false
        playerView.showsFullScreenToggleButton = false
        playerView.showsSharingServiceButton = false
        playerView.actionPopUpButtonMenu = nil
        
        // Configurar reproducción automática y en bucle
        player.play()
        
        // Agregar observer para reproducción en bucle
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Actualizar la URL si es necesaria
        if nsView.player?.currentItem?.asset != AVURLAsset(url: url) {
            let newPlayer = AVPlayer(url: url)
            nsView.player = newPlayer
            newPlayer.play()
            
            // Reconfigurar el observer para el nuevo item
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }
        }
    }
}

/// Versión alternativa usando VideoPlayer de SwiftUI con configuración personalizada
struct VideoPlayerConControlesOcultos: View {
    let url: URL
    @State private var player: AVPlayer
    
    init(url: URL) {
        self.url = url
        self._player = State(initialValue: AVPlayer(url: url))
    }
    
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                // Configurar el player para ocultar controles usando KVO
                configurePlayerForHiddenControls()
                player.play()
            }
            .onDisappear {
                player.pause()
            }
            .disabled(true) // Prevenir interacción del usuario
            .allowsHitTesting(false) // Desactivar completamente la interacción
    }
    
    private func configurePlayerForHiddenControls() {
        // Buscar la AVPlayerView en la jerarquía de vistas y configurarla
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let playerView = findAVPlayerView() {
                playerView.controlsStyle = .none
                playerView.showsFrameSteppingButtons = false
                playerView.showsFullScreenToggleButton = false
                playerView.showsSharingServiceButton = false
            }
        }
    }
    
    private func findAVPlayerView() -> AVPlayerView? {
        // Esta función busca recursivamente la AVPlayerView en la jerarquía
        guard let window = NSApp.keyWindow else { return nil }
        return findAVPlayerView(in: window.contentView)
    }
    
    private func findAVPlayerView(in view: NSView?) -> AVPlayerView? {
        guard let view = view else { return nil }
        
        if let playerView = view as? AVPlayerView {
            return playerView
        }
        
        for subview in view.subviews {
            if let found = findAVPlayerView(in: subview) {
                return found
            }
        }
        
        return nil
    }
}
