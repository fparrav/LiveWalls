import XCTest
import AVFoundation
@testable import LiveWalls

/// Task 2.9 / 3.2 — display-scoped fresh rebuild: a stall confined to a subset
/// of displays rebuilds only those windows and leaves the healthy displays'
/// pipelines untouched.
///
/// The scope decision (`WallpaperManager.resolveRebuildScope`) is a pure
/// function and is tested directly. The end-to-end wiring is driven headlessly
/// through the DEBUG seams (`testStalledDisplayIDsOverride`,
/// `testLiveDisplayIDsOverride`, `testFreshRebuildVerifyHook`,
/// `testRebuildTargetsSeen`) because real multi-display window creation and the
/// first-frame render probe cannot run without attached displays.
@MainActor
final class RecoveryPerDisplayTests: XCTestCase {

    override func tearDown() {
        RecoveryDebugFlags.resetAllKillSwitches()
        super.tearDown()
    }

    // MARK: - resolveRebuildScope (pure)

    func testScopeIsTheStrictSubsetWhenBothFlagsOn() {
        let scope = WallpaperManager.resolveRebuildScope(
            requested: [2],
            liveDisplays: [1, 2, 3],
            perDisplayEnabled: true,
            refCountEnabled: true
        )
        XCTAssertEqual(scope, [2])
    }

    func testScopeClampsRequestToLiveDisplays() {
        // Display 9 is not attached any more; only 2 survives the intersection.
        let scope = WallpaperManager.resolveRebuildScope(
            requested: [2, 9],
            liveDisplays: [1, 2, 3],
            perDisplayEnabled: true,
            refCountEnabled: true
        )
        XCTAssertEqual(scope, [2])
    }

    func testNilRequestMeansGlobal() {
        XCTAssertNil(WallpaperManager.resolveRebuildScope(
            requested: nil, liveDisplays: [1, 2], perDisplayEnabled: true, refCountEnabled: true))
    }

    func testEmptyRequestMeansGlobal() {
        XCTAssertNil(WallpaperManager.resolveRebuildScope(
            requested: [], liveDisplays: [1, 2], perDisplayEnabled: true, refCountEnabled: true))
    }

    func testRequestCoveringEveryLiveDisplayMeansGlobal() {
        XCTAssertNil(WallpaperManager.resolveRebuildScope(
            requested: [1, 2], liveDisplays: [1, 2], perDisplayEnabled: true, refCountEnabled: true))
    }

    func testRequestDisjointFromLiveDisplaysMeansGlobal() {
        XCTAssertNil(WallpaperManager.resolveRebuildScope(
            requested: [7, 8], liveDisplays: [1, 2], perDisplayEnabled: true, refCountEnabled: true))
    }

    func testPerDisplayFlagOffMeansGlobal() {
        XCTAssertNil(WallpaperManager.resolveRebuildScope(
            requested: [2], liveDisplays: [1, 2, 3], perDisplayEnabled: false, refCountEnabled: true))
    }

    func testRefCountFlagOffMeansGlobal() {
        XCTAssertNil(WallpaperManager.resolveRebuildScope(
            requested: [2], liveDisplays: [1, 2, 3], perDisplayEnabled: true, refCountEnabled: false))
    }

    // MARK: - End-to-end wiring through the bounded-recovery loop

    private func makeManager() -> WallpaperManager {
        let manager = WallpaperManager(loadPersistedData: false)
        manager.currentVideo = VideoFile(
            url: URL(fileURLWithPath: "/tmp/per-display-dummy.mp4"),
            name: "Per-Display Dummy",
            bookmarkData: Data()
        )
        manager.testRecoveryBackoffOverride = [.zero, .zero, .zero]
        return manager
    }

