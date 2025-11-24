import Foundation
import os.log

/// Actor for thread-safe telemetry collection and reporting of video playback metrics
/// Provides structured monitoring of playback stability and performance
actor PlaybackTelemetry {
    private let logger = Logger(subsystem: "com.livewalls.app", category: "PlaybackTelemetry")
    
    // MARK: - Telemetry Counters
    
    /// Total number of playback stalls detected
    private var stallCount: Int = 0
    
    /// Total number of window recreation events
    private var windowRecreationCount: Int = 0
    
    /// Total number of frame drops detected
    private var frameDropCount: Int = 0
    
    /// Total number of health checks performed
    private var healthCheckCount: Int = 0
    
    /// Timestamp of the last detected stall
    private var lastStallTime: Date?
    
    /// Timestamp of the last window recreation
    private var lastRecreationTime: Date?
    
    // MARK: - Session Tracking
    
    /// When this telemetry session started
    private var sessionStartTime: Date = Date()
    
    /// Cumulative playback time (for future use with pause tracking)
    private var totalPlaybackTime: TimeInterval = 0
    
    // MARK: - Public API
    
    /// Record detection of a playback stall
    func recordStall() {
        stallCount += 1
        lastStallTime = Date()
        logger.warning("📊 Telemetry: Stall detected (total: \(self.stallCount, privacy: .public))")
    }
    
    /// Record a window recreation event
    func recordWindowRecreation() {
        windowRecreationCount += 1
        lastRecreationTime = Date()
        logger.info("📊 Telemetry: Window recreation (total: \(self.windowRecreationCount, privacy: .public))")
    }
    
    /// Record detection of a frame drop
    func recordFrameDrop() {
        frameDropCount += 1
        logger.debug("📊 Telemetry: Frame drop (total: \(self.frameDropCount, privacy: .public))")
    }
    
    /// Record execution of a health check
    func recordHealthCheck() {
        healthCheckCount += 1
    }
    
    /// Get a comprehensive telemetry report
    /// - Returns: TelemetryReport with current metrics
    func getTelemetryReport() -> TelemetryReport {
        let uptime = Date().timeIntervalSince(sessionStartTime)
        return TelemetryReport(
            stallCount: stallCount,
            windowRecreationCount: windowRecreationCount,
            frameDropCount: frameDropCount,
            healthCheckCount: healthCheckCount,
            uptime: uptime,
            lastStallTime: lastStallTime,
            lastRecreationTime: lastRecreationTime,
            totalPlaybackTime: totalPlaybackTime
        )
    }
    
    /// Get current stall count
    func getStallCount() -> Int {
        return stallCount
    }
    
    /// Get current window recreation count
    func getWindowRecreationCount() -> Int {
        return windowRecreationCount
    }
    
    /// Get current frame drop count
    func getFrameDropCount() -> Int {
        return frameDropCount
    }
    
    /// Get current health check count
    func getHealthCheckCount() -> Int {
        return healthCheckCount
    }
    
    /// Reset all telemetry counters (for new session)
    func resetTelemetry() {
        stallCount = 0
        windowRecreationCount = 0
        frameDropCount = 0
        healthCheckCount = 0
        lastStallTime = nil
        lastRecreationTime = nil
        sessionStartTime = Date()
        totalPlaybackTime = 0
        logger.info("📊 Telemetry: Reset for new session")
    }
    
    /// Update cumulative playback time
    /// - Parameter duration: Time to add to total playback time
    func addPlaybackTime(_ duration: TimeInterval) {
        totalPlaybackTime += duration
    }
}

/// Immutable report of playback telemetry metrics
struct TelemetryReport: Sendable {
    /// Number of stalls detected during session
    let stallCount: Int
    
    /// Number of window recreation events
    let windowRecreationCount: Int
    
    /// Number of frame drops detected
    let frameDropCount: Int
    
    /// Number of health checks performed
    let healthCheckCount: Int
    
    /// Total session uptime in seconds
    let uptime: TimeInterval
    
    /// Timestamp of last stall (if any)
    let lastStallTime: Date?
    
    /// Timestamp of last window recreation (if any)
    let lastRecreationTime: Date?
    
    /// Total cumulative playback time
    let totalPlaybackTime: TimeInterval
    
    /// Human-readable description of telemetry metrics
    var description: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        
        return """
        === Playback Telemetry Report ===
        Uptime: \(String(format: "%.1f", uptime))s
        Playback Time: \(String(format: "%.1f", totalPlaybackTime))s
        
        Performance Metrics:
        • Stalls: \(stallCount)
        • Window Recreations: \(windowRecreationCount)
        • Frame Drops: \(frameDropCount)
        • Health Checks: \(healthCheckCount)
        
        Recent Events:
        • Last Stall: \(lastStallTime?.formatted() ?? "Never")
        • Last Recreation: \(lastRecreationTime?.formatted() ?? "Never")
        """
    }
}
