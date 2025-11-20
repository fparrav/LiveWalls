import Foundation
import AppKit
import AVFoundation

/// Manages smooth transitions between video wallpapers
@MainActor
class TransitionManager {
    
    // MARK: - Properties
    
    private var currentTransition: Transition? = nil
    private var animationTask: Task<Void, Never>? = nil
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
        let fromWindows: [DesktopVideoWindowMejorada]
        let toWindows: [DesktopVideoWindowMejorada]
        
        init(type: TransitionType, duration: TimeInterval, fromWindow: DesktopVideoWindowMejorada?, toWindow: DesktopVideoWindowMejorada?) {
            self.type = type
            self.duration = duration
            self.startTime = Date()
            self.fromWindow = fromWindow
            self.toWindow = toWindow
            self.fromWindows = []
            self.toWindows = []
        }
        
        init(type: TransitionType, duration: TimeInterval, fromWindows: [DesktopVideoWindowMejorada], toWindows: [DesktopVideoWindowMejorada]) {
            self.type = type
            self.duration = duration
            self.startTime = Date()
            self.fromWindow = fromWindows.first
            self.toWindow = toWindows.first
            self.fromWindows = fromWindows
            self.toWindows = toWindows
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
        currentTransition = Transition(
            type: .crossfade,
            duration: transitionDuration,
            fromWindow: fromWindow,
            toWindow: toWindow
        )
        startAnimationTask()
    }
    
    /// Starts a crossfade transition between multiple video windows (multi-monitor)
    /// - Parameters:
    ///   - fromWindows: Current video windows (will fade out)
    ///   - toWindows: Next video windows (will fade in)
    func startCrossfadeTransition(fromWindows: [DesktopVideoWindowMejorada], toWindows: [DesktopVideoWindowMejorada]) {
        currentTransition = Transition(
            type: .crossfade,
            duration: transitionDuration,
            fromWindows: fromWindows,
            toWindows: toWindows
        )
        startAnimationTask()
    }
    
    /// Stops any ongoing transition
    func stopCurrentTransition() {
        currentTransition = nil
    }
    
    // MARK: - Private Methods
    
    /// Animates the current transition using an async Task on the main actor
    private func startAnimationTask() {
        guard currentTransition != nil else { return }
        // Cancel any running task
        animationTask?.cancel()
        
        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Drive animation at ~60 FPS
            let frameInterval: UInt64 = 16_666_667 // nanoseconds (~16.67ms)
            while let t = self.currentTransition {
                let elapsed = Date().timeIntervalSince(t.startTime)
                let progress = min(elapsed / t.duration, 1.0)
                
                switch t.type {
                case .crossfade:
                    self.updateCrossfadeOpacity(progress: progress, transition: t)
                case .fadeOutFadeIn:
                    self.updateFadeOutFadeInOpacity(progress: progress, transition: t)
                }
                
                if progress >= 1.0 {
                    self.completeTransition(transition: t)
                    break
                }
                try? await Task.sleep(nanoseconds: frameInterval)
            }
        }
    }
    
    /// Updates opacity for crossfade transition
    private func updateCrossfadeOpacity(progress: Double, transition: Transition) {
        let fromAlpha = 1.0 - progress
        let toAlpha = progress
        
        // Multi-monitor: fade all, fallback to single windows
        if !transition.fromWindows.isEmpty || !transition.toWindows.isEmpty {
            transition.fromWindows.forEach { $0.setOpacity(fromAlpha) }
            transition.toWindows.forEach { $0.setOpacity(toAlpha) }
        } else {
            if let fromWindow = transition.fromWindow {
                fromWindow.setOpacity(fromAlpha)
            }
            if let toWindow = transition.toWindow {
                toWindow.setOpacity(toAlpha)
            }
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

// MARK: - Note: setOpacity extension is defined in DesktopVideoWindowMejorada.swift
