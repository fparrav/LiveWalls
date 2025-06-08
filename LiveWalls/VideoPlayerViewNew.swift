import SwiftUI
import AVFoundation

/// Nueva implementación de VideoPlayerView que evita los problemas de gestión de memoria
/// usando un patrón de arquitectura más seguro y AVPlayerLayer directamente.
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
        // private var playerView: AVPlayerView? // Eliminado
        var playerLayer: AVPlayerLayer? // Nuevo: para AVFoundation, cambiado de private a internal (default)
        var player: AVPlayer? // Cambiado de private a internal (default)
        private var playerItem: AVPlayerItem?
        private var loopObserver: NSObjectProtocol?
        private let syncQueue = DispatchQueue(label: "video.sync", qos: .userInitiated)
        
        override init() {
            super.init()
            print("🎬 Nuevo Coordinator creado")
        }
        
        func setupPlayer(for url: URL, shouldLoop: Bool, aspectFill: Bool, in view: NSView) { // Modificado para aceptar NSView
            syncQueue.async { [weak self] in
                self?.cleanupCurrentPlayer()
                self?.createNewPlayer(for: url, shouldLoop: shouldLoop, aspectFill: aspectFill, in: view) // Modificado
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

                // Limpiar playerLayer
                if let layer = self.playerLayer {
                    layer.player = nil
                    layer.removeFromSuperlayer()
                    self.playerLayer = nil
                }
                
                // Limpiar player
                self.player?.pause()
                self.player?.replaceCurrentItem(with: nil)
                self.player = nil
                
                // Limpiar playerItem
                self.playerItem = nil
                
                print("✅ Player limpiado")
            }
        }
        
        private func createNewPlayer(for url: URL, shouldLoop: Bool, aspectFill: Bool, in view: NSView) { // Modificado para aceptar NSView
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

                // Configurar playerLayer y añadirlo a la vista
                let newPlayerLayer = AVPlayerLayer(player: newPlayer)
                newPlayerLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
                newPlayerLayer.frame = view.bounds // Ajustar al tamaño de la vista contenedora
                
                // Asegurarse de que la vista contenedora tenga una capa
                if view.layer == nil {
                    view.wantsLayer = true
                }
                view.layer?.addSublayer(newPlayerLayer)
                
                // Guardar referencias después de configurar
                self.player = newPlayer
                self.playerItem = newPlayerItem
                self.playerLayer = newPlayerLayer // Guardar referencia al layer
                
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
        
        // func updatePlayerView(_ playerView: AVPlayerView) { // Eliminado o cambiar propósito
        //     self.playerView = playerView
        // }
        
        func updateContainingView(_ view: NSView) {
            // Esta función puede ser usada si el coordinator necesita una referencia a la NSView
            // Por ejemplo, para ajustar el frame del playerLayer si la vista cambia de tamaño.
            // Por ahora, el frame se establece en createNewPlayer y se actualizará en updateNSView.
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
    
    func makeNSView(context: Context) -> NSView { // Modificado: Retorna NSView
        let view = NSView()
        view.wantsLayer = true // Esencial para añadir AVPlayerLayer
        
        print("🎬 Creando nueva NSView para AVPlayerLayer")
        
        // Configurar el player y playerLayer a través del coordinator
        // Pasamos la vista para que el coordinator pueda añadir la capa de video.
        context.coordinator.setupPlayer(for: url, shouldLoop: shouldLoop, aspectFill: aspectFill, in: view)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) { // Modificado: Acepta NSView
        print("🔄 Actualizando NSView para: \(url.lastPathComponent)")
        
        // Ajustar el frame del playerLayer si el tamaño de la vista cambió
        if let playerLayer = context.coordinator.playerLayer, playerLayer.superlayer === nsView.layer {
            if playerLayer.frame != nsView.bounds {
                playerLayer.frame = nsView.bounds
                print("🔄 Frame de AVPlayerLayer actualizado a: \(nsView.bounds)")
            }
        }
        
        // Verificar si la URL cambió
        // La lógica original para cambiar de player si la URL cambia se mantiene,
        // pero setupPlayer ahora toma 'nsView' como argumento.
        if let currentAsset = context.coordinator.player?.currentItem?.asset as? AVURLAsset,
           currentAsset.url != url {
            
            print("🎯 URL cambió de \(currentAsset.url.lastPathComponent) a \(url.lastPathComponent)")
            context.coordinator.setupPlayer(for: url, shouldLoop: shouldLoop, aspectFill: aspectFill, in: nsView)
        } else if context.coordinator.player == nil { // Si no hay player, configurarlo
            print("🤔 No hay player existente, configurando uno nuevo en updateNSView.")
            context.coordinator.setupPlayer(for: url, shouldLoop: shouldLoop, aspectFill: aspectFill, in: nsView)
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { // Modificado: Acepta NSView
        print("🧹 Desmontando NSView...")
        coordinator.cleanup() // El coordinator debería manejar la limpieza de su playerLayer
        // nsView.player = nil // nsView ya no es AVPlayerView
        // Quitar la capa explícitamente si es necesario, aunque cleanup del coordinator debería hacerlo.
        nsView.layer?.sublayers?.removeAll(where: { $0 is AVPlayerLayer })
        print("✅ NSView desmontado correctamente")
    }
}

// Mantener compatibilidad con el código existente
typealias VideoPlayerView = VideoPlayerViewNew
