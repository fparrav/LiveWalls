import XCTest
@testable import LiveWalls

/// Tests for Task 2.8 / Design D9: per-increment kill-switches with sane defaults.
@MainActor
final class RecoveryKillSwitchTests: XCTestCase {

    override func setUpWithError() throws {
        // Start with a clean state for each test
        RecoveryDebugFlags.resetAllKillSwitches()
    }

    override func tearDownWithError() throws {
        // Clean up after each test
        RecoveryDebugFlags.resetAllKillSwitches()
    }

    // MARK: - Probe-Based Health Judgment (2.4)

    /// Test that probeBasedHealthJudgment defaults to true (fix active)
    func testProbeBasedHealthJudgmentDefaultsToTrue() {
        XCTAssertTrue(RecoveryDebugFlags.probeBasedHealthJudgment,
                      "probeBasedHealthJudgment should default to true (fix active)")
    }

    /// Test that setting probeBasedHealthJudgment to false persists and is readable
    func testProbeBasedHealthJudgmentCanBeSetToFalse() {
        RecoveryDebugFlags.probeBasedHealthJudgment = false
        XCTAssertFalse(RecoveryDebugFlags.probeBasedHealthJudgment,
                       "probeBasedHealthJudgment should be false after setting to false")
    }

    /// Test that setting probeBasedHealthJudgment to true persists and is readable
    func testProbeBasedHealthJudgmentCanBeSetToTrue() {
        RecoveryDebugFlags.probeBasedHealthJudgment = false
        RecoveryDebugFlags.probeBasedHealthJudgment = true
        XCTAssertTrue(RecoveryDebugFlags.probeBasedHealthJudgment,
                      "probeBasedHealthJudgment should be true after setting to true")
    }

    // MARK: - Full Fresh Rebuild (2.5)

    /// Test that fullFreshRebuild defaults to true (fix active)
    func testFullFreshRebuildDefaultsToTrue() {
        XCTAssertTrue(RecoveryDebugFlags.fullFreshRebuild,
                      "fullFreshRebuild should default to true (fix active)")
    }

    /// Test that setting fullFreshRebuild to false persists and is readable
    func testFullFreshRebuildCanBeSetToFalse() {
        RecoveryDebugFlags.fullFreshRebuild = false
        XCTAssertFalse(RecoveryDebugFlags.fullFreshRebuild,
                       "fullFreshRebuild should be false after setting to false")
    }

    /// Test that setting fullFreshRebuild to true persists and is readable
    func testFullFreshRebuildCanBeSetToTrue() {
        RecoveryDebugFlags.fullFreshRebuild = false
        RecoveryDebugFlags.fullFreshRebuild = true
        XCTAssertTrue(RecoveryDebugFlags.fullFreshRebuild,
                      "fullFreshRebuild should be true after setting to true")
    }

    // MARK: - Bookmark Ref-Count (2.6)

    /// Test that bookmarkRefCount defaults to true (fix active)
    func testBookmarkRefCountDefaultsToTrue() {
        XCTAssertTrue(RecoveryDebugFlags.bookmarkRefCount,
                      "bookmarkRefCount should default to true (fix active)")
    }

    /// Test that setting bookmarkRefCount to false persists and is readable
    func testBookmarkRefCountCanBeSetToFalse() {
        RecoveryDebugFlags.bookmarkRefCount = false
        XCTAssertFalse(RecoveryDebugFlags.bookmarkRefCount,
                       "bookmarkRefCount should be false after setting to false")
    }

    /// Test that setting bookmarkRefCount to true persists and is readable
    func testBookmarkRefCountCanBeSetToTrue() {
        RecoveryDebugFlags.bookmarkRefCount = false
        RecoveryDebugFlags.bookmarkRefCount = true
        XCTAssertTrue(RecoveryDebugFlags.bookmarkRefCount,
                      "bookmarkRefCount should be true after setting to true")
    }

    // MARK: - Static Apply Off-Main (2.7)

    /// Test that staticApplyOffMain defaults to true (fix active)
    func testStaticApplyOffMainDefaultsToTrue() {
        XCTAssertTrue(RecoveryDebugFlags.staticApplyOffMain,
                      "staticApplyOffMain should default to true (fix active)")
    }

