import Foundation
import os.log

/// Lightweight, durable telemetry for the suspend → wake → recover → verify lifecycle.
/// Writes compact, one-line entries to a rolling file in the app container that survives
/// unified-log eviction. No per-frame writes — lifecycle events only.
actor RecoveryTelemetry {
    // MARK: - Configuration

    private let maxFileSizeBytes: Int = 64 * 1024  // 64 KB rolling cap
    private let maxEntries: Int = 2000             // hard cap on retained lines
    private let logger = Logger(subsystem: "com.livewalls.app", category: "RecoveryTelemetry")

    // MARK: - State

    private var telemetryURL: URL?
    private var isEnabled: Bool = true

    // MARK: - Public API

    /// Initialize the telemetry writer, creating/opening the rolling file.
    /// Call once at app startup.
    func configure() {
        guard isEnabled else { return }
        do {
            let url = try makeTelemetryURL()
            self.telemetryURL = url
            // Ensure file exists
            if !FileManager.default.fileExists(atPath: url.path) {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
            logger.info("📝 RecoveryTelemetry configured at \(url.path)")
        } catch {
            logger.error("❌ Failed to configure RecoveryTelemetry: \(error.localizedDescription)")
            // Disable on failure — keep app functional
            isEnabled = false
        }
    }

    /// Disable telemetry entirely (for testing or user preference).
    func disable() {
        isEnabled = false
    }

    /// Enable telemetry (default on).
    func enable() {
        isEnabled = true
    }

    /// Record a lifecycle stage with optional outcome detail.
    /// Stages: "suspend", "wake", "recover-attempted", "recover-outcome", "verify-result"
    /// Outcomes: free-form string; use standard codes for machine parsing:
    ///   - suspend: "observed"
    ///   - wake: "observed"
    ///   - recover-attempted: "started" | "skipped-not-playing" | "skipped-already-recovering"
    ///   - recover-outcome: "success" | "failed:<reason>" | "timeout" | "no-video"
    ///   - verify-result: "advancing" | "stalled" | "no-windows" | "error:<reason>"
    func record(stage: String, outcome: String? = nil, details: String? = nil) {
        guard isEnabled else { return }
        guard let url = telemetryURL else {
            logger.debug("⏭️ RecoveryTelemetry not configured, dropping: \(stage)")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        var line = "\(timestamp) stage=\(stage)"
        if let outcome { line += " outcome=\(outcome)" }
        if let details { line += " details=\(details)" }
        line += "\n"

        appendLine(line, to: url)
    }

    /// Convenience for suspend (willSleep notification).
    func recordSuspend() {
        record(stage: "suspend", outcome: "observed")
    }

    /// Convenience for wake (didWake notification).
    func recordWake() {
        record(stage: "wake", outcome: "observed")
    }

    /// Convenience for recovery attempt start.
    func recordRecoverAttempted(reason: String) {
        record(stage: "recover-attempted", outcome: "started", details: "reason=\(reason)")
    }

    /// Convenience for recovery skipped (not playing / already recovering).
    func recordRecoverSkipped(reason: String) {
        record(stage: "recover-attempted", outcome: "skipped", details: "reason=\(reason)")
    }

    /// Convenience for recovery outcome.
    func recordRecoverOutcome(success: Bool, reason: String? = nil) {
        let outcome = success ? "success" : "failed"
        record(stage: "recover-outcome", outcome: outcome, details: reason.map { "reason=\($0)" })
    }

    /// Convenience for verification result.
    func recordVerifyResult(advancing: Bool, detail: String? = nil) {
        let outcome = advancing ? "advancing" : "stalled"
        record(stage: "verify-result", outcome: outcome, details: detail)
    }

    /// Convenience for render-advance probe state transitions.
    /// Maps a verdict string to telemetry outcomes.
    /// - Parameter verdict: The aggregate probe verdict string ("advancing", "stalled", "idle", "unknown").
    func recordProbeState(_ verdict: String) {
        record(stage: "verify-result", outcome: verdict)
    }

    // MARK: - Private

    private func makeTelemetryURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw RecoveryTelemetryError.noAppSupportDirectory
        }
        let livewallsDir = appSupport.appendingPathComponent("LiveWalls")
        if !FileManager.default.fileExists(atPath: livewallsDir.path) {
            try FileManager.default.createDirectory(at: livewallsDir, withIntermediateDirectories: true)
        }
        return livewallsDir.appendingPathComponent("recovery_telemetry.log")
    }

    private func appendLine(_ line: String, to url: URL) {
        // Perform bounded write on a background queue to avoid main-thread I/O
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.doAppendLine(line, to: url)
        }
    }

    private func doAppendLine(_ line: String, to url: URL) {
        do {
            // Read existing, append, enforce bounds, write back atomically
            var content: String
            if FileManager.default.fileExists(atPath: url.path) {
                content = try String(contentsOf: url, encoding: .utf8)
            } else {
                content = ""
            }

            // Append new line
            content += line

            // Enforce line count cap (keep last maxEntries)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > maxEntries {
                content = lines.suffix(maxEntries).joined(separator: "\n") + "\n"
            }

            // Enforce file size cap (keep last maxFileSizeBytes)
            if content.utf8.count > maxFileSizeBytes {
                let data = content.data(using: .utf8) ?? Data()
                let suffix = data.suffix(maxFileSizeBytes)
                // Find first newline after truncation to avoid partial line
                if let newlineIdx = suffix.firstIndex(of: UInt8(ascii: "\n")) {
                    content = String(data: suffix[newlineIdx.advanced(by: 1)...], encoding: .utf8) ?? ""
                } else {
                    content = ""
                }
            }

            // Atomic write
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // Log but don't crash — telemetry is best-effort
            logger.error("❌ RecoveryTelemetry write failed: \(error.localizedDescription)")
        }
    }
}

enum RecoveryTelemetryError: Error, LocalizedError {
    case noAppSupportDirectory

    var errorDescription: String? {
        switch self {
        case .noAppSupportDirectory:
            return "Could not locate Application Support directory"
        }
    }
}

// MARK: - Telemetry Stage Constants (for consistent log parsing)

extension RecoveryTelemetry {
    /// Standard stage names for the recovery lifecycle.
    enum Stage: String {
        case suspend = "suspend"
        case wake = "wake"
        case recoverAttempted = "recover-attempted"
        case recoverOutcome = "recover-outcome"
        case verifyResult = "verify-result"
    }

    /// Standard outcome codes for machine parsing.
    enum Outcome: String {
        // suspend / wake
        case observed = "observed"

        // recover-attempted
        case started = "started"
        case skipped = "skipped"
        case skippedNotPlaying = "skipped-not-playing"
        case skippedAlreadyRecovering = "skipped-already-recovering"

        // recover-outcome
        case success = "success"
        case failed = "failed"
        case timeout = "timeout"
        case noVideo = "no-video"

        // verify-result
        case advancing = "advancing"
        case stalled = "stalled"
        case noWindows = "no-windows"
        case error = "error"
    }
}