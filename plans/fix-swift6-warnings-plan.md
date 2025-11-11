## Plan: Fix Swift 6 Concurrency Warnings

This plan systematically addresses 30+ Swift 6 concurrency warnings across production and test files. The warnings fall into 5 categories, with production code (WallpaperManager.swift) prioritized. We'll use a phased approach to maintain test stability and ensure no regressions.

**Phases: 5**

---

## Phase 1: Fix Production Code Warnings (WallpaperManager.swift)

**Objective:** Fix the 3 Swift 6 warnings in `WallpaperManager.swift` to ensure production code is fully Swift 6 compliant.

**Files/Functions to Modify/Create:**
- `LiveWalls/WallpaperManager.swift` - Lines 136, 147, 1648
  - `attemptAutoStart()` method (lines 135-158)
  - `ensurePlaying()` method (line 1648)

**Tests to Write:**
- No new tests needed - verify existing tests pass after fixes
- Run: `./build.sh test` to validate WallpaperManager behavior

**Steps:**
1. **Fix Warning 1 (Line 136): Non-Sendable closure in `hasVideo` parameter**
   - Nest `MainActor.run` to properly isolate the closure
   - Change from: `hasVideo: { [weak self] in guard let self else { return false }; return await MainActor.run { self.currentVideo != nil && !self.videoFiles.isEmpty } }`
   - Change to: `hasVideo: { [weak self] in guard let self else { return false }; return await MainActor.run { [weak self] in guard let self else { return false }; return self.currentVideo != nil && !self.videoFiles.isEmpty } }`

2. **Fix Warning 2 (Line 147): Non-Sendable closure in `startAction` parameter**
   - Nest `MainActor.run` for proper closure isolation
   - Change from: `startAction: { [weak self] in await MainActor.run { guard let self else { return }; self.startWallpaperSafe() } }`
   - Change to: `startAction: { [weak self] in await MainActor.run { [weak self] in guard let self else { return }; self.startWallpaperSafe() } }`

3. **Fix Warning 3 (Line 1648): Unused value binding**
   - Replace optional binding with boolean test since `currentVideo` is not used in the guard scope
   - Change from: `guard let currentVideo = currentVideo else { appLogger.debug("ℹ️ No currentVideo disponible"); return }`
   - Change to: `guard currentVideo != nil else { appLogger.debug("ℹ️ No currentVideo disponible"); return }`

4. **Run all tests to verify no regressions**
   - Execute: `./build.sh test`
   - Ensure all 49 unit tests pass
   - Ensure all 8 UI tests pass

5. **Build and verify clean compilation**
   - Execute: `./build.sh build`
   - Verify no Swift 6 warnings remain in WallpaperManager.swift

---

## Phase 2: Fix Async XCTest Method Warnings

**Objective:** Replace deprecated `wait(for:timeout:)` calls with modern `await fulfillment(of:timeout:)` in async test functions.

**Files/Functions to Modify/Create:**
- `LiveWallsTests/StartupPerformanceTests.swift` - Lines 29, 77, 93
  - `testFullStartupDoesNotBlockMainThread()` (line 29)
  - `testNoMainThreadBlockingDuringAutoStart()` (line 77)
  - `testBackgroundTasksCompleteWithinTimeout()` (line 93)

**Tests to Write:**
- No new tests - this is refactoring existing tests
- Verify all 3 affected tests still pass

**Steps:**
1. **Fix Line 29 in `testFullStartupDoesNotBlockMainThread()`**
   - Replace: `wait(for: [ready], timeout: 1.0)`
   - With: `await fulfillment(of: [ready], timeout: 1.0)`

2. **Fix Line 77 in `testNoMainThreadBlockingDuringAutoStart()`**
   - Replace: `wait(for: [ready], timeout: 3.0)`
   - With: `await fulfillment(of: [ready], timeout: 3.0)`

3. **Fix Line 93 in `testBackgroundTasksCompleteWithinTimeout()`**
   - Replace: `wait(for: [exp], timeout: 1.0)`
   - With: `await fulfillment(of: [exp], timeout: 1.0)`

