import XCTest
import AVFoundation
@testable import LiveWalls

/// Task 3.1 — End-to-end test of the recover → verify cycle using the
/// deterministic stall hook, driven headlessly in CI (no long suspend, no
/// real display).
///
/// The deterministic stall hook (`RecoveryDebugFlags.simulateStall`, task 1.6)
/// is what makes "stalled" reproducible on a real device: it freezes
/// `DesktopVideoWindowMejorada.getCurrentTime()` so the render-advance probe
/// classifies `.stalled` while the decoder still reports healthy. In CI there
/// are no real windows, so `WallpaperManager.testFreshRebuildVerifyHook`
/// (a DEBUG-only seam) stands in for the two steps that cannot run without a
/// display — real window/AVPlayer creation and the first-frame render probe —
/// returning the verdict the probe would have produced.
///
/// Everything else runs for real: the `attemptBoundedRecovery` loop (guard,
/// escalating backoff, attempt counter, telemetry, success/failure branching,
/// exhaustion), the `performFreshRebuild` prelude (currentVideo guard, teardown
/// check, `bookmarkActor.reconcile()`), and the real `WallpaperOperationActor`
/// exclusive lock.
@MainActor
final class RecoveryEndToEndTest: XCTestCase {

    private func makeManagerWithStalledVideo() -> WallpaperManager {
        let manager = WallpaperManager(loadPersistedData: false)
        // A dummy current video is enough: the test seam returns before the
        // bookmark is resolved, so the bookmark data is never dereferenced.
        manager.currentVideo = VideoFile(
            url: URL(fileURLWithPath: "/tmp/e2e-recovery-dummy.mp4"),
            name: "E2E Recovery Dummy",
            bookmarkData: Data()
        )
        // No real backoff waits in CI.
        manager.testRecoveryBackoffOverride = [.zero, .zero, .zero]
        return manager
    }

    /// Full cycle: stall detected → recovery retries → fresh rebuild reports
    /// advancing on the second attempt → recovery succeeds and clears its state.
    func testRecoverThenVerifyAdvancingOnSecondAttempt() async throws {
        RecoveryDebugFlags.enableStallSimulation()
        defer { RecoveryDebugFlags.disableStallSimulation() }
        XCTAssertTrue(RecoveryDebugFlags.isSimulatingStall,
                      "The deterministic stall hook should be active for this scenario")

        let manager = makeManagerWithStalledVideo()

        // The stand-in for the first-frame probe: still stalled on attempt 1,
        // advancing from attempt 2 onward (a fresh rebuild fixed the pipeline).
        let attemptsSeen = Locked<[Int]>([])
        manager.testFreshRebuildVerifyHook = { _, attempt in
            attemptsSeen.mutate { $0.append(attempt) }
            return attempt >= 2
        }

        await manager.testDriveBoundedRecovery(reason: "e2e-deterministic-stall")

        XCTAssertEqual(attemptsSeen.value, [1, 2],
                       "Recovery should retry once: fail on attempt 1, succeed on attempt 2")
        XCTAssertEqual(manager.testRecoveryAttempts, 0,
                       "Attempt counter is reset to zero after a successful recovery")
        XCTAssertFalse(manager.testRecoveryExhausted,
                       "Exhausted flag stays false after a successful recovery")
    }

    /// When every fresh rebuild keeps reporting a stall, recovery stops after the
    /// bounded number of attempts and latches the exhausted flag.
    func testRecoveryExhaustsAfterMaxAttempts() async throws {
        RecoveryDebugFlags.enableStallSimulation()
        defer { RecoveryDebugFlags.disableStallSimulation() }

        let manager = makeManagerWithStalledVideo()

        let callCount = Locked<Int>(0)
        manager.testFreshRebuildVerifyHook = { _, _ in
            callCount.mutate { $0 += 1 }
            return false // never recovers
        }

        await manager.testDriveBoundedRecovery(reason: "e2e-permanent-stall")

        XCTAssertEqual(callCount.value, 3,
                       "The rebuild should be attempted exactly maxRecoveryAttempts times")
        XCTAssertEqual(manager.testRecoveryAttempts, 3,
                       "Attempt counter is left at the max after exhaustion")
        XCTAssertTrue(manager.testRecoveryExhausted,
                      "Exhausted flag latches once max attempts are spent")
    }

    /// A rebuild that reports advancing on the very first attempt is the common
    /// wake case: one pass, no retry, state cleared.
    func testRecoverSucceedsOnFirstAttempt() async throws {
        let manager = makeManagerWithStalledVideo()

        let callCount = Locked<Int>(0)
        manager.testFreshRebuildVerifyHook = { _, _ in
            callCount.mutate { $0 += 1 }
            return true
        }

        await manager.testDriveBoundedRecovery(reason: "e2e-single-pass")

        XCTAssertEqual(callCount.value, 1, "A first-attempt success needs no retry")
        XCTAssertEqual(manager.testRecoveryAttempts, 0)
        XCTAssertFalse(manager.testRecoveryExhausted)
    }

    /// The concurrent-loop guard: a second drive while one is already running is
    /// ignored rather than starting a parallel recovery.
    func testConcurrentRecoveryIsIgnored() async throws {
        let manager = makeManagerWithStalledVideo()

        let callCount = Locked<Int>(0)
        manager.testFreshRebuildVerifyHook = { _, _ in
            callCount.mutate { $0 += 1 }
            try? await Task.sleep(for: .milliseconds(120))
            return true
        }

        async let first: Void = manager.testDriveBoundedRecovery(reason: "e2e-concurrent-a")
        async let second: Void = manager.testDriveBoundedRecovery(reason: "e2e-concurrent-b")
        _ = await (first, second)

        XCTAssertEqual(callCount.value, 1,
                       "Only one recovery loop runs; the concurrent trigger is dropped")
    }
}

/// Minimal lock so test closures can accumulate state across `await` hops
/// without tripping Swift concurrency capture rules.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { self.storage = value }
    var value: Value { lock.withLock { storage } }
    func mutate(_ body: (inout Value) -> Void) { lock.withLock { body(&storage) } }
}
