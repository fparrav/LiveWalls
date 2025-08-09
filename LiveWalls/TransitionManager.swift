import Foundation
import AppKit
import AVFoundation

/// Manages smooth transitions between video wallpapers
@MainActor
class TransitionManager {
    
    // MARK: - Properties
    
    private var currentTransition: Transition? = nil
    private let transitionDuration: TimeInterval = 2.0 // Default 2 seconds
    
    // MARK: - Types
    
    enum TransitionType {
        case crossfade
        case fadeOutFadeIn
        // Add more transition types as needed
    }
    
    struct Transition {
        let type: TransitionType
        let duration: TimeInterval
        let startTime: Date
        let fromWindow: DesktopVideoWindowMejorada?
        let toWindow: DesktopVideoWindowMejorada?
        
        init(type: TransitionType, duration: TimeInterval, fromWindow: DesktopVideoWindowMejorada?, toWindow: DesktopVideoWindowMejorada?) {
            self.type = type
            self.duration = duration
            self.startTime = Date()
            self.fromWindow = fromWindow
            self.toWindow = toWindow
        }
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Starts a crossfade transition between two video windows
    /// - Parameters:
    ///   - fromWindow: Current video window (will fade out)
    ///   - toWindow: Next video window (will fade in)
    func startCrossfadeTransition(fromWindow: DesktopVideoWindowMejorada?, toWindow: DesktopVideoWindowMejorada?) {
        let transition = Transition(
            type: .crossfade,
            duration: transitionDuration,
            fromWindow: fromWindow,
            toWindow: toWindow
        )
        
        currentTransition = transition
        
        // Start the transition animation
        animateTransition()
    }
    
    /// Stops any ongoing transition
    func stopCurrentTransition() {
        currentTransition = nil
    }
    
    // MARK: - Private Methods
    
    /// Animates the current transition
    private func animateTransition() {
        guard let transition = currentTransition else { return }
        
        // Create a timer to update the transition progress
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self, let currentTransition = self.currentTransition else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(currentTransition.startTime)
            let progress = min(elapsed / currentTransition.duration, 1.0)
            
            // Update opacity of windows based on progress
            switch currentTransition.type {
            case .crossfade:
                self.updateCrossfadeOpacity(progress: progress, transition: currentTransition)
            case .fadeOutFadeIn:
                self.updateFadeOutFadeInOpacity(progress: progress, transition: currentTransition)
            }
            
            // Stop timer when transition is complete
            if progress >= 1.0 {
                timer.invalidate()
                self.completeTransition(transition: currentTransition)
            }
        }
        
        // Keep reference to timer to prevent it from being deallocated
        // Note: In a real implementation, we'd want to store this timer reference properly
    }
    
    /// Updates opacity for crossfade transition
    private func updateCrossfadeOpacity(progress: Double, transition: Transition) {
        let fromAlpha = 1.0 - progress
        let toAlpha = progress
        
        // Update opacity of fromWindow (fade out)
        if let fromWindow = transition.fromWindow {
            fromWindow.setOpacity(fromAlpha)
        }
        
        // Update opacity of toWindow (fade in)
        if let toWindow = transition.toWindow {
            toWindow.setOpacity(toAlpha)
        }
    }
    
    /// Updates opacity for fade out/fade in transition
    private func updateFadeOutFadeInOpacity(progress: Double, transition: Transition) {
        let fromAlpha = 1.0 - progress
        let toAlpha = progress
        
        // Update opacity of fromWindow (fade out)
        if let fromWindow = transition.fromWindow {
            fromWindow.setOpacity(fromAlpha)
        }
        
        // Update opacity of toWindow (fade in)
        if let toWindow = transition.toWindow {
            toWindow.setOpacity(toAlpha)
        }
    }
    
    /// Completes the transition and cleans up
    private func completeTransition(transition: Transition) {
        // Ensure we're still on the main thread
        Task { @MainActor in
            // Remove any temporary references or perform cleanup if needed
            currentTransition = nil
            
            // In a real implementation, we might:
            // 1. Remove the old window if it's no longer needed
            // 2. Update references to point to the new window
            // 3. Perform any final cleanup
            
            print("Transition completed")
        }
    }
}

// MARK: - Extension for DesktopVideoWindowMejorada

extension DesktopVideoWindowMejorada {
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
}
