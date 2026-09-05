import XCTest
import AVFoundation
@testable import LiveWalls

/// Task 3.3 — recovery must not freeze the UI, and the slow static-image apply
/// must run off the main queue.
///
/// Part A asserts the `NSWorkspace.setDesktopImageURL` loop inside
/// `setSystemStaticWallpaper` runs off the main thread when `staticApplyOffMain`
/// is enabled (and on it when the kill-switch is off), via the DEBUG-only
/// `testStaticApplyProbe` seam — which also short-circuits the real system call
/// so the test never touches the host's desktop.
///
/// Part B is the headless equivalent of "the status-bar panel opens and its
/// controls respond during and after a recovery": while `attemptBoundedRecovery`
/// is parked mid-rebuild (holding the wallpaper exclusive lock), lock-free
/// `@MainActor` operations on the same manager still complete — the main actor
/// is never monopolized.
@MainActor
final class RecoveryUIResponsivenessTests: XCTestCase {

    override func tearDown() {
        RecoveryDebugFlags.resetAllKillSwitches()
        super.tearDown()
    }

    // MARK: - Part A: static-image apply is off the main queue

    private func makeStaticImageFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("static-apply-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        return url
    }

    func testStaticApplyRunsOffMainThreadWhenFlagEnabled() async {
        RecoveryDebugFlags.staticApplyOffMain = true

        let manager = WallpaperManager(loadPersistedData: false)
        let onMain = Locked<Bool?>(nil)
        manager.testStaticApplyProbe = { isMain in
            onMain.mutate { $0 = isMain }
            return true // skip the real NSWorkspace.setDesktopImageURL call
        }

        let image = makeStaticImageFile()
        defer { try? FileManager.default.removeItem(at: image) }

        let ok = await manager.testApplyStaticWallpaper(imageURL: image)

        XCTAssertTrue(ok)
        XCTAssertEqual(onMain.value, false,
                       "El loop de setDesktopImageURL debe correr fuera del main thread (design D7)")
    }

    func testStaticApplyRunsOnMainThreadWhenKillSwitchOff() async {
        RecoveryDebugFlags.staticApplyOffMain = false

        let manager = WallpaperManager(loadPersistedData: false)
        let onMain = Locked<Bool?>(nil)
        manager.testStaticApplyProbe = { isMain in
            onMain.mutate { $0 = isMain }
            return true
        }

        let image = makeStaticImageFile()
        defer { try? FileManager.default.removeItem(at: image) }

        let ok = await manager.testApplyStaticWallpaper(imageURL: image)

        XCTAssertTrue(ok)
        XCTAssertEqual(onMain.value, true,
                       "Con staticApplyOffMain apagado, el loop corre en el main thread (comportamiento legacy)")
    }

    // MARK: - Part B: the main actor stays responsive during (and after) recovery

    private func makeManager() -> WallpaperManager {
        let manager = WallpaperManager(loadPersistedData: false)
        manager.currentVideo = VideoFile(
            url: URL(fileURLWithPath: "/tmp/ui-responsiveness-dummy.mp4"),
            name: "UI Responsiveness Dummy",
            bookmarkData: Data()
        )
        manager.testRecoveryBackoffOverride = [.zero, .zero, .zero]
        return manager
    }

    private func enabledVideos(_ count: Int) -> [VideoFile] {
        (1...count).map { i in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ui-resp-\(UUID().uuidString)-\(i).mp4")
            FileManager.default.createFile(atPath: url.path, contents: Data("d\(i)".utf8))
            return VideoFile(url: url, name: "Video \(i)", isEnabledForRandomPlay: true)
        }
    }

    func testMainActorServesLockFreeWorkWhileRecoveryIsInFlight() async {
        let manager = makeManager()
        manager.videoFiles = enabledVideos(6)
        manager.isShuffleMode = true

        let rebuildParked = expectation(description: "rebuild hook reached")
        let release = Locked<Bool>(false)

        manager.testFreshRebuildVerifyHook = { _, _ in
            rebuildParked.fulfill()
            while !release.value {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return true // rebuilt clip advances once released
        }

        // Kick off recovery without awaiting it — it will park inside the hook
        // while holding the wallpaper exclusive lock.
        let recovery = Task { await manager.testDriveBoundedRecovery(reason: "health-check-unhealthy") }
        await fulfillment(of: [rebuildParked], timeout: 2.0)

        // DURING recovery: a lock-free @MainActor operation still completes.
        XCTAssertFalse(manager.testRecoveryExhausted, "Recovery sigue en progreso")
        let pickedDuring = await manager.getNextVideoInShuffleMode()
        XCTAssertNotNil(pickedDuring,
                        "Una operación @MainActor responde mientras el recovery está en curso")

        // Published state the status bar binds to is still readable/mutable.
        manager.isShuffleMode = false
        XCTAssertFalse(manager.isShuffleMode)

        // Let the rebuild finish.
        release.mutate { $0 = true }
        await recovery.value

        // AFTER recovery: operations still work and recovery reports success.
        XCTAssertEqual(manager.testRecoveryAttempts, 0)
        XCTAssertFalse(manager.testRecoveryExhausted)
        manager.isShuffleMode = true
        let pickedAfter = await manager.getNextVideoInShuffleMode()
        XCTAssertNotNil(pickedAfter, "Las operaciones siguen respondiendo después del recovery")
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
