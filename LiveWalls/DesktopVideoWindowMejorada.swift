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
    private var player: AVPlayer?
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

    // Definition of playerItem property
    private var playerItem: AVPlayerItem?

    /// Initializes the window with the screen and accessible video URL (active security-scoped).
    /// IMPORTANT: The window does NOT take ownership of security-scoped access.
    /// WallpaperManager is responsible for managing the access lifecycle.
    /// - Parameters:
    ///   - screen: Target screen.
    ///   - videoURL: Video URL with active security-scoped access.
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
        memoryLogger.info("🖥️ Configuring window for screen: \(screen.localizedName)")
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
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

    private func setupPlayer(with url: URL) async {
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

            let asset = AVURLAsset(url: url)
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

                        // Create components in specific order
                        let newPlayerItem = AVPlayerItem(asset: asset)
                        let newPlayer = AVPlayer(playerItem: newPlayerItem)
                        
                        // Optimized configuration for background playback
                        newPlayer.actionAtItemEnd = .none
                        newPlayer.volume = 0.0
                        newPlayer.automaticallyWaitsToMinimizeStalling = false
                        newPlayer.isMuted = true
                        newPlayer.rate = 1.0 // Ensure rate is 1.0
                        
                        // Configure playerLayer with optimizations
                        let newPlayerLayer = AVPlayerLayer(player: newPlayer)
                        newPlayerLayer.videoGravity = .resizeAspectFill
                        newPlayerLayer.frame = self.contentView?.bounds ?? .zero
                        newPlayerLayer.isOpaque = true
                        newPlayerLayer.backgroundColor = CGColor.black
                        newPlayerLayer.masksToBounds = true
                        newPlayerLayer.shouldRasterize = true // Optimize rendering
                        newPlayerLayer.rasterizationScale = NSScreen.main?.backingScaleFactor ?? 1.0
                        newPlayerLayer.drawsAsynchronously = true // Asynchronous rendering

                        // Add layer to view
                        if let contentView = self.contentView {
                            if contentView.layer == nil {
                                contentView.wantsLayer = true
                            }
                            contentView.layer?.addSublayer(newPlayerLayer)
                        }

                        // Configure observers
                        setupObservers(player: newPlayer, playerItem: newPlayerItem)

                        // Save references
                        self.player = newPlayer
                        self.playerItem = newPlayerItem
                        self.playerLayer = newPlayerLayer

                        // Start playback
                        newPlayer.play()
                        
                        memoryLogger.info("✅ Player configured successfully for: \(url.lastPathComponent)")
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

    private func setupObservers(player: AVPlayer, playerItem: AVPlayerItem) {
        // Observe playerItem status
        playerItemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            switch item.status {
            case .readyToPlay:
                memoryLogger.info("✅ PlayerItem ready to play")
                player.play()
            case .failed:
                memoryLogger.error("❌ PlayerItem failed: \(item.error?.localizedDescription ?? "Unknown error")")
                self.cleanupPlayer()
            case .unknown:
                memoryLogger.warning("⚠️ PlayerItem in unknown state")
            @unknown default:
                memoryLogger.warning("⚠️ PlayerItem in unhandled state")
            }
        }

        // Observe playback rate
        playerRateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            if player.rate == 0 && !self.isClosing {
                memoryLogger.warning("⚠️ Player stopped unexpectedly")
                player.play()
            }
        }

        // Observe end of playback
        playerItemDidPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.isClosing {
                memoryLogger.info("🔄 Video reached end, restarting...")
                player.seek(to: .zero)
                player.play()
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
        
        // Capture references BEFORE cleanup for thread safety
        let components = (
            player: self.player,
            playerLayer: self.playerLayer,
            playerItem: self.playerItem,
            statusObserver: self.playerItemStatusObserver,
            rateObserver: self.playerRateObserver,
            endObserver: self.playerItemDidPlayToEndObserver
        )
        
        // Clean references atomically
        self.player = nil
        self.playerItem = nil
        self.playerLayer = nil
        self.playerItemStatusObserver = nil
        self.playerRateObserver = nil
        self.playerItemDidPlayToEndObserver = nil
        
        // Perform asynchronous cleanup to avoid deadlocks
        let performCleanupAsync = {
            // Clean observers FIRST
            components.statusObserver?.invalidate()
            components.rateObserver?.invalidate()
            
            if let observer = components.endObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            
            // Stop player BEFORE removing layer
            components.player?.pause()
            components.player?.replaceCurrentItem(with: nil)
            
            // Remove layer from superlayer
            components.playerLayer?.removeFromSuperlayer()
            
            memoryLogger.info("🧹 Player cleaned successfully")
            
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
    
    /// Gets the total duration of the current video
    /// - Returns: CMTime with total duration or nil if not available
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
        memoryLogger.warning("⚠️ Showing error in window: \(message)")
    }
}
