// Unified implementation of DesktopVideoWindowMejorada
// This class replaces DesktopVideoWindow and should be used throughout the project.

import Cocoa
import CoreGraphics
import AVFoundation
import os.log
import Foundation
import AppKit

// Specific logger for memory debugging
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

// Extensions for compatibility with earlier macOS versions
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

/// Enhanced and unified desktop video window
public class DesktopVideoWindowMejorada: NSWindow {
    private var player: AVQueuePlayer?  // Changed from AVPlayer to AVQueuePlayer
    private var looper: AVPlayerLooper?  // NEW: For automatic looping
    public var playerLayer: AVPlayerLayer?
    
    /// Access to player layer for external control
    var currentPlayerLayer: AVPlayerLayer? {
        return playerLayer
    }
    
    /// Sets the opacity of the window and its video layer
    func setOpacity(_ opacity: Double) {
        // Update the layer's opacity
        playerLayer?.opacity = Float(opacity)
        
        // If we need to also update the window's opacity
        self.alphaValue = opacity
        
        // Ensure the layer is updated properly
        if let layer = self.contentView?.layer {
            layer.opacity = Float(opacity)
        }
    }

    private var videoURL: URL
    private var urlSecurityScoped: URL?
    private var playerItemStatusObserver: NSKeyValueObservation?  // PHASE 2: Only status observer kept (for error detection)
    // PHASE 2: REMOVED playerRateObserver and playerItemDidPlayToEndObserver (handled by AVPlayerLooper)
    private var isClosing: Bool = false
    private var isPlayerSetupInProgress: Bool = false
    private var isBeingTornDown: Bool = false
    private let setupLock = NSLock()
    private let cleanupLock = NSLock()
    private let setupQueue = DispatchQueue(label: "com.livewalls.window.setup", qos: .userInitiated)
    private let cleanupQueue = DispatchQueue(label: "com.livewalls.window.cleanup", qos: .userInitiated)

    // Definition of playerItem property
    private var playerItem: AVPlayerItem?
    
    // FASE 5.1: Garantizar Player Ready antes de Transición
    /// Indica si el reproductor está completamente configurado y listo para reproducir
    private(set) var isPlayerReady: Bool = false
    
    /// Indica si el reproductor debe iniciar en pausa para pre-carga
    private let startPaused: Bool
    
    /// Indica si hay una activación de reproducción pendiente
    private var activationPending: Bool = false

    /// Initializes the window with the screen and accessible video URL (active security-scoped).
    /// IMPORTANT: The window does NOT take ownership of security-scoped access.
    /// WallpaperManager is responsible for managing the access lifecycle.
    /// - Parameters:
    ///   - screen: Target screen.
    ///   - videoURL: Video URL with active security-scoped access.
    ///   - startPaused: Si es true, el reproductor se configura pero no inicia reproducción automáticamente
    ///   - staticImageURL: URL opcional de imagen estática para mostrar como placeholder durante pre-carga
    ///   - preloadedAsset: Optional preloaded AVAsset to skip asset loading (for fast window creation)
    public init(screen: NSScreen, videoURL: URL, startPaused: Bool = false, staticImageURL: URL? = nil, preloadedAsset: AVURLAsset? = nil) {
        self.videoURL = videoURL
        self.urlSecurityScoped = nil
        self.startPaused = startPaused
        let contentRect = screen.frame
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setupWindow(for: screen)
        
        // Si hay imagen estática, mostrarla como placeholder
        if let staticImageURL = staticImageURL {
            showStaticPlaceholder(from: staticImageURL)
        }
        
        Task {
            await setupPlayer(with: videoURL, preloadedAsset: preloadedAsset)
        }
    }

