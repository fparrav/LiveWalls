//
//  ThrottleManager.swift
//  LiveWalls
//
//  Created for performance optimization - Phase 2
//  Handles throttling of frequent system notifications to prevent excessive reactivations
//

import Foundation

/// Manages throttling of frequent events to prevent excessive function calls
/// Used to consolidate multiple rapid notifications into a single action
actor ThrottleManager {
    private var lastExecutionTimes: [String: Date] = [:]
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    
    /// Throttles a function call by key, ensuring it doesn't execute more than once per time window
    /// - Parameters:
    ///   - key: Unique identifier for the throttled operation
    ///   - interval: Minimum time interval between executions (in seconds)
    ///   - action: Async closure to execute after throttle period
    func throttle(key: String, interval: TimeInterval, action: @escaping @MainActor () async -> Void) {
        let now = Date()
        
        // Check if we need to throttle
        if let lastTime = lastExecutionTimes[key] {
            let elapsed = now.timeIntervalSince(lastTime)
            
            if elapsed < interval {
                // Still within throttle window - cancel any pending task and schedule new one
                pendingTasks[key]?.cancel()
                
                let remainingTime = interval - elapsed
                pendingTasks[key] = Task {
                    try? await Task.sleep(for: .seconds(remainingTime))
                    
                    guard !Task.isCancelled else { return }
                    
                    await MainActor.run {
                        Task {
                            await action()
                        }
                    }
                    
                    await self.updateLastExecution(key: key)
                    await self.clearPendingTask(key: key)
                }
                
                return
            }
        }
        
        // First call or outside throttle window - execute immediately
        lastExecutionTimes[key] = now
        
        Task { @MainActor in
            await action()
        }
    }
    
    /// Debounces a function call by key, only executing after a quiet period
    /// - Parameters:
    ///   - key: Unique identifier for the debounced operation
    ///   - delay: Quiet period duration (in seconds) before execution
    ///   - action: Async closure to execute after quiet period
    func debounce(key: String, delay: TimeInterval, action: @escaping @MainActor () async -> Void) {
        // Cancel any existing pending task
        pendingTasks[key]?.cancel()
        
        pendingTasks[key] = Task {
            try? await Task.sleep(for: .seconds(delay))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                Task {
                    await action()
                }
            }
            
            await self.updateLastExecution(key: key)
            await self.clearPendingTask(key: key)
        }
    }
    
    private func updateLastExecution(key: String) {
        lastExecutionTimes[key] = Date()
    }
    
    private func clearPendingTask(key: String) {
        pendingTasks[key] = nil
    }
    
    /// Clears all throttle/debounce state
    func reset() {
        lastExecutionTimes.removeAll()
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
    }
}