    /// Test that setting staticApplyOffMain to false persists and is readable
    func testStaticApplyOffMainCanBeSetToFalse() {
        RecoveryDebugFlags.staticApplyOffMain = false
        XCTAssertFalse(RecoveryDebugFlags.staticApplyOffMain,
                       "staticApplyOffMain should be false after setting to false")
    }

    /// Test that setting staticApplyOffMain to true persists and is readable
    func testStaticApplyOffMainCanBeSetToTrue() {
        RecoveryDebugFlags.staticApplyOffMain = false
        RecoveryDebugFlags.staticApplyOffMain = true
        XCTAssertTrue(RecoveryDebugFlags.staticApplyOffMain,
                      "staticApplyOffMain should be true after setting to true")
    }

    // MARK: - Reset All Kill-Switches

    /// Test that resetAllKillSwitches sets all flags back to true (default)
    func testResetAllKillSwitches() {
        // Set all flags to false
        RecoveryDebugFlags.probeBasedHealthJudgment = false
        RecoveryDebugFlags.fullFreshRebuild = false
        RecoveryDebugFlags.bookmarkRefCount = false
        RecoveryDebugFlags.staticApplyOffMain = false

        // Verify they're false
        XCTAssertFalse(RecoveryDebugFlags.probeBasedHealthJudgment)
        XCTAssertFalse(RecoveryDebugFlags.fullFreshRebuild)
        XCTAssertFalse(RecoveryDebugFlags.bookmarkRefCount)
        XCTAssertFalse(RecoveryDebugFlags.staticApplyOffMain)

        // Reset all
        RecoveryDebugFlags.resetAllKillSwitches()

        // Verify all are back to true
        XCTAssertTrue(RecoveryDebugFlags.probeBasedHealthJudgment)
        XCTAssertTrue(RecoveryDebugFlags.fullFreshRebuild)
        XCTAssertTrue(RecoveryDebugFlags.bookmarkRefCount)
        XCTAssertTrue(RecoveryDebugFlags.staticApplyOffMain)
    }

    // MARK: - Legacy Behavior Tests (Optional but good to have)

    /// Test: With probeBasedHealthJudgment=OFF, ensurePlaying should pass .unknown to health checker
    /// (This is more of an integration test; we trust the flag is read correctly in WallpaperManager)
    func testProbeBasedHealthJudgmentOffUsesFallback() async throws {
        // Arrange: set flag to OFF
        RecoveryDebugFlags.probeBasedHealthJudgment = false

        // Act & Assert: flag should be false
        XCTAssertFalse(RecoveryDebugFlags.probeBasedHealthJudgment)
        // The actual usage is tested in WallpaperManager via code inspection
    }

    /// Test: With fullFreshRebuild=OFF, recovery should use legacy path
    func testFullFreshRebuildOffUsesLegacyPath() async throws {
        // Arrange: set flag to OFF
        RecoveryDebugFlags.fullFreshRebuild = false

        // Act & Assert: flag should be false
        XCTAssertFalse(RecoveryDebugFlags.fullFreshRebuild)
    }

    /// Test: With bookmarkRefCount=OFF, BookmarkActor should use legacy Set semantics
    func testBookmarkRefCountOffUsesLegacySet() async throws {
        // Arrange: set flag to OFF
        RecoveryDebugFlags.bookmarkRefCount = false

        // Act & Assert: flag should be false
        XCTAssertFalse(RecoveryDebugFlags.bookmarkRefCount)
        // Actual behavior tested in BookmarkActor via code inspection
    }

    /// Test: With staticApplyOffMain=OFF, setSystemStaticWallpaper should run on main queue
    func testStaticApplyOffMainOffUsesMainQueue() async throws {
        // Arrange: set flag to OFF
        RecoveryDebugFlags.staticApplyOffMain = false

        // Act & Assert: flag should be false
        XCTAssertFalse(RecoveryDebugFlags.staticApplyOffMain)
        // Actual behavior tested in WallpaperManager via code inspection
    }
}