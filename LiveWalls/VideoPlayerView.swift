import SwiftUI
import AVFoundation
import AVKit

struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    let shouldLoop: Bool
    let aspectFill: Bool
    
    init(url: URL, shouldLoop: Bool = true, aspectFill: Bool = true) {
        self.url = url
        self.shouldLoop = shouldLoop
        self.aspectFill = aspectFill
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: VideoPlayerView
        
        init(_ parent: VideoPlayerView) {
            self.parent = parent
        }
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "status" {
                if let playerItem = object as? AVPlayerItem {
                    switch playerItem.status {
                    case .readyToPlay:
                        print("Video listo para reproducir: \(parent.url.lastPathComponent)")
                        playerItem.seek(to: .zero, completionHandler: nil)
                        // Obtener el player desde el playerView que debe estar configurado
                    case .failed:
                        if let error = playerItem.error {
                            print("Error al reproducir video: \(error.localizedDescription)")
                            print("URL: \(parent.url.path)")
                        }
                    case .unknown:
                        print("Estado desconocido del video")
                    @unknown default:
                        print("Estado no manejado del video")
                    }
                }
            }
        }
    }
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        
        // Verificar que el archivo existe antes de intentar reproducirlo
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Error: Archivo de video no encontrado: \(url.path)")
            return playerView
        }
        
        // Crear asset y verificar que es válido
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Observar errores en el playerItem
        playerItem.addObserver(context.coordinator, 
                              forKeyPath: "status", 
                              options: [.new, .initial], 
                              context: nil)
        
        let player = AVPlayer(playerItem: playerItem)
        
        playerView.player = player
        playerView.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        playerView.controlsStyle = .none
        playerView.showsFrameSteppingButtons = false
        playerView.showsSharingServiceButton = false
        playerView.showsFullScreenToggleButton = false
        
        // Configurar para que el video se reproduzca en loop
        if shouldLoop {
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
        }
        
        // Silenciar el video por defecto
        player.isMuted = true
        
        // Iniciar reproducción cuando esté listo
        player.play()
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Si la URL cambió, actualizar el player
        if let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL != url {
            let newPlayer = AVPlayer(url: url)
            nsView.player = newPlayer
            
            if shouldLoop {
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: newPlayer.currentItem,
                    queue: .main
                ) { _ in
                    newPlayer.seek(to: .zero)
                    newPlayer.play()
                }
            }
            
            newPlayer.isMuted = true
            newPlayer.play()
        }
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
        NotificationCenter.default.removeObserver(nsView)
    }
}

// Vista previa del video con controles básicos
struct VideoPreviewView: View {
    let videoFile: VideoFile
    @State private var isPlaying = false
    
    var body: some View {
        ZStack {
            VideoPlayerView(url: videoFile.url, shouldLoop: true, aspectFill: false)
                .cornerRadius(8)
            
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        isPlaying.toggle()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding()
            }
        }
    }
}
