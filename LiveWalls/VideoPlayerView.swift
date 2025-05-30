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
        var parent: VideoPlayerView?
        private var observedItems: Set<AVPlayerItem> = []
        private var notificationObservers: [NSObjectProtocol] = []
        private var isCleanedUp = false
        private let cleanupQueue = DispatchQueue(label: "video.cleanup", qos: .userInitiated)
        
        init(_ parent: VideoPlayerView) {
            self.parent = parent
            super.init()
            self.logDebug("🎬 Coordinator: Initialized for \(parent.url.lastPathComponent)")
        }
        
        // Simple logging function for crash debugging
        func logDebug(_ message: String) {
            let timestamp = DateFormatter().string(from: Date())
            let logEntry = "[\(timestamp)] \(message)"
            print("🐛 \(logEntry)")
            
            // Also write to file for persistence
            DispatchQueue.global(qos: .utility).async {
                if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let logFile = documentsPath.appendingPathComponent("LiveWalls_debug.log")
                    if let data = "\(logEntry)\n".data(using: .utf8) {
                        if FileManager.default.fileExists(atPath: logFile.path) {
                            if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                                fileHandle.seekToEndOfFile()
                                fileHandle.write(data)
                                fileHandle.closeFile()
                            }
                        } else {
                            try? data.write(to: logFile)
                        }
                    }
                }
            }
        }
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            guard !isCleanedUp, let parent = parent else { return }
            
            if keyPath == "status" {
                if let playerItem = object as? AVPlayerItem {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, !self.isCleanedUp else { return }
                        
                        switch playerItem.status {
                        case .readyToPlay:
                            print("✅ Video listo para reproducir: \(parent.url.lastPathComponent)")
                            playerItem.seek(to: .zero, completionHandler: nil)
                        case .failed:
                            if let error = playerItem.error {
                                print("❌ Error al reproducir video: \(error.localizedDescription)")
                                print("URL: \(parent.url.path)")
                            }
                        case .unknown:
                            print("⚠️ Estado desconocido del video")
                        @unknown default:
                            print("⚠️ Estado no manejado del video")
                        }
                    }
                }
            }
        }
        
        func addObserver(for playerItem: AVPlayerItem) {
            guard !isCleanedUp, !observedItems.contains(playerItem) else { return }
            
            playerItem.addObserver(self,
                                  forKeyPath: "status",
                                  options: [.new, .initial],
                                  context: nil)
            observedItems.insert(playerItem)
            print("🔍 Observer añadido para playerItem: \(playerItem)")
        }
        
        func removeObserver(for playerItem: AVPlayerItem) {
            guard !isCleanedUp, observedItems.contains(playerItem) else { return }
            
            // Remover observer de forma segura con manejo de errores silencioso
            playerItem.removeObserver(self, forKeyPath: "status")
            observedItems.remove(playerItem)
            print("🗑️ Observer removido para playerItem: \(playerItem)")
        }
        
        func addNotificationObserver(_ observer: NSObjectProtocol) {
            guard !isCleanedUp else { return }
            notificationObservers.append(observer)
        }
        
        func cleanup() {
            guard !isCleanedUp else { 
                logDebug("🧹 cleanup(): Already cleaned up, skipping")
                return 
            }
            
            logDebug("🧹 cleanup(): Starting aggressive coordinator cleanup")
            isCleanedUp = true
            
            // Cleanup en background queue para evitar race conditions
            cleanupQueue.async { [weak self] in
                guard let self = self else { 
                    print("🧹 cleanup(): Self is nil in cleanup queue")
                    return 
                }
                
                self.logDebug("🧹 cleanup(): In cleanup queue, cloning collections")
                
                // Clonar las colecciones para limpieza segura
                let itemsToClean = Array(self.observedItems)
                let observersToClean = Array(self.notificationObservers)
                
                self.logDebug("🧹 cleanup(): Cloned \(itemsToClean.count) items and \(observersToClean.count) observers")
                
                // Limpiar en main queue
                DispatchQueue.main.async {
                    self.logDebug("🧹 cleanup(): In main queue, starting observer removal")
                    
                    // Remover todos los observers de AVPlayerItem de forma segura
                    for (index, item) in itemsToClean.enumerated() {
                        self.logDebug("🧹 cleanup(): Removing observer \(index + 1)/\(itemsToClean.count)")
                        // Usar un bloque silencioso para evitar crashes
                        autoreleasepool {
                            item.removeObserver(self, forKeyPath: "status")
                        }
                        self.logDebug("🗑️ cleanup(): Observer removed safely for item \(index + 1)")
                    }
                    
                    self.logDebug("🧹 cleanup(): Starting notification observer removal")
                    
                    // Remover todos los notification observers
                    for (index, observer) in observersToClean.enumerated() {
                        self.logDebug("🧹 cleanup(): Removing notification observer \(index + 1)/\(observersToClean.count)")
                        NotificationCenter.default.removeObserver(observer)
                        self.logDebug("🗑️ cleanup(): Notification observer \(index + 1) removed")
                    }
                    
                    self.logDebug("🧹 cleanup(): Clearing collections")
                    
                    // Limpiar las colecciones
                    self.observedItems.removeAll()
                    self.notificationObservers.removeAll()
                    
                    self.logDebug("✅ cleanup(): Coordinator cleaned up safely")
                }
            }
        }
        
        func safeCleanupPlayer(_ player: AVPlayer) {
            logDebug("🗑️ STARTING safeCleanupPlayer")
            cleanupQueue.async { [weak self] in
                self?.logDebug("🗑️ safeCleanupPlayer: In cleanup queue")
                DispatchQueue.main.async { [weak self] in
                    self?.logDebug("🗑️ safeCleanupPlayer: In main queue, about to autoreleasepool")
                    autoreleasepool {
                        self?.logDebug("🗑️ safeCleanupPlayer: Inside autoreleasepool, pausing player")
                        player.pause()
                        self?.logDebug("🗑️ safeCleanupPlayer: Player paused, replacing current item")
                        player.replaceCurrentItem(with: nil)
                        self?.logDebug("🗑️ safeCleanupPlayer: Current item replaced")
                    }
                    self?.logDebug("🗑️ safeCleanupPlayer: Exited autoreleasepool")
                    print("🗑️ Player limpiado de forma segura")
                }
            }
        }
        
        deinit {
            logDebug("🔄 deinit(): Coordinator deinitializing")
            if !isCleanedUp {
                logDebug("🔄 deinit(): Not cleaned up yet, performing emergency cleanup")
                
                // Última oportunidad de limpieza síncrona
                let itemsToClean = Array(observedItems)
                logDebug("🔄 deinit(): Emergency cleanup for \(itemsToClean.count) items")
                
                for (index, item) in itemsToClean.enumerated() {
                    logDebug("🔄 deinit(): Emergency removing observer \(index + 1)/\(itemsToClean.count)")
                    // Usar autoreleasepool para limpieza segura
                    autoreleasepool {
                        item.removeObserver(self, forKeyPath: "status")
                    }
                    logDebug("🔄 deinit(): Emergency observer \(index + 1) removed")
                }
                
                logDebug("🔄 deinit(): Emergency cleanup for \(notificationObservers.count) notification observers")
                
                for (index, observer) in notificationObservers.enumerated() {
                    logDebug("🔄 deinit(): Emergency removing notification observer \(index + 1)")
                    NotificationCenter.default.removeObserver(observer)
                    logDebug("🔄 deinit(): Emergency notification observer \(index + 1) removed")
                }
                
                logDebug("🔄 deinit(): Emergency clearing collections")
                observedItems.removeAll()
                notificationObservers.removeAll()
                logDebug("🔄 deinit(): Emergency cleanup completed")
            } else {
                logDebug("🔄 deinit(): Already cleaned up")
            }
            logDebug("🔄 deinit(): Coordinator deinitialized successfully")
        }
    }
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        
        print("🎬 Creando nuevo AVPlayerView para: \(url.lastPathComponent)")
        
        // Verificar que el archivo existe antes de intentar reproducirlo
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Error: Archivo de video no encontrado: \(url.path)")
            return playerView
        }
        
        // Crear asset y verificar que es válido
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Añadir observer a través del coordinator
        context.coordinator.addObserver(for: playerItem)
        
        let player = AVPlayer(playerItem: playerItem)
        
        playerView.player = player
        playerView.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        playerView.controlsStyle = .none
        playerView.showsFrameSteppingButtons = false
        playerView.showsSharingServiceButton = false
        playerView.showsFullScreenToggleButton = false
        
        // Configurar para que el video se reproduzca en loop
        if shouldLoop {
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                print("🔄 Video terminó, reiniciando...")
                player.seek(to: .zero)
                player.play()
            }
            context.coordinator.addNotificationObserver(observer)
        }
        
        // Silenciar el video por defecto
        player.isMuted = true
        
        // Iniciar reproducción cuando esté listo
        player.play()
        
        print("✅ AVPlayerView configurado correctamente")
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.logDebug("🔄 updateNSView(): Starting update for \(url.lastPathComponent)")
        
        // Si la URL cambió, actualizar el player
        if let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url,
           currentURL != url {
            
            context.coordinator.logDebug("🎯 updateNSView(): URL changed from \(currentURL.lastPathComponent) to \(url.lastPathComponent)")
            
            // Limpiar el player actual de forma agresiva
            if let currentPlayer = nsView.player {
                context.coordinator.logDebug("🔄 updateNSView(): Found current player, pausing")
                
                // Pausa inmediata
                currentPlayer.pause()
                context.coordinator.logDebug("🔄 updateNSView(): Current player paused")
                
                // Remover observer del item actual de forma segura
                if let currentItem = currentPlayer.currentItem {
                    context.coordinator.logDebug("🔄 updateNSView(): Found current item, removing observer")
                    context.coordinator.removeObserver(for: currentItem)
                    context.coordinator.logDebug("🔄 updateNSView(): Observer removed for current item")
                } else {
                    context.coordinator.logDebug("🔄 updateNSView(): No current item found")
                }
                
                // Limpiar player de forma segura
                context.coordinator.logDebug("🔄 updateNSView(): Starting safe cleanup of current player")
                context.coordinator.safeCleanupPlayer(currentPlayer)
                context.coordinator.logDebug("🔄 updateNSView(): Safe cleanup initiated")
            } else {
                context.coordinator.logDebug("🔄 updateNSView(): No current player found")
            }
            
            // Limpiar observers de notificaciones anteriores
            context.coordinator.logDebug("🔄 updateNSView(): Starting coordinator cleanup")
            context.coordinator.cleanup()
            context.coordinator.logDebug("🔄 updateNSView(): Coordinator cleanup initiated")
            
            // Actualizar parent reference (struct puede haber cambiado)
            context.coordinator.logDebug("🔄 updateNSView(): Updating parent reference")
            context.coordinator.parent = self
            context.coordinator.logDebug("🔄 updateNSView(): Parent reference updated")
            
            // Pequeña demora para asegurar que la limpieza termine
            context.coordinator.logDebug("🔄 updateNSView(): Scheduling delayed player creation")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                context.coordinator.logDebug("🔄 updateNSView(): In delayed execution, starting autoreleasepool")
                autoreleasepool {
                    context.coordinator.logDebug("🔄 updateNSView(): Inside autoreleasepool, creating new asset")
                    
                    // Crear nuevo asset y playerItem
                    let asset = AVURLAsset(url: self.url)
                    let playerItem = AVPlayerItem(asset: asset)
                    context.coordinator.logDebug("🔄 updateNSView(): New asset and playerItem created")
                    
                    // Añadir observer al nuevo item
                    context.coordinator.logDebug("🔄 updateNSView(): Adding observer to new item")
                    context.coordinator.addObserver(for: playerItem)
                    context.coordinator.logDebug("🔄 updateNSView(): Observer added to new item")
                    
                    context.coordinator.logDebug("🔄 updateNSView(): Creating new player")
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    nsView.player = newPlayer
                    context.coordinator.logDebug("🔄 updateNSView(): New player assigned to nsView")
                    
                    // Configurar loop para el nuevo player
                    if self.shouldLoop {
                        context.coordinator.logDebug("🔄 updateNSView(): Configuring loop for new player")
                        let observer = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: newPlayer.currentItem,
                            queue: .main
                        ) { _ in
                            context.coordinator.logDebug("🔄 updateNSView(): Video ended, restarting")
                            newPlayer.seek(to: .zero)
                            newPlayer.play()
                        }
                        context.coordinator.addNotificationObserver(observer)
                        context.coordinator.logDebug("🔄 updateNSView(): Loop configured and observer added")
                    }
                    
                    context.coordinator.logDebug("🔄 updateNSView(): Setting player properties")
                    newPlayer.isMuted = true
                    newPlayer.play()
                    context.coordinator.logDebug("✅ updateNSView(): Player updated successfully with delay")
                }
                context.coordinator.logDebug("🔄 updateNSView(): Exited autoreleasepool")
            }
        } else {
            context.coordinator.logDebug("🔄 updateNSView(): No URL change detected, skipping update")
        }
    }
    
    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.logDebug("🧹 dismantleNSView(): Starting aggressive NSView dismantling")
        
        // Cleanup inmediato en main queue
        DispatchQueue.main.async {
            coordinator.logDebug("🧹 dismantleNSView(): In main queue, starting autoreleasepool")
            autoreleasepool {
                coordinator.logDebug("🧹 dismantleNSView(): Inside autoreleasepool")
                
                if let player = nsView.player {
                    coordinator.logDebug("🧹 dismantleNSView(): Found player, pausing")
                    
                    // Pausa inmediata
                    player.pause()
                    coordinator.logDebug("🧹 dismantleNSView(): Player paused")
                    
                    // Remover observer del item actual si existe
                    if let currentItem = player.currentItem {
                        coordinator.logDebug("🧹 dismantleNSView(): Found current item, removing observer")
                        coordinator.removeObserver(for: currentItem)
                        coordinator.logDebug("🧹 dismantleNSView(): Observer removed for current item")
                    } else {
                        coordinator.logDebug("🧹 dismantleNSView(): No current item found")
                    }
                    
                    // Limpiar player de forma segura
                    coordinator.logDebug("🧹 dismantleNSView(): Starting safe player cleanup")
                    coordinator.safeCleanupPlayer(player)
                    coordinator.logDebug("🧹 dismantleNSView(): Safe player cleanup initiated")
                } else {
                    coordinator.logDebug("🧹 dismantleNSView(): No player found in nsView")
                }
                
                // Limpiar todos los observers del coordinator
                coordinator.logDebug("🧹 dismantleNSView(): Starting coordinator cleanup")
                coordinator.cleanup()
                coordinator.logDebug("🧹 dismantleNSView(): Coordinator cleanup initiated")
                
                // Limpiar el player view
                coordinator.logDebug("🧹 dismantleNSView(): Clearing nsView player")
                nsView.player = nil
                coordinator.logDebug("🧹 dismantleNSView(): nsView player cleared")
                
                // Limpiar parent reference
                coordinator.logDebug("🧹 dismantleNSView(): Clearing parent reference")
                coordinator.parent = nil
                coordinator.logDebug("🧹 dismantleNSView(): Parent reference cleared")
                
                coordinator.logDebug("✅ dismantleNSView(): NSView dismantled successfully")
            }
            coordinator.logDebug("🧹 dismantleNSView(): Exited autoreleasepool")
        }
    }
}

// Vista previa del video con controles básicos se ha movido a otro archivo
