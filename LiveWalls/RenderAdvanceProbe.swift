import Foundation
import AVFoundation
import os.log

/// Verdict of a single probe sample or the aggregated state.
/// - `idle`: probe is not evaluating (playback not expected).
/// - `advancing`: render is progressing (forward advance or loop wrap detected this sample).
/// - `stalled`: N consecutive samples with no advance and no wrap.
/// - `unknown`: insufficient samples yet to classify (first sample).
enum RenderAdvanceVerdict: Sendable, Equatable {
    case idle
    case advancing
    case stalled
    case unknown
}

/// Per-window probe state for a single display's video pipeline.
/// One instance per `DesktopVideoWindowMejorada` so recovery can be per-display.
actor RenderAdvanceProbe {
    // MARK: - Configuration

    private let logger = Logger(subsystem: "com.livewalls.app", category: "RenderAdvanceProbe")

    /// Sample period in seconds. Default 2.5 s (mid-range of 2–3 s spec).
    let sampleInterval: TimeInterval

    /// Number of consecutive no-progress samples before declaring stalled.
    /// Default 3: 3 × 2.5 s = 7.5 s without advance/wrap → stalled.
    let stalledThreshold: Int

    // MARK: - State

    private var lastSampleTime: CMTime?
    // MARK: - Internal counters (internal for testability; NOT private — actors are isolation boundaries)
    var consecutiveNoProgress: Int = 0
    private var isEvaluating: Bool = false
    private var samplingTask: Task<Void, Never>?
    private var timeSource: (@Sendable () async -> CMTime?)?

    // Exposed state for callers
    private(set) var currentVerdict: RenderAdvanceVerdict = .idle

    // MARK: - Init

    init(sampleInterval: TimeInterval = 2.5, stalledThreshold: Int = 3) {
        self.sampleInterval = sampleInterval
        self.stalledThreshold = stalledThreshold
    }

    // MARK: - Public API

    /// Starts periodic evaluation with a time source.
    /// - Parameter timeSource: A `@Sendable` async closure that returns the player's current time.
    ///   Typically captures a window and hops to MainActor: `{ await window.getCurrentTime() }`.
    ///   Called every `sampleInterval` while evaluating.
    func startEvaluating(timeSource: @escaping @Sendable () async -> CMTime?) {
        guard !isEvaluating else { return }
        self.timeSource = timeSource
        isEvaluating = true
        consecutiveNoProgress = 0
        lastSampleTime = nil
        currentVerdict = .unknown

        // Launch self-driving sampling loop
        samplingTask = Task { [weak self] in
            guard let self else { return }
            while await self.isEvaluating {
                // Sleep for the sample interval (cancels cleanly when task is cancelled)
                do {
                    try await Task.sleep(for: .seconds(await self.sampleInterval))
                } catch {
                    break // Task cancelled
                }

                // Check again in case we were stopped during sleep
                let stillEvaluating = await self.isEvaluating
                if !stillEvaluating { break }

                // Fetch current time via the provided source
                guard let timeSource = await self.timeSource else { break }
                let currentTime = await timeSource()

                // Evaluate and update state
                await self.evaluateSample(currentTime: currentTime)
            }
        }
    }

    /// Stops periodic evaluation and cancels the sampling loop.
    func stopEvaluating() {
        isEvaluating = false
        timeSource = nil
        samplingTask?.cancel()
        samplingTask = nil
        currentVerdict = .idle
        consecutiveNoProgress = 0
        lastSampleTime = nil
    }

    /// Forces an immediate sample using the stored time source (e.g., on wake to get a baseline).
    /// Returns the verdict for this sample. Does NOT start periodic evaluation.
    func sampleNow() async -> RenderAdvanceVerdict? {
        guard let timeSource = timeSource else { return nil }
        let currentTime = await timeSource()
        return evaluateSample(currentTime: currentTime)
    }

    /// Core evaluation logic: given a new `currentTime`, classifies advance/wrap/stall.
    /// Called internally by the sampling loop; also callable directly for unit tests.
    /// Returns the new `currentVerdict`.
    @discardableResult
    func evaluateSample(currentTime: CMTime?) -> RenderAdvanceVerdict {
        guard isEvaluating else {
            currentVerdict = .idle
            return .idle
        }

        guard let currentTime = currentTime, currentTime.isValid, currentTime.seconds > 0 else {
            // No valid time yet — stay unknown, don't penalize
            currentVerdict = .unknown
            return .unknown
        }

        if let lastTime = lastSampleTime, lastTime.isValid, lastTime.seconds > 0 {
            let currentSecs = currentTime.seconds
            let lastSecs = lastTime.seconds

            if currentSecs > lastSecs + 0.05 {
                // Forward advance (allow small epsilon for clock jitter)
                consecutiveNoProgress = 0
                lastSampleTime = currentTime
                currentVerdict = .advancing
                logger.debug("📈 RenderAdvanceProbe: advancing (Δ=\(String(format: "%.2f", currentSecs - lastSecs))s)")
                return .advancing
            } else if currentSecs < lastSecs - 0.05 {
                // Wrap/decrease → loop restart with AVPlayerLooper
                consecutiveNoProgress = 0
                lastSampleTime = currentTime
                currentVerdict = .advancing
                logger.debug("🔄 RenderAdvanceProbe: loop wrap detected (was \(String(format: "%.2f", lastSecs))s, now \(String(format: "%.2f", currentSecs))s)")
                return .advancing
            } else {
                // No meaningful change
                consecutiveNoProgress += 1
                logger.debug("⏸️ RenderAdvanceProbe: no progress (count=\(self.consecutiveNoProgress)/\(self.stalledThreshold))")

                if consecutiveNoProgress >= stalledThreshold {
                    currentVerdict = .stalled
                    logger.warning("🛑 RenderAdvanceProbe: STALLED after \(self.consecutiveNoProgress) samples with no advance/wrap")
                } else {
                    currentVerdict = .unknown // not yet stalled, but not advancing this sample
                }
                return currentVerdict
            }
        } else {
            // First valid sample — establish baseline
            lastSampleTime = currentTime
            currentVerdict = .unknown
            logger.debug("📍 RenderAdvanceProbe: baseline established at \(String(format: "%.2f", currentTime.seconds))s")
            return .unknown
        }
    }
}

