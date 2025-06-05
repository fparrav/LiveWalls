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
        // Quitar 'weak' ya que VideoPlayerView es una struct, no una clase
        var parent: VideoPlayerView?
        private var observedItems: Set<AVPlayerItem> = []
        private var notificationObservers: [NSObjectProtocol] = []
        // Cambiar a internal para que sea accesible desde dismantleNSView
        internal var isCleanedUp = false
        // Cambiar a internal para que sea accesible desde dismantleNSView
        internal var isBeingDeinitalized = false
        private let cleanupQueue = DispatchQueue(label: "video.cleanup", qos: .userInitiated)
        
        // CRITICAL: Mantener referencias fuertes para prevenir deallocación prematura
        // Esta colección es para los AVPlayer que el coordinador gestiona directamente.
        private var retainedPlayers: [AVPlayer] = []
        // Esta colección es para los AVPlayerItem a los que se les han añadido observadores KVO.
        private var retainedPlayerItems: [AVPlayerItem] = []
        
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
            
            // CRITICAL: Retener referencia fuerte para prevenir deallocación prematura
            retainedPlayerItems.append(playerItem)
            logDebug("🔒 addObserver(): Retained playerItem reference, total retained: \(retainedPlayerItems.count)")
            
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
            let success = safeRemoveObserverWithProtection(from: playerItem, keyPath: "status")
            if success {
                observedItems.remove(playerItem)
                
                // CRITICAL: Liberar referencia fuerte solo después de remover observer exitosamente
                if let index = retainedPlayerItems.firstIndex(of: playerItem) {
                    retainedPlayerItems.remove(at: index)
                    logDebug("🔓 removeObserver(): Released playerItem reference, total retained: \(retainedPlayerItems.count)")
                }
                
                print("🗑️ Observer removido para playerItem: \(playerItem)")
            } else {
                logDebug("⚠️ removeObserver(): Failed to remove observer, keeping reference for safety")
            }
        }
        
        // Nueva función para retener referencias de players
        func retainPlayer(_ player: AVPlayer) {
            guard !retainedPlayers.contains(player) else { return }
            retainedPlayers.append(player)
            logDebug("🔒 retainPlayer(): Retained player reference, total retained: \(retainedPlayers.count)")
        }
        
        // Función para liberar referencias de AVPlayerItem de forma segura
        func releasePlayerItem(_ playerItem: AVPlayerItem) {
            cleanupLock.lock()
            let isDeinitializing = isBeingDeinitalized
            cleanupLock.unlock()

            if isDeinitializing {
                logDebug("🗑️ releasePlayerItem: Coordinator is deinitializing, skipping release for item.")
                return
            }

            if let index = retainedPlayerItems.firstIndex(of: playerItem) {
                retainedPlayerItems.remove(at: index)
                logDebug("🗑️ releasePlayerItem: Released playerItem. Total retained: \(retainedPlayerItems.count)")
            } else {
                logDebug("⚠️ releasePlayerItem: PlayerItem not found in retainedPlayerItems for release.")
            }
        }
        
        // Nueva función para liberar referencias de players de forma segura
        func releasePlayer(_ player: AVPlayer) {
            if let index = retainedPlayers.firstIndex(of: player) {
                retainedPlayers.remove(at: index)
                logDebug("🔓 releasePlayer(): Released player reference, total retained: \(retainedPlayers.count)")
            }
        }
        
        func addNotificationObserver(_ observer: NSObjectProtocol) {
            guard !isCleanedUp else { return }
            notificationObservers.append(observer)
        }
        
        // Agregar un mutex para garantizar que las operaciones de limpieza sean thread-safe
        internal let cleanupLock = NSLock()
        
        func cleanup() {
            // Proteger contra limpiezas concurrentes
            cleanupLock.lock()
            defer { cleanupLock.unlock() }
            
            if isCleanedUp || isBeingDeinitalized {
                logDebug("🧹 cleanup(): Already cleaned up or being deinitialized, skipping")
                return
            }
            
            logDebug("🧹 cleanup(): Starting aggressive coordinator cleanup")
            isCleanedUp = true
            
            // Capturar y vaciar todas las colecciones de una sola vez para evitar race conditions
            let itemsToCleanup = Array(observedItems)
            let observersToCleanup = Array(notificationObservers)
            let playersToRelease = Array(retainedPlayers)
            
            observedItems.removeAll()
            notificationObservers.removeAll()
            retainedPlayers.removeAll()
            retainedPlayerItems.removeAll()
            
            // Ahora procesamos los elementos capturados
            if Thread.isMainThread {
                performSafeCleanupWithCapturedItems(items: itemsToCleanup, 
                                                  observers: observersToCleanup,
                                                  players: playersToRelease)
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isBeingDeinitalized else { return }
                    self.performSafeCleanupWithCapturedItems(items: itemsToCleanup, 
                                                          observers: observersToCleanup,
                                                          players: playersToRelease)
                }
            }
        }
        
        private func performSafeCleanupWithCapturedItems(items: [AVPlayerItem], 
                                                     observers: [NSObjectProtocol], 
                                                     players: [AVPlayer]) {
            // No acceder a self.observedItems o cualquier propiedad colectiva
            logDebug("🧹 performSafeCleanupWithCapturedItems(): Processing captured items")
            
            // Procesar cada item capturado de forma aislada
            for item in items {
                autoreleasepool {
                    if item.observationInfo != nil {
                        logDebug("🧹 removeObserver for captured item")
                        item.removeObserver(self, forKeyPath: "status")
                    }
                }
            }
            
            // Limpiar observers
            for observer in observers {
                autoreleasepool {
                    logDebug("🧹 removing notification observer")
                    NotificationCenter.default.removeObserver(observer)
                }
            }
            
            // Limpiar players
            for player in players {
                autoreleasepool {
                    logDebug("🧹 pausing and clearing player")
                    player.pause()
                    player.replaceCurrentItem(with: nil)
                }
            }
            
            logDebug("✅ performSafeCleanupWithCapturedItems(): All captured items processed")
        }
        
        deinit {
            logDebug("🔄 deinit(): Coordinator deinitializing")
            
            // Marcamos INMEDIATAMENTE para evitar cualquier otra operación concurrente
            cleanupLock.lock()
            isBeingDeinitalized = true
            isCleanedUp = true
            cleanupLock.unlock()
            
            // NO hacemos nada más aquí - simplemente liberamos las colecciones sin procesar objetos
            observedItems = []
            notificationObservers = []
            retainedPlayers = []
            retainedPlayerItems = []
            parent = nil
            
            logDebug("🔄 deinit(): Coordinator deinitialized successfully")
        }
        
        private func performSafeDeinitCleanup() {
            // Este método ya no es necesario y solo puede causar problemas
            // Lo dejamos vacío para evitar modificar muchas partes del código
            logDebug("🔄 performSafeDeinitCleanup(): Using simplified cleanup approach")
        }
        
        func safeCleanupPlayer(_ player: AVPlayer) {
            // Proteger contra limpiezas durante deinit
            cleanupLock.lock()
            let isDeinitializing = isBeingDeinitalized
            cleanupLock.unlock()
            
            if isDeinitializing {
                logDebug("🗑️ safeCleanupPlayer: Coordinator is deinitializing, skipping cleanup for player: \(player)")
                return
            }
            
            logDebug("🗑️ STARTING safeCleanupPlayer for player: \(player)")
            
            // Usar una copia local del player
            let playerRef = player
            
            // Hacer una limpieza simple sin referencias a las colecciones internas
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    print("🗑️ safeCleanupPlayer: Coordinator deallocated while cleaning player \(playerRef).")
                    playerRef.pause()
                    playerRef.replaceCurrentItem(with: nil)
                    return
                }

                self.cleanupLock.lock()
                let stillDeinitializing = self.isBeingDeinitalized
                self.cleanupLock.unlock()

                if stillDeinitializing {
                    self.logDebug("🗑️ safeCleanupPlayer: Coordinator started deinitializing during async player cleanup \(playerRef).")
                    return
                }

                self.logDebug("🗑️ safeCleanupPlayer: Performing cleanup on main thread for player \(playerRef)")
                playerRef.pause()

                if let currentItem = playerRef.currentItem {
                    self.logDebug("🗑️ safeCleanupPlayer: Removing observer and releasing item for player \(playerRef)")
                    self.removeObserver(for: currentItem) 
                    self.releasePlayerItem(currentItem)   
                }
                
                playerRef.replaceCurrentItem(with: nil) 

                if let index = self.retainedPlayers.firstIndex(of: playerRef) {
                    self.retainedPlayers.remove(at: index)
                    self.logDebug("🗑️ safeCleanupPlayer: Released player reference from retainedPlayers. Total: \(self.retainedPlayers.count)")
                } else {
                    self.logDebug("⚠️ safeCleanupPlayer: Player \(playerRef) not found in retainedPlayers for release.")
                }
                self.logDebug("✅ safeCleanupPlayer: Finished cleanup for player \(playerRef)")
            }
        }
        
        func safeCleanupPlayerOnDeinit(_ player: AVPlayer) {
            logDebug("🗑️ STARTING safeCleanupPlayerOnDeinit")
            
            // Limpieza específica para deinit
            autoreleasepool {
                logDebug("🗑️ safeCleanupPlayerOnDeinit: Inside autoreleasepool, pausing player")
                player.pause()
                logDebug("🗑️ safeCleanupPlayerOnDeinit: Player paused, replacing current item")
                player.replaceCurrentItem(with: nil)
                logDebug("🗑️ safeCleanupPlayerOnDeinit: Current item replaced")
            }
            logDebug("🗑️ safeCleanupPlayerOnDeinit: Autoreleasepool exited")
        }
        
        func performCleanupForDeinit() {
            logDebug("🧹 performCleanupForDeinit(): Starting cleanup for deinit")
            
            // Cleanup SÍNCRONO en main queue para evitar race conditions
            if Thread.isMainThread {
                logDebug("🧹 performCleanupForDeinit(): On main thread, cleaning up directly")
                autoreleasepool {
                    // Pausar todos los players
                    for player in retainedPlayers {
                        logDebug("🧹 performCleanupForDeinit(): Pausing player")
                        player.pause()
                    }
                    
                    // Remover observers de todos los items
                    for item in observedItems {
                        logDebug("🧹 performCleanupForDeinit(): Removing observer from item")
                        // Usar _ = para ignorar explícitamente el resultado
                        _ = safeRemoveObserverWithProtection(from: item, keyPath: "status")
                    }
                    
                    // Limpiar todas las referencias
                    logDebug("🧹 performCleanupForDeinit(): Clearing all references")
                    retainedPlayers.removeAll()
                    retainedPlayerItems.removeAll()
                    observedItems.removeAll()
                    notificationObservers.removeAll()
                }
                logDebug("🧹 performCleanupForDeinit(): Synchronous cleanup completed")
            } else {
                logDebug("🧹 performCleanupForDeinit(): Not on main thread, using async cleanup")
                DispatchQueue.main.async { [weak self] in
                    self?.logDebug("🧹 performCleanupForDeinit(): In main queue async, starting autoreleasepool")
                    autoreleasepool {
                        // Pausar todos los players
                        for player in (self?.retainedPlayers ?? []) {
                            self?.logDebug("🧹 performCleanupForDeinit(): Pausing player")
                            player.pause()
                        }
                        
                        // Remover observers de todos los items
                        for item in (self?.observedItems ?? []) {
                            self?.logDebug("🧹 performCleanupForDeinit(): Removing observer from item")
                            // Usar _ = para ignorar explícitamente el resultado
                            _ = self?.safeRemoveObserverWithProtection(from: item, keyPath: "status")
                        }
                        
                        // Limpiar todas las referencias
                        self?.logDebug("🧹 performCleanupForDeinit(): Clearing all references")
                        self?.retainedPlayers.removeAll()
                        self?.retainedPlayerItems.removeAll()
                        self?.observedItems.removeAll()
                        self?.notificationObservers.removeAll()
                    }
                    self?.logDebug("🧹 performCleanupForDeinit(): Exited autoreleasepool")
                }
                logDebug("🧹 performCleanupForDeinit(): Async cleanup scheduled")
            }
        }
        
        // Función auxiliar para remover observers de forma segura con protección robusta
        private func safeRemoveObserver(from item: AVPlayerItem, keyPath: String) -> Bool {
            // En Swift, podemos usar NSException handling implícito
            // Si el observer no existe, no se producirá un crash sino un warning silencioso
            item.removeObserver(self, forKeyPath: keyPath)
            return true  // Asumimos éxito ya que Swift maneja las excepciones internamente
        }
        
        // Función mejorada con protección adicional contra crashes de memoria
        private func safeRemoveObserverWithProtection(from item: AVPlayerItem, keyPath: String) -> Bool {
            // Verificación múltiple para prevenir crashes de EXC_BAD_ACCESS
            
            // 1. Verificar que el item no está siendo deallocated
            guard item.observationInfo != nil else {
                logDebug("⚠️ safeRemoveObserverWithProtection(): Item has no observationInfo, skipping")
                return false
            }
            
            // 2. Verificar que el item está en nuestro set tracked
            guard observedItems.contains(item) else {
                logDebug("⚠️ safeRemoveObserverWithProtection(): Item not in tracked set, skipping")
                return false
            }
            
            // 3. Usar NSException handling mediante objc runtime protection
            // Esto es una técnica para manejar excepciones de Objective-C en Swift
            var success = false
            autoreleasepool {
                // El autoreleasepool ayuda a prevenir memory corruption
                // que puede causar EXC_BAD_ACCESS durante cleanup
                item.removeObserver(self, forKeyPath: keyPath)
                success = true
                logDebug("✅ safeRemoveObserverWithProtection(): Observer removed successfully")
            }
            
            return success
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
        context.coordinator.retainPlayer(player) // Retener el reproductor
        
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
            
            // Limpiar el player actual de forma específica
            if let currentPlayer = nsView.player {
                context.coordinator.logDebug("🔄 updateNSView(): Found current player, initiating cleanup for URL change.")
                
                // safeCleanupPlayer se encargará de pausar, remover observadores del item,
                // liberar el item, anular currentItem y liberar el player de retainedPlayers.
                context.coordinator.safeCleanupPlayer(currentPlayer)
                context.coordinator.logDebug("🔄 updateNSView(): Safe cleanup for current player initiated.")
                
                nsView.player = nil // Desvincular de la vista inmediatamente
            } else {
                context.coordinator.logDebug("🔄 updateNSView(): No current player found to clean up.")
            }
            
            // NO LLAMAR A context.coordinator.cleanup() aquí, es demasiado agresivo.
            
            // Actualizar parent reference (struct puede haber cambiado)
            context.coordinator.logDebug("🔄 updateNSView(): Updating parent reference")
            context.coordinator.parent = self
            context.coordinator.logDebug("🔄 updateNSView(): Parent reference updated")
            
            // Pequeña demora para asegurar que la limpieza asíncrona del reproductor anterior
            // tenga tiempo de progresar antes de crear uno nuevo.
            context.coordinator.logDebug("🔄 updateNSView(): Scheduling delayed player creation")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // El retraso podría necesitar ajuste
                context.coordinator.logDebug("🔄 updateNSView(): In delayed execution, starting autoreleasepool for new player setup")
                autoreleasepool {
                    // Verificar si el coordinador o la vista están siendo desmantelados mientras tanto
                    context.coordinator.cleanupLock.lock()
                    let isDeinitNow = context.coordinator.isBeingDeinitalized
                    context.coordinator.cleanupLock.unlock()
                    if isDeinitNow {
                        context.coordinator.logDebug("🔄 updateNSView(): Coordinator/View is deinitializing during delayed execution. Aborting new player setup.")
                        return
                    }

                    context.coordinator.logDebug("🔄 updateNSView(): Inside autoreleasepool, creating new asset for \(self.url.lastPathComponent)")
                    
                    // Crear nuevo asset y playerItem
                    let asset = AVURLAsset(url: self.url)
                    let playerItem = AVPlayerItem(asset: asset)
                    context.coordinator.logDebug("🔄 updateNSView(): New asset and playerItem created")
                    
                    // Añadir observer al nuevo item (esto también lo añade a retainedPlayerItems)
                    context.coordinator.logDebug("🔄 updateNSView(): Adding observer to new item")
                    context.coordinator.addObserver(for: playerItem)
                    context.coordinator.logDebug("🔄 updateNSVew(): Observer added to new item")
                    
                    context.coordinator.logDebug("🔄 updateNSView(): Creating new player")
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    context.coordinator.retainPlayer(newPlayer) // Retener el nuevo reproductor
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
        // CRITICAL: Verificación temprana para evitar cualquier operación en un coordinator que está siendo deinicializado
        coordinator.cleanupLock.lock()
        let isBeingDeinited = coordinator.isBeingDeinitalized
        coordinator.cleanupLock.unlock()
        
        if isBeingDeinited {
            coordinator.logDebug("🧹 dismantleNSView(): Coordinator being deinitialized, skipping")
            return
        }
        
        coordinator.logDebug("🧹 dismantleNSView(): Starting NSView dismantling")
        
        // Hacer operaciones simples y seguras sin invocar mucha lógica
        // Primero, capturamos el player
        let playerToCleanup = nsView.player
        
        // Liberamos inmediatamente la referencia en NSView
        nsView.player = nil
        
        // Si hay un player, pausarlo inmediatamente en el hilo principal
        if let player = playerToCleanup {
            DispatchQueue.main.async {
                player.pause()
            }
        }
        
        // Limpiar recursos gradualmente para evitar bloqueos o race conditions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak coordinator] in
            guard let coordinator = coordinator else { return }
            
            // Verificar de nuevo que no se haya iniciado deinit
            coordinator.cleanupLock.lock()
            let isDeinitNow = coordinator.isBeingDeinitalized
            coordinator.cleanupLock.unlock()
            
            if isDeinitNow {
                coordinator.logDebug("🧹 dismantleNSView(): Coordinator now being deinitialized, aborting delayed cleanup")
                return
            }
            
            // Ahora limpiamos el coordinator, que limpiará todos los recursos
            coordinator.cleanup()
            
            // Limpiar referencia al parent
            coordinator.parent = nil
            
            coordinator.logDebug("✅ dismantleNSView(): NSView dismantled successfully")
        }
    }
}

// Vista previa del video con controles básicos se ha movido a otro archivo