4. **Run unit tests to verify fixes**
   - Execute: `xcodebuild test -project LiveWalls.xcodeproj -scheme LiveWalls -only-testing:LiveWallsTests/StartupPerformanceTests`
   - Verify all tests in StartupPerformanceTests pass

---

## Phase 3: Fix Mutable Capture Warnings with Actor Pattern

**Objective:** Eliminate data races from mutable variable captures in `@Sendable` closures by using Swift actors for synchronization.

**Files/Functions to Modify/Create:**
- `LiveWallsTests/StartupPerformanceTests.swift` - Lines 58, 60
  - `testNoMainThreadBlockingDuringAutoStart()` method
- `LiveWallsTests/ScheduledHealthCheckManagerTests.swift` - Line 112
  - `testHealthChecksCanBeCancelled()` method

**Tests to Write:**
- No new tests - refactoring existing test implementations
- Verify the 2 affected tests still pass with correct behavior

**Steps:**
1. **Fix Lines 58, 60 in StartupPerformanceTests.swift**
   - Create a local `actor AttemptTracker` inside the test
   - Replace `var attempts = 0` with `let tracker = AttemptTracker()`
   - Change `attempts += 1` to `await tracker.increment()`
   - Change `return attempts > 1` to `return await tracker.shouldRetry()`
   - Ensure the actor provides thread-safe mutation

2. **Fix Line 112 in ScheduledHealthCheckManagerTests.swift**
   - Create a local `actor ExecutionCounter` inside `testHealthChecksCanBeCancelled()`
   - Replace `var executionCount = 0` with `let counter = ExecutionCounter()`
   - Change `executionCount += 1` to `await counter.increment()`
   - Update assertions to use `await counter.getCount()`

3. **Run affected tests**
   - Execute: `xcodebuild test -project LiveWalls.xcodeproj -scheme LiveWalls -only-testing:LiveWallsTests/StartupPerformanceTests/testNoMainThreadBlockingDuringAutoStart`
   - Execute: `xcodebuild test -project LiveWalls.xcodeproj -scheme LiveWalls -only-testing:LiveWallsTests/ScheduledHealthCheckManagerTests/testHealthChecksCanBeCancelled`
   - Verify both tests pass with proper synchronization

---

## Phase 4: Remove Thread.isMainThread Checks in Async Contexts

**Objective:** Eliminate use of `Thread.isMainThread` in async test functions, which is unavailable and unreliable in Swift 6 structured concurrency.

**Files/Functions to Modify/Create:**
- `LiveWallsTests/ScheduledHealthCheckManagerTests.swift` - Lines 38, 76
  - `testScheduledHealthChecksRunInBackground()` (line 38)
  - `testHealthCheckManagerDoesNotSaturateMainThread()` (line 76)
- `LiveWallsTests/PlaybackHealthCheckerTests.swift` - Lines 37, 49
  - `testCheckPlaybackHealthDoesNotBlockMainThread()` (lines 37, 49)

**Tests to Write:**
- No new tests - refactoring test logic
- Verify all 3 affected tests still validate their intended behavior

**Steps:**
1. **Fix Lines 38, 76 in ScheduledHealthCheckManagerTests.swift**
   - Remove `Thread.isMainThread` checks from `@Sendable` closures
   - Since closures are `@Sendable`, they execute off the main thread by definition
   - Simplify logic: count executions without thread checks
   - Update assertions to verify background execution by measuring timing/responsiveness

2. **Fix Lines 37, 49 in PlaybackHealthCheckerTests.swift**
   - Remove `let mainThreadBefore = Thread.isMainThread` (line 37)
   - Remove `let mainThreadDuring = Thread.isMainThread` (line 49)
   - Restructure test to verify responsiveness instead of thread identity
   - Measure async operation duration to ensure it doesn't block

