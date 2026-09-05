import XCTest
import AVFoundation
@testable import LiveWalls

/// Task 3.4 — No-effect-when-healthy: an advancing video must trigger **no
/// rebuild, no static-image apply, and no per-poll telemetry writes**.
///
/// Two properties are checked:
///
/// 1. The health-check decision path (`ensurePlaying`'s `if isPlayingWallpaper`
///    branch, exposed headlessly as `testRunHealthCheckDecision`): with the
///    render-advance verdict `.advancing`, the check returns healthy and the
///    manager takes no action — `attemptBoundedRecovery` is never entered, so
///    the `testFreshRebuildVerifyHook` and `testStaticApplyProbe` seams never
///    fire and the recovery counters stay at zero.
///
/// 2. The telemetry poll (`publishRenderAdvanceAggregate`, extracted from the
///    render-advance poll loop) is edge-triggered: a steady `.advancing` stream
///    writes exactly one entry (the transition), never one per sample.
@MainActor
final class RecoveryNoOpWhenHealthyTests: XCTestCase {

    override func tearDown() {
        RecoveryDebugFlags.resetAllKillSwitches()
        super.tearDown()
    }

    private func makeManager() -> WallpaperManager {
        let manager = WallpaperManager(loadPersistedData: false)
        manager.currentVideo = VideoFile(
            url: URL(fileURLWithPath: "/tmp/no-op-when-healthy-dummy.mp4"),
            name: "No-Op When Healthy Dummy",
            bookmarkData: Data()
        )
        manager.testRecoveryBackoffOverride = [.zero, .zero, .zero]
        return manager
    }

    // MARK: - Property 1: an advancing video drives no recovery

    func testAdvancingVideoTriggersNoRebuildAndNoStaticApply() async {
        let manager = makeManager()

        // A non-empty window list is required to reach the probe verdict switch
        // in checkPlaybackHealth; `.advancing` short-circuits before the window
        // state is inspected, so a paused stand-in window is fine.
        let screen = NSScreen.main ?? NSScreen()
        let window = DesktopVideoWindowMejorada(
            screen: screen,
            videoURL: manager.currentVideo!.url,
            startPaused: true
        )
        defer { window.close() }
        manager.testAttachDesktopWindow(window, url: manager.currentVideo!.url)

        let rebuildCalls = Locked<Int>(0)
        let staticApplyCalls = Locked<Int>(0)
        manager.testFreshRebuildVerifyHook = { _, _ in
            rebuildCalls.mutate { $0 += 1 }
            return true
        }
        manager.testStaticApplyProbe = { _ in
            staticApplyCalls.mutate { $0 += 1 }
            return true
        }

        // Probe says the video is advancing.
        await manager.publishRenderAdvanceAggregate(.advancing)

        let decidedToRecover = await manager.testRunHealthCheckDecision()

        XCTAssertFalse(decidedToRecover,
                       "Un video .advancing se juzga sano — no se dispara recuperación")
        XCTAssertEqual(rebuildCalls.value, 0, "No hay fresh rebuild cuando el video avanza")
        XCTAssertEqual(staticApplyCalls.value, 0, "No hay static-image apply cuando el video avanza")
        XCTAssertEqual(manager.testRecoveryAttempts, 0)
        XCTAssertFalse(manager.testRecoveryExhausted)
    }

    // MARK: - Property 2: the telemetry poll is edge-triggered, not per-frame

    func testSteadyAdvancingStreamWritesTelemetryOnce() async {
        let manager = makeManager()

        // Five consecutive polls all read the same aggregate verdict.
        for _ in 0..<5 {
            await manager.publishRenderAdvanceAggregate(.advancing)
        }

        XCTAssertEqual(manager.testProbeStateWrites, ["advancing"],
                       "Un flujo estable .advancing escribe una sola entrada de telemetría (la transición)")
        XCTAssertEqual(manager.renderAdvanceState, .advancing)
    }

    func testTelemetryRecordsTransitionsNotSamples() async {
        let manager = makeManager()

        // idle → advancing → advancing → stalled → stalled → advancing
        let stream: [RenderAdvanceVerdict] = [.advancing, .advancing, .stalled, .stalled, .advancing]
        for verdict in stream {
            await manager.publishRenderAdvanceAggregate(verdict)
        }

        XCTAssertEqual(manager.testProbeStateWrites, ["advancing", "stalled", "advancing"],
                       "Solo las transiciones se registran; las muestras repetidas se colapsan")
    }
}

/// Minimal lock so `@Sendable` test closures can accumulate state across `await`
/// hops without tripping Swift concurrency capture rules.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { self.storage = value }
    var value: Value { lock.withLock { storage } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&storage) } }
}
