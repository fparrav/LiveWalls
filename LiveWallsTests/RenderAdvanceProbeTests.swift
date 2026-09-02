import XCTest
import AVFoundation
@testable import LiveWalls

/// Tests para RenderAdvanceProbe — render-advance probe classifier y deterministic stall hook
final class RenderAdvanceProbeTests: XCTestCase {

    var probe: RenderAdvanceProbe!

    override func setUp() async throws {
        try await super.setUp()
        probe = RenderAdvanceProbe(sampleInterval: 2.5, stalledThreshold: 3)
    }

    override func tearDown() async throws {
        // Stop the probe before releasing (avoids async in deinit)
        await probe?.stopEvaluating()
        probe = nil
        // Reset UserDefaults flags so tests don't leak
        UserDefaults.standard.set(false, forKey: "RecoveryDebug.SimulateStall")
        try await super.tearDown()
    }

    // MARK: - Probe Classifier Tests

    /// Test 1: First sample → .unknown (baseline establishment)
    func testFirstSampleReturnsUnknownBaseline() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        let verdict = await probe.evaluateSample(currentTime: CMTime(seconds: 5.0, preferredTimescale: 600))
        XCTAssertEqual(verdict, .unknown, "First valid sample should establish baseline as unknown")
    }

    /// Test 2: Monotonic forward advance across samples → .advancing
    func testMonotonicForwardAdvanceReturnsAdvancing() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        // Baseline
        _ = await probe.evaluateSample(currentTime: CMTime(seconds: 0.0, preferredTimescale: 600))

        let v1 = await probe.evaluateSample(currentTime: CMTime(seconds: 1.0, preferredTimescale: 600))
        XCTAssertEqual(v1, .advancing, "Forward advance should classify as advancing")

        let v2 = await probe.evaluateSample(currentTime: CMTime(seconds: 2.0, preferredTimescale: 600))
        XCTAssertEqual(v2, .advancing, "Continued forward advance should remain advancing")
    }

    /// Test 3: Playhead decrease (loop wrap with AVPlayerLooper) → .advancing
    func testPlayheadDecreaseLoopWrapReturnsAdvancing() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        // Baseline at end of loop
        _ = await probe.evaluateSample(currentTime: CMTime(seconds: 30.0, preferredTimescale: 600))

        // Wrap around to start of loop (decrease > 0.05 s)
        let v = await probe.evaluateSample(currentTime: CMTime(seconds: 0.1, preferredTimescale: 600))
        XCTAssertEqual(v, .advancing, "Playhead wrap (decrease) should classify as advancing")

        // consecutiveNoProgress should reset on wrap
        let counterAfterWrap = await probe.consecutiveNoProgress
        XCTAssertEqual(counterAfterWrap, 0, "Wrap should reset no-progress counter")
    }

    /// Test 4a: Same time for fewer than threshold → NOT stalled yet
    func testSameTimeBelowThresholdDoesNotReturnStalled() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        // Baseline
        _ = await probe.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))

        let v1 = await probe.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))
        XCTAssertEqual(v1, .unknown, "One no-progress sample should stay unknown")

        let v2 = await probe.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))
        XCTAssertEqual(v2, .unknown, "Two no-progress samples (below threshold 3) should stay unknown")
    }

    /// Test 4b: Same time for stalledThreshold consecutive samples → .stalled
    func testSameTimeAtThresholdReturnsStalled() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        // Baseline
        _ = await probe.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))

        // Threshold-1 consecutive samples → still unknown
        for i in 0..<2 {
            let v = await probe.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))
            XCTAssertEqual(v, .unknown, "Sample \(i+1): below threshold, should not be stalled")
        }

        // Threshold-th sample → .stalled
        let vFinal = await probe.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))
        XCTAssertEqual(vFinal, .stalled, "At threshold, should be classified as stalled")
    }

    /// Test 5: Invalid/nil/zero time → .unknown, doesn't count toward stall
    func testInvalidTimeDoesNotCountTowardStall() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        // Nil time
        let vNil = await probe.evaluateSample(currentTime: nil)
        XCTAssertEqual(vNil, .unknown, "Nil time should return unknown")
        let counterAfterNil = await probe.consecutiveNoProgress
        XCTAssertEqual(counterAfterNil, 0, "Nil time should not increment no-progress")

        // Zero seconds
        let vZero = await probe.evaluateSample(currentTime: CMTime(seconds: 0, preferredTimescale: 600))
        XCTAssertEqual(vZero, .unknown, "Zero seconds should return unknown")
        let counterAfterZero = await probe.consecutiveNoProgress
        XCTAssertEqual(counterAfterZero, 0, "Zero seconds should not increment no-progress")
    }

    /// Test 6: After stopEvaluating → .idle
    func testStopEvaluatingReturnsIdle() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })
        _ = await probe.evaluateSample(currentTime: CMTime(seconds: 5.0, preferredTimescale: 600))

        let vBefore = await probe.currentVerdict
        XCTAssertEqual(vBefore, .unknown)

        await probe.stopEvaluating()
        let vAfter = await probe.currentVerdict
        XCTAssertEqual(vAfter, .idle, "After stopEvaluating, verdict should be idle")
    }

    /// Test 7: Advancing resets no-progress counter
    func testAdvancingResetsNoProgressCounter() async throws {
        await probe.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        // Baseline
        _ = await probe.evaluateSample(currentTime: CMTime(seconds: 0.0, preferredTimescale: 600))

        // Advance
        let vAdv = await probe.evaluateSample(currentTime: CMTime(seconds: 1.0, preferredTimescale: 600))
        XCTAssertEqual(vAdv, .advancing)

        // Two no-progress samples (not yet stalled)
        let v1 = await probe.evaluateSample(currentTime: CMTime(seconds: 1.0, preferredTimescale: 600))
        let v2 = await probe.evaluateSample(currentTime: CMTime(seconds: 1.0, preferredTimescale: 600))
        XCTAssertEqual(v1, .unknown, "One no-progress sample should stay unknown")
        XCTAssertEqual(v2, .unknown, "Two no-progress samples (below threshold 3) should stay unknown")

        // New advance resets counter
        let vNew = await probe.evaluateSample(currentTime: CMTime(seconds: 2.0, preferredTimescale: 600))
        XCTAssertEqual(vNew, .advancing)
        let counterAfterAdvance = await probe.consecutiveNoProgress
        XCTAssertEqual(counterAfterAdvance, 0, "Advancement after stalls should reset counter")
    }

    // MARK: - Deterministic Stall Hook Tests

    /// Test 8: Default simulateStall == false, isSimulatingStall == false
    func testDefaultFlagsAreOff() {
        XCTAssertFalse(RecoveryDebugFlags.simulateStall, "Default simulateStall should be false")
        XCTAssertFalse(RecoveryDebugFlags.isSimulatingStall, "Default isSimulatingStall should be false")
    }

    /// Test 9: enableStallSimulation sets flag true; disable/clear sets it false
    func testEnableDisableClearStallSimulation() {
        RecoveryDebugFlags.enableStallSimulation()
        XCTAssertTrue(RecoveryDebugFlags.simulateStall, "enableStallSimulation should set simulateStall to true")
        XCTAssertTrue(RecoveryDebugFlags.isSimulatingStall, "isSimulatingStall should be true")

        RecoveryDebugFlags.disableStallSimulation()
        XCTAssertFalse(RecoveryDebugFlags.simulateStall, "disableStallSimulation should set simulateStall to false")
        XCTAssertFalse(RecoveryDebugFlags.isSimulatingStall, "isSimulatingStall should be false after disable")

        // Re-enable for clear test
        RecoveryDebugFlags.enableStallSimulation()
        XCTAssertTrue(RecoveryDebugFlags.simulateStall)

        RecoveryDebugFlags.clearStallSimulation()
        XCTAssertFalse(RecoveryDebugFlags.simulateStall, "clearStallSimulation should set simulateStall to false")
    }

    /// Test 10: Frozen-time semantics — when flag enabled, constant time stays constant forever.
    /// Proves: "hook-enabled → frozen time → probe sees stalled" vs "hook-off → advancing time → advancing"
    func testHookControlsProbeVerdict() async throws {
        // Scenario A: No hook — advancing times → probe sees advancing
        let probeA = RenderAdvanceProbe(sampleInterval: 2.5, stalledThreshold: 3)
        await probeA.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        let vAdvancing = await probeA.evaluateSample(currentTime: CMTime(seconds: 2.0, preferredTimescale: 600))
        XCTAssertEqual(vAdvancing, .advancing,
                       "With advancing times, probe should report advancing (no hook)")

        await probeA.stopEvaluating()

        // Scenario B: Simulates frozen time (as if stall hook enabled, returns same time)
        let probeB = RenderAdvanceProbe(sampleInterval: 2.5, stalledThreshold: 3)
        await probeB.startEvaluating(timeSource: { CMTime(seconds: 0, preferredTimescale: 600) })

        // First sample establishes baseline
        let vBaseB = await probeB.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))
        XCTAssertEqual(vBaseB, .unknown)

        // Feed constant time (simulates frozen window under stall simulation)
        var vBeforeStalled: RenderAdvanceVerdict = .unknown
        for i in 0..<3 {
            let v = await probeB.evaluateSample(currentTime: CMTime(seconds: 10.0, preferredTimescale: 600))
            if i < 2 {
                vBeforeStalled = v
            }
        }
        XCTAssertEqual(vBeforeStalled, .unknown,
                       "Before threshold, should not be stalled")

        // At this point: baseline (1) + 3 no-progress = 4 samples = threshold met
        let vFinalB = await probeB.currentVerdict
        XCTAssertEqual(vFinalB, .stalled,
                       "Constant time from sample 1 onward should reach stalled at threshold")

        await probeB.stopEvaluating()
    }
}