3. **Run affected tests**
   - Execute: `xcodebuild test -project LiveWalls.xcodeproj -scheme LiveWalls -only-testing:LiveWallsTests/ScheduledHealthCheckManagerTests`
   - Execute: `xcodebuild test -project LiveWalls.xcodeproj -scheme LiveWalls -only-testing:LiveWallsTests/PlaybackHealthCheckerTests`
   - Verify tests pass and still validate concurrency behavior

---

## Phase 5: Fix Sendable Type Conversion Warnings in StartupCoordinatorTests

**Objective:** Resolve 9 warnings related to converting non-Sendable closures to `@Sendable` parameters by redesigning the `StartupCoordinator` signature to accept `@MainActor` closures.

**Files/Functions to Modify/Create:**
- `LiveWalls/StartupCoordinator.swift`
  - `coordinateStartup()` method signature
- `LiveWallsTests/StartupCoordinatorTests.swift` - Lines 29-41, 60-75, 97-112, 122-133
  - `testCoordinateStartupDoesNotBlockMainThread()` (lines 29-41)
  - `testRetriesMechanismRespectsMaxRetries()` (lines 60-75)
  - `testStartupFailsWhenVideoNeverAvailable()` (lines 97-112)
  - `testStartupSucceedsOnFirstAttemptWhenConditionsMet()` (lines 122-133)
- `LiveWalls/WallpaperManager.swift`
  - Update calls to `coordinateStartup()` to match new signature

**Tests to Write:**
- No new tests - updating existing tests to match new API
- Verify all StartupCoordinatorTests pass after refactor

**Steps:**
1. **Redesign StartupCoordinator.coordinateStartup() signature**
   - Change `hasVideo: @Sendable () async -> Bool` to `hasVideo: @MainActor () -> Bool`
   - Change `startAction: @Sendable () async -> Void` to `startAction: @MainActor () -> Void`
   - Keep `hasScreens: @Sendable () async -> Bool` as-is (no main thread requirement)
   - Rationale: Startup operations are inherently main-thread-bound (UI state checks)

2. **Update implementation in StartupCoordinator.swift**
   - Add `await MainActor.run` when calling `hasVideo()` and `startAction()`
   - Ensure proper isolation when executing main-actor-bound closures
   - No behavioral changes - only type safety improvements

3. **Update WallpaperManager.attemptAutoStart() call site**
   - Remove nested `MainActor.run` from closures (no longer needed)
   - Simplify closure implementations since `@MainActor` is expected
   - Verify logic remains identical

4. **Update all 4 test methods in StartupCoordinatorTests.swift**
   - Remove `@Sendable` annotations from test closures
   - Closures can now freely capture mutable state and use `@MainActor`
   - No type conversion warnings should remain

5. **Run all StartupCoordinator tests**
   - Execute: `xcodebuild test -project LiveWalls.xcodeproj -scheme LiveWalls -only-testing:LiveWallsTests/StartupCoordinatorTests`
   - Verify all tests pass

6. **Run full test suite to catch any regressions**
   - Execute: `./build.sh test`
   - Ensure all 49 unit tests + 8 UI tests still pass

---

## Open Questions

1. **StartupCoordinator design intent:** Should we keep `@MainActor` signature permanently, or is there a use case for generic `@Sendable` closures? 
   - **Recommendation:** Keep `@MainActor` - startup is always UI-bound in LiveWalls
   
2. **WallpaperManagerTests unused await warnings:** Should we add `let _ =` to all fire-and-forget async calls?
   - **Recommendation:** Yes, for clarity and to suppress warnings

3. **Testing thread safety:** After removing `Thread.isMainThread` checks, how do we verify tests actually run in background?
   - **Recommendation:** Use timing/responsiveness checks or explicit actor isolation verification

4. **Future Swift 6 strictness:** Should we enable complete concurrency checking (`-strict-concurrency=complete`) after these fixes?
   - **Recommendation:** Yes, to future-proof the codebase

5. **Documentation:** Should we add comments explaining the `@MainActor` vs `@Sendable` design choices?
   - **Recommendation:** Yes, especially in StartupCoordinator for maintainability