    private func setupWindow(for screen: NSScreen) {
        memoryLogger.info("🖥️ Configuring window for screen: \(screen.localizedName)")
        // Keep above the system wallpaper but below desktop icons
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.backgroundColor = NSColor.clear
        self.setFrame(screen.frame, display: true)
        self.styleMask = [.borderless, .fullSizeContentView]
        
        // Additional optimizations
        self.acceptsMouseMovedEvents = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false // Changed to false to control lifecycle
        self.hidesOnDeactivate = false
        self.isExcludedFromWindowsMenu = true
        self.showsResizeIndicator = false
        self.showsToolbarButton = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.toolbar = nil
    }

    private func setupPlayer(with url: URL, preloadedAsset: AVURLAsset? = nil) async {
        await withCheckedContinuation { continuation in
            setupLock.lock()
            guard !isPlayerSetupInProgress, !isBeingTornDown else {
                setupLock.unlock()
                memoryLogger.warning("⚠️ Player setup cancelled - already in progress or being destroyed")
                continuation.resume()
                return
            }
            isPlayerSetupInProgress = true
            setupLock.unlock()

            // Use preloaded asset if available, otherwise create new one with optimized options
            let asset: AVURLAsset
            if let preloadedAsset = preloadedAsset {
                asset = preloadedAsset
                memoryLogger.info("🚀 Using PRELOADED AVAsset - fast path")
            } else {
                // Configure AVURLAsset with options to minimize internal errors
                let assetOptions: [String: Any] = [
                    AVURLAssetPreferPreciseDurationAndTimingKey: true,
                    // Reduce pixel format negotiation warnings
                    "AVURLAssetHTTPHeaderFieldsKey": [:] as [String: String]
                ]
                asset = AVURLAsset(url: url, options: assetOptions)
            }
            
            Task {
                do {
                    let (isPlayable, _) = try await asset.load(.isPlayable, .tracks)
                    
                    guard isPlayable else {
                        throw NSError(domain: "com.livewalls.error", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video is not playable"])
                    }

                    await MainActor.run {
                        setupLock.lock()
                        defer { 
                            setupLock.unlock()
                            self.isPlayerSetupInProgress = false
                        }
                        
                        guard !isBeingTornDown else {
                            memoryLogger.warning("⚠️ Setup cancelled: window being destroyed")
                            continuation.resume()
                            return
                        }

                        // PHASE 2: Create AVQueuePlayer with AVPlayerLooper for automatic looping
                        let newPlayerItem = AVPlayerItem(asset: asset)
                        
                        // Configure AVPlayerItem to reduce internal errors
                        newPlayerItem.preferredForwardBufferDuration = 2.0 // Reduce buffer to minimize overhead
                        newPlayerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
                        
                        let newQueuePlayer = AVQueuePlayer(playerItem: newPlayerItem)
                        
                        // Optimized configuration for background playback
                        newQueuePlayer.volume = 0.0
                        newQueuePlayer.automaticallyWaitsToMinimizeStalling = false
                        newQueuePlayer.isMuted = true
                        
                        // PHASE 2: Set up AVPlayerLooper for seamless looping (replaces manual seek)
                        let newLooper = AVPlayerLooper(player: newQueuePlayer, templateItem: newPlayerItem)
                        
                        // Configure playerLayer with optimizations
                        let newPlayerLayer = AVPlayerLayer(player: newQueuePlayer)
                        newPlayerLayer.videoGravity = .resizeAspectFill
                        newPlayerLayer.frame = self.contentView?.bounds ?? .zero
                        newPlayerLayer.isOpaque = true
                        newPlayerLayer.backgroundColor = CGColor.black
                        newPlayerLayer.masksToBounds = true
                        // Use asynchronous drawing for smooth video playback
                        // Note: shouldRasterize is NOT used as it's for static content and conflicts with video rendering
                        newPlayerLayer.drawsAsynchronously = true

                        // Add layer to view
                        if let contentView = self.contentView {
                            if contentView.layer == nil {
                                contentView.wantsLayer = true
                            }
                            contentView.layer?.addSublayer(newPlayerLayer)
                        }

                        // PHASE 2: Only keep status observer for error detection (no manual looping observers)
                        // Capture strategy: newQueuePlayer captured strongly to keep player alive until observer removed.
                        // Weak self ensures observer is cleaned when window deallocates.
                        self.playerItemStatusObserver = newPlayerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                            guard let self = self else { return }
                            switch item.status {
                            case .readyToPlay:
                                memoryLogger.info("✅ PlayerItem ready to play")
                                // Solo auto-play si NO está en modo pausado
                                if !self.startPaused {
                                    newQueuePlayer.play()
                                }
                            case .failed:
                                memoryLogger.error("❌ PlayerItem failed: \(item.error?.localizedDescription ?? "Unknown error")")
                                self.cleanupPlayer()
                            case .unknown:
                                memoryLogger.warning("⚠️ PlayerItem in unknown state")
                            @unknown default:
                                memoryLogger.warning("⚠️ PlayerItem in unhandled state")
                            }
                        }

                        // Save references
                        self.player = newQueuePlayer
                        self.looper = newLooper  // PHASE 2: Save looper reference
                        self.playerItem = newPlayerItem
                        self.playerLayer = newPlayerLayer

                        // Marcar como listo antes de reproducir
                        self.isPlayerReady = true
                        
                        // Start playback solo si NO está en modo pausado
                        if !self.startPaused {
                            newQueuePlayer.play()
                            memoryLogger.info("✅ AVQueuePlayer configured with AVPlayerLooper and playing: \(url.lastPathComponent)")
                        } else {
                            // En modo pausado, mantener pausa pero marcar como listo
                            newQueuePlayer.pause()
                            memoryLogger.info("✅ AVQueuePlayer configured with AVPlayerLooper (paused, ready for activation): \(url.lastPathComponent)")
                        }
                        
                        continuation.resume()
                    }
                } catch {
                    memoryLogger.error("❌ Error configuring player: \(error.localizedDescription)")
                    await MainActor.run {
                        self.setupLock.lock()
                        self.isPlayerSetupInProgress = false
                        self.setupLock.unlock()
                        
                        self.cleanupPlayer { [weak self] in
                            self?.showErrorInWindow("Error loading video: \(error.localizedDescription)")
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }

    // PHASE 2: setupObservers() removed - AVPlayerLooper handles automatic looping
    // Manual observers (.didPlayToEndTime, rate observer, periodic observer) are no longer needed
    
    // MARK: - FASE 5.1: Activación de Reproducción
    
    /// Activa la reproducción del video pre-cargado
    /// Este método debe llamarse después de que la transición visual haya finalizado
    /// - Returns: true si la activación fue exitosa, false si el player no está listo
    @discardableResult
    public func activatePlayback() -> Bool {
        guard isPlayerReady else {
            memoryLogger.warning("⚠️ Intento de activar playback pero player no está listo")
            return false
        }
        
        guard let player = player else {
            memoryLogger.error("❌ Intento de activar playback pero player es nil")
            return false
        }
        
        activationPending = true
        
        // Remover placeholder estático si existe
        removeStaticPlaceholder()
        
        // Iniciar reproducción
        player.play()
        activationPending = false
        
        memoryLogger.info("✅ Reproducción activada exitosamente")
        return true
    }
    
    /// Muestra una imagen estática como placeholder mientras se carga el video
    private func showStaticPlaceholder(from url: URL) {
        guard let contentView = self.contentView else { return }
        
        // Cargar imagen en background thread para no bloquear main thread (FASE 5.2)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            
            guard let imageData = try? Data(contentsOf: url),
                  let nsImage = NSImage(data: imageData) else {
                memoryLogger.warning("⚠️ No se pudo cargar imagen placeholder desde: \(url.path)")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                guard let contentView = self?.contentView else { return }
                
                // Crear y configurar image view
                let imageView = NSImageView(frame: contentView.bounds)
                imageView.image = nsImage
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.autoresizingMask = [.width, .height]
                imageView.identifier = NSUserInterfaceItemIdentifier("staticPlaceholder")
                
                contentView.addSubview(imageView)
                memoryLogger.info("📷 Placeholder estático mostrado")
            }
        }
    }
    
    /// Remueve el placeholder estático si existe
    private func removeStaticPlaceholder() {
        guard let contentView = self.contentView else { return }
        
        for subview in contentView.subviews {
            if subview.identifier?.rawValue == "staticPlaceholder" {
                subview.removeFromSuperview()
                memoryLogger.info("🗑️ Placeholder estático removido")
            }
        }
    }

    /// Safely cleans up all player resources
    /// Based on Swift Foundation best practices for concurrency
    private func cleanupPlayer(completion: @escaping () -> Void = {}) {
        // Use defer to guarantee lock unlock
        cleanupLock.lock()
        defer { cleanupLock.unlock() }
        
        guard !isBeingTornDown else {
            completion()
            return
        }
        isBeingTornDown = true
        
        // PHASE 2: Capture looper reference for cleanup
        let looperToCleanup = self.looper
        
        // Capture references BEFORE cleanup for thread safety
        let components = (
            player: self.player,
            playerLayer: self.playerLayer,
            playerItem: self.playerItem,
            statusObserver: self.playerItemStatusObserver
            // PHASE 2: Removed rateObserver and endObserver (handled by AVPlayerLooper)
        )
        
        // Clean references atomically
        self.player = nil
        self.playerItem = nil
        self.playerLayer = nil
        self.playerItemStatusObserver = nil
        self.looper = nil  // PHASE 2: Clean looper reference
        
        // Perform asynchronous cleanup to avoid deadlocks
        let performCleanupAsync = {
            // PHASE 2: Disable looper before cleanup
            looperToCleanup?.disableLooping()
            
            // Clean observers FIRST
            components.statusObserver?.invalidate()
            // PHASE 2: Removed manual observer cleanup (no rate or end observers)
            
            // Stop player BEFORE removing layer
            components.player?.pause()
            components.player?.replaceCurrentItem(with: nil)
            
            // Remove layer from superlayer
            components.playerLayer?.removeFromSuperlayer()
            
            memoryLogger.info("🧹 Player cleaned successfully (AVQueuePlayer + AVPlayerLooper)")
            
            // Execute completion on main thread
            DispatchQueue.main.async {
                completion()
            }
        }
        
        // Execute cleanup in thread-safe manner
        if Thread.isMainThread {
            // If on main thread, execute asynchronously to avoid blocking
            DispatchQueue.main.async(execute: performCleanupAsync)
        } else {
            // If on another thread, execute directly
            performCleanupAsync()
        }
    }

    /// Closes the window and releases associated resources.
    public func close(completion: @escaping () -> Void = {}) {
        // Avoid multiple closures
        if isClosing { 
            completion()
            return 
        }
        isClosing = true
        
        memoryLogger.info("🚪 Closing video window...")
        
        // Clean resources before closing window
        cleanupPlayer { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            
            // Close window on main thread
            DispatchQueue.main.async { [weak self] in
                self?.performClose()
                completion()
            }
        }
    }
    
    /// Private method to close the window
    private func performClose() {
        super.close()
    }
    
    /// Override of original close() method to maintain compatibility
    public override func close() {
        close(completion: {})
    }

    deinit {
        memoryLogger.info("🧹 Deinitializing video window")
        // Ensure final cleanup if not done before
        if !isBeingTornDown {
            cleanupPlayer()
        }
    }

    // MARK: - Public API para acceso al reproductor
    
    /// Gets the current video playback time
    /// - Returns: Current CMTime of the player or nil if no active player
    public func getCurrentTime() -> CMTime? {
        return player?.currentTime()
    }
    
     /// Gets the current player state
     /// - Returns: Current playback rate (0.0 = paused, 1.0 = normal playback)
     public func getPlaybackRate() -> Float? {
         return player?.rate
     }
     
     /// PHASE 6: Gets the current time control status of the player
     /// Used for accurate stall detection (paused, waitingToPlayAtSpecifiedRate, playing)
     /// - Returns: Current timeControlStatus or nil if player doesn't exist
     public func getTimeControlStatus() -> AVPlayer.TimeControlStatus? {
         return player?.timeControlStatus
     }
     
     /// Gets the total duration of the current video
     /// - Returns: CMTime with total duration or nil if not available
     public func getTotalDuration() -> CMTime? {
         return player?.currentItem?.duration
     }

    /// Forces playback on the underlying player if available
    public func forcePlay() {
        player?.play()
    }
    
    /// Pauses playback and keeps the current frame visible (alias)
    public func forcePause() {
        pausePlayback()
    }
    
    /// Pauses playback while keeping the current frame visible
    /// Uses rate=0 instead of pause() to ensure frame stays rendered
    public func pausePlayback() {
        guard let player = player else { return }
        
        // Use rate = 0 instead of pause() to keep frame visible
        player.rate = 0.0
        
        // Force layer to stay visible and rendered
        playerLayer?.isHidden = false
        
        memoryLogger.debug("⏸️ Playback paused at \(String(format: "%.2f", player.currentTime().seconds))s - frame should remain visible")
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
         memoryLogger.warning("⚠️ Showing error in window: \(message)")
     }
     
     // MARK: - Phase 3: Window Reuse and Health Check
     
     /// Checks if the window is healthy and can be reused without recreation
     /// - Returns: true if window is valid and playback is functional, false otherwise
     public func isHealthy() -> Bool {
         // Check if window is being torn down
         if isBeingTornDown {
             memoryLogger.debug("❌ Window unhealthy: Being torn down")
             return false
         }
         
         // Check if player exists
         guard let player = player else {
             memoryLogger.debug("❌ Window unhealthy: No player")
             return false
         }
         
         // Check if current item exists
         guard let currentItem = player.currentItem else {
             memoryLogger.debug("❌ Window unhealthy: No current item")
             return false
         }
         
         // Check if player item status indicates failure
         if currentItem.status == .failed {
             memoryLogger.debug("❌ Window unhealthy: Player item failed")
             return false
         }
         
         // Check if content view exists
         if contentView == nil {
             memoryLogger.debug("❌ Window unhealthy: No content view")
             return false
         }
         
         memoryLogger.debug("✅ Window healthy: Ready for reuse")
         return true
     }
     
      /// Updates window properties for a Space change without full recreation
      /// This method ensures the window remains visible and playback continues on the new Space
      public func updateForSpace() {
          memoryLogger.debug("🔄 Updating window for Space change")
          
          // PHASE 3: Validate resource access before operations
          // Check that player and layer are still accessible
          guard let player = player else {
              memoryLogger.warning("⚠️ Player is nil - may indicate resource cleanup issue")
              // Window state is corrupted, recovery would require WallpaperManager intervention
              return
          }
          
          if playerLayer == nil {
              memoryLogger.warning("⚠️ Player layer is nil - may indicate render resource issue")
          }
          
          // Ensure window is on correct Space
          self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
          
          // PHASE 5: Use consistent window level
          // Keep same level as setupWindow() - never change window level
          // Use kCGDesktopIconWindowLevel - 1 (same as initial setup)
          self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
          self.orderBack(nil)
          
          // PHASE 3: Resume playback with validation
          // Resume playback if paused (and not paused by user)
          if let queuePlayer = player as? AVQueuePlayer {
              if queuePlayer.rate == 0 {
                  memoryLogger.debug("▶️ Resuming playback after Space change")
                  queuePlayer.play()
              } else {
                  memoryLogger.debug("✅ Playback already running after Space change")
              }
          } else {
              memoryLogger.warning("⚠️ Player not available as AVQueuePlayer for resume")
          }
          
          memoryLogger.debug("✅ Window updated for Space change")
      }
}

