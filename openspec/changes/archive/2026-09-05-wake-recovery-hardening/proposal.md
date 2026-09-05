## Why

After running LiveWalls for a long session, then suspending the Mac for many minutes/hours and waking it, the desktop video can freeze to a single static frame and — more seriously — **the status-bar controls stop responding, and manually selecting a new video no longer works.** The only recovery is to kill and relaunch the app.

Investigation of the source tree and the unified log shows this is not (only) a video-pausing problem; it is a **failure of the app's own wake/recovery machinery.** The app already has a wake recovery (`didWake` does a full teardown + rebuild), but (1) its health check is *blind* to the actual broken thing — it judges "playing" from decoder `timeControlStatus`/`rate` rather than from whether rendered output is advancing, so a stalled-but-not-failed player is declared "healthy"; (2) the recovery path is gated by concurrency booleans (`isEnsurePlayingRunning`, `isChangingVideo`, `isTransitioning`) that have **no timeout and can latch**, silently no-op'ing every later `start`/`change`/`set` action; and (3) there is **no real serialization** of window rebuilds (`withExclusiveAccess` is a no-op), and the wake rebuild bypasses it and races other rebuild paths, which can desync security-scoped resource accounting. Finally, because LiveWalls logs almost everything at `.info`/`.debug`, **the freeze left no retrievable trail**, so today's fix is being designed blind.

This change makes the self-heal actually work after wake/stalls, keeps the UI responsive, and makes the next freeze **observable and reproducible-on-demand** so the fix can be validated without a multi-day session.

## What Changes

- **Render-advance-based health detection.** Playback "health" (and the decision to recover) is judged by whether the rendered stream is actually *advancing over time* (a monotonic `currentTime()`/frame-advance probe), not merely by decoder `timeControlStatus == .playing` / `rate > 0`. A confirmed render-stall triggers recovery.
- **Wake-triggered full recovery.** After a system wake (and on a detected stall), the app restores live playback on every display by fully rebuilding the pipeline including a freshly-attached video layer, re-asserting window level/order, and re-establishing security-scoped access — without a user relaunch.
- **Bounded, non-latching recovery.** Recovery gates can never stay latched: each gated operation has a timeout and a guaranteed release (via `defer`/actor), and a stuck recovery times out and retries.
- **Serialized window rebuilds.** Concurrent window rebuild operations are mutually exclusive through a real exclusive-access mechanism; the wake path is routed through it instead of bypassing it.
- **Balanced security-scoped access.** Security-scoped `start/stop` accounting cannot desync across racy rebuilds; a rebuild rebalances access to a known-clean state.
- **UI responsiveness during recovery.** Status-bar and main-window controls remain responsive throughout and after a recovery attempt; slow system calls used in recovery (e.g. `NSWorkspace.setDesktopImageURL`) are offloaded off the main queue.
- **Durable recovery telemetry.** The suspend → wake → recover → verify lifecycle is recorded durably (to a file that survives log eviction) and at a retained log level, so a freeze is diagnosable after the fact.
- **Deterministic wake-stall simulation (debug/testing).** A gated, off-by-default test hook reproduces the post-wake render-stall state on demand, so the recovery can be proven and regression-tested without a real long suspend.

No user-facing behavioral *regression* is intended; the observable improvement is that the previously-frozen UI and video recover automatically. The added telemetry and debug simulation are guarded/off by default and are not part of normal user-facing behavior.

## Capabilities

### New Capabilities

- `playback-recovery`: Automatic restoration of live wallpaper playback after a system suspend/wake and after a detected render-stall, with bounded (non-latching) recovery, serialized and race-safe window rebuilds, balanced security-scoped resource access, and continuous responsiveness of the status-bar/main-window UI throughout recovery.
- `recovery-observability`: Durable, retained-level telemetry for the suspend → wake → recover → verify lifecycle, plus a deterministic, off-by-default wake-stall simulation that reproduces the post-wake render-stall for testing and regression guard.

### Modified Capabilities

<!-- None. The only existing spec (`liquid-glass-ui`) is UI-styling and its requirements are unchanged by this change. Playback/wake behavior has no existing spec, so all of the above are new capabilities. -->

## Impact

- **Code** (under `LiveWalls/`):
    - `WallpaperManager.swift` — wake handling (`willSleep`/`didWake`), the recovery gate (`isEnsurePlayingRunning`), video-change gates (`isChangingVideo`/`isTransitioning`), the `WallpaperOperationActor.withExclusiveAccess` serialization, and the static-frame `NSWorkspace.setDesktopImageURL` dispatch.
    - `PlaybackHealthChecker.swift` — health judgment switched to a render-advance probe.
    - `DesktopVideoWindowMejorada.swift` — expose a render-advance probe and a fresh-layer re-attach for full rebuild.
    - `WindowCreationCoordinator.swift`, `VideoPreloader.swift`, `ScheduledHealthCheckManager.swift` — participation in serialized, probe-based recovery.
    - `BookmarkActor.swift` — security-scoped access rebalancing.
    - A new small diagnostics/telemetry module (file writer + retained-level logger) and a debug simulation hook.
- **Dependencies / systems:** macOS `NSWorkspace` sleep/wake notifications, AVFoundation `AVQueuePlayer`/`AVPlayer`/`AVPlayerLooper` + `AVPlayerLayer` rendering, security-scoped resource access. No new third-party dependencies.
- **Acceptance / risk:** The highest-value, lowest-risk increment is the **observability + render-advance probe**, which alone makes a real freeze diagnosable; the **self-heal** increments (serialization, gate timeouts, security-scoped rebalance, off-main dispatch) are the actual fix. The deterministic simulation is the regression guard. Behavior must remain a no-op when there is no stall.