    func testStallConfinedToOneDisplayRebuildsOnlyThatDisplay() async {
        let manager = makeManager()
        manager.testLiveDisplayIDsOverride = [1, 2, 3]
        manager.testStalledDisplayIDsOverride = [2]

        let hookCalls = Locked<Int>(0)
        manager.testFreshRebuildVerifyHook = { _, _ in
            hookCalls.mutate { $0 += 1 }
            return true // rebuilt display advances immediately
        }

        await manager.testDriveBoundedRecovery(reason: "health-check-unhealthy")

        XCTAssertEqual(hookCalls.value, 1, "One attempt is enough once the rebuilt display advances")
        XCTAssertEqual(manager.testRebuildTargetsSeen, [Set<CGDirectDisplayID>([2])],
                       "Recovery rebuilds only the stalled display, not displays 1 and 3")
        XCTAssertEqual(manager.testRecoveryAttempts, 0)
        XCTAssertFalse(manager.testRecoveryExhausted)
    }

    func testNoSubsetStalledFallsBackToGlobalRebuild() async {
        let manager = makeManager()
        manager.testLiveDisplayIDsOverride = [1, 2, 3]
        manager.testStalledDisplayIDsOverride = [] // aggregate stall with no per-display attribution

        manager.testFreshRebuildVerifyHook = { _, _ in true }
        await manager.testDriveBoundedRecovery(reason: "health-check-unhealthy")

        XCTAssertEqual(manager.testRebuildTargetsSeen, [nil],
                       "With no stalled subset, recovery rebuilds every display")
    }

    func testEveryDisplayStalledFallsBackToGlobalRebuild() async {
        let manager = makeManager()
        manager.testLiveDisplayIDsOverride = [1, 2]
        manager.testStalledDisplayIDsOverride = [1, 2]

        manager.testFreshRebuildVerifyHook = { _, _ in true }
        await manager.testDriveBoundedRecovery(reason: "health-check-unhealthy")

        XCTAssertEqual(manager.testRebuildTargetsSeen, [nil],
                       "When all displays stalled, a global rebuild is used")
    }

    func testPerDisplayKillSwitchOffForcesGlobalRebuild() async {
        RecoveryDebugFlags.perDisplayRecovery = false
        defer { RecoveryDebugFlags.resetAllKillSwitches() }

        let manager = makeManager()
        manager.testLiveDisplayIDsOverride = [1, 2, 3]
        manager.testStalledDisplayIDsOverride = [2]

        manager.testFreshRebuildVerifyHook = { _, _ in true }
        await manager.testDriveBoundedRecovery(reason: "health-check-unhealthy")

        XCTAssertEqual(manager.testRebuildTargetsSeen, [nil],
                       "perDisplayRecovery off ⇒ always rebuild every display")
    }

    func testBookmarkRefCountKillSwitchOffForcesGlobalRebuild() async {
        RecoveryDebugFlags.bookmarkRefCount = false
        defer { RecoveryDebugFlags.resetAllKillSwitches() }

        let manager = makeManager()
        manager.testLiveDisplayIDsOverride = [1, 2, 3]
        manager.testStalledDisplayIDsOverride = [2]

        manager.testFreshRebuildVerifyHook = { _, _ in true }
        await manager.testDriveBoundedRecovery(reason: "health-check-unhealthy")

        XCTAssertEqual(manager.testRebuildTargetsSeen, [nil],
                       "The scoped path needs ref-counting; without it, recovery stays global")
    }

    func testScopedRebuildRetriesTheSameDisplaySet() async {
        let manager = makeManager()
        manager.testLiveDisplayIDsOverride = [1, 2, 3]
        manager.testStalledDisplayIDsOverride = [3]

        let attempts = Locked<Int>(0)
        manager.testFreshRebuildVerifyHook = { _, _ in
            attempts.mutate { $0 += 1 }
            return attempts.value >= 2 // fails attempt 1, advances on attempt 2
        }

        await manager.testDriveBoundedRecovery(reason: "health-check-unhealthy")

        XCTAssertEqual(manager.testRebuildTargetsSeen,
                       [Set<CGDirectDisplayID>([3]), Set<CGDirectDisplayID>([3])],
                       "Both attempts target the same stalled display")
        XCTAssertEqual(manager.testRecoveryAttempts, 0)
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