// MARK: - Batch evaluation for multi-display (convenience; each probe still owns its loop)

extension RenderAdvanceProbe {
    /// Creates a probe per window and starts all of them with their respective time sources.
    /// Returns the array of probes. Caller must retain them to keep loops alive.
    static func startProbes(
        for windows: [DesktopVideoWindowMejorada],
        sampleInterval: TimeInterval = 2.5,
        stalledThreshold: Int = 3
    ) async -> [RenderAdvanceProbe] {
        var probes: [RenderAdvanceProbe] = []
        for window in windows {
            let probe = RenderAdvanceProbe(sampleInterval: sampleInterval, stalledThreshold: stalledThreshold)
            await probe.startEvaluating(timeSource: { await window.getCurrentTime() })
            probes.append(probe)
        }
        return probes
    }

    /// Stops all probes and clears the array.
    static func stopProbes(_ probes: [RenderAdvanceProbe]) async {
        for probe in probes {
            await probe.stopEvaluating()
        }
    }

    /// Collects current verdicts from all probes.
    static func collectVerdicts(_ probes: [RenderAdvanceProbe]) async -> [RenderAdvanceVerdict] {
        var verdicts: [RenderAdvanceVerdict] = []
        for probe in probes {
            verdicts.append(await probe.currentVerdict)
        }
        return verdicts
    }

    /// Checks if ANY probe reports stalled (useful for global recovery trigger).
    static func anyStalled(_ probes: [RenderAdvanceProbe]) async -> Bool {
        for probe in probes {
            if await probe.currentVerdict == .stalled {
                return true
            }
        }
        return false
    }

    /// Checks if ALL evaluating probes report advancing (healthy steady state).
    static func allAdvancing(_ probes: [RenderAdvanceProbe]) async -> Bool {
        var anyEvaluating = false
        for probe in probes {
            let v = await probe.currentVerdict
            if v != .idle {
                anyEvaluating = true
                if v != .advancing {
                    return false
                }
            }
        }
        return anyEvaluating // true only if at least one was evaluating and all were advancing
    }
}