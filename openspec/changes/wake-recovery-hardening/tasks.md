# Tasks: wake-recovery-hardening

Ordered by delivery phase (A → B → C). Phase A is independently shippable and de-risks the rest. Each increment is behind a debug-default flag that can be disabled (see design.md §D9), so a regression rolls back without a relaunch.

## 1. Phase A — Observability & render-advance probe (low risk, land first)

- [x] 1.1 Add a durable recovery-lifecycle telemetry writer: append one compact entry per stage (suspend, wake, recover-attempted, recover-outcome, verify-result) to a rolling file in the app container that survives unified-log eviction.
- [x] 1.2 Record `willSleep` and `didWake` as telemetry markers (suspend-observed / wake-observed).
- [x] 1.3 Emit the recover-decision and its outcome at a retained log level (`.error`/`.fault`) in addition to the existing `.info`/`.debug` logs.
- [x] 1.4 Implement the render-advance probe (design D1): a periodic (~2–3 s) sample, active only when playback is expected (wallpaper active, not user-paused, not full-screen-paused); classify "advancing" on a forward playhead advance OR a loop-wrap, and "stalled" only after N periods with no advance/wrap.
- [x] 1.5 Expose the probe result as an observable signal and feed it into the telemetry store.
- [x] 1.6 Add the off-by-default deterministic stall hook (design D8/3): a gated/test-enabled path that forces a static frame while the decoder reports healthy, and can be enabled, observed, and cleared programmatically; verify it is inert when off.
- [x] 1.7 Unit tests: probe classifies advance, loop-wrap, and stall correctly; the deterministic hook forces a recover path when enabled and a no-op when off.

## 2. Phase B — Self-heal correctness (the actual fix)

- [x] 2.1 Make `WallpaperOperationActor.withExclusiveAccess` a real async mutex with a timeout and guaranteed release (design D4), replacing the no-op.
- [x] 2.2 Route all rebuild triggers through the exclusive lock: `didWake`, `didBecomeActive`, `activeSpaceDidChange`, the scheduled health checks, and manual changes; remove `didWake`'s bypass of the actor.
- [x] 2.3 Replace the latching boolean gates (`isEnsurePlayingRunning`, `isChangingVideo`, `isTransitioning`) with a guarded operation that always releases on every exit path with a timeout; queue user video-changes that arrive during a recovery instead of silently dropping them (design D5).
- [x] 2.4 Switch the health check to the probe-based judgment from 1.4 (design D2), with a bounded, escalating retry policy that stops and logs after the attempts are exhausted.
- [x] 2.5 On a confirmed stall or wake, perform a full fresh rebuild (design D3): new `AVQueuePlayer` + `AVPlayerLooper` + freshly attached `AVPlayerLayer`, then `orderOut → orderFront → orderBack` + a brief settle + a first-frame probe before declaring success; retry sparingly and ensure no stale frozen window remains stacked on any display.
- [ ] 2.6 Make `BookmarkActor` the single source of truth for security-scoped access with per-URL ref-counting, a `reconcile()` that runs once at start of a rebuild, and a fixed `stopAllSecurityScopedAccess` that uses the resolved URL directly instead of `URL(string:)` (design D6).
- [ ] 2.7 Offload the slow static-image apply (`NSWorkspace.setDesktopImageURL`) and any other long synchronous system calls invoked by recovery off the main queue (design D7).
- [ ] 2.8 Add per-increment debug flags / a kill-switch with sane defaults so each increment rolls back independently without a relaunch.

## 3. Phase C — Validation & regression

- [ ] 3.1 End-to-end test using the deterministic hook: drive a full recover → verify cycle in CI without a long suspend, asserting advancing output after recovery.
- [ ] 3.2 Multi-display test: when one display is stalled, that display recovers independently and others are unaffected.
- [ ] 3.3 UI-responsiveness test: the status-bar panel opens and its controls respond during and after a simulated recovery; assert the static-image apply is off the main queue.
- [ ] 3.4 No-effect-when-healthy test: an advancing video triggers no rebuild, no static-apply, and no per-frame telemetry writes.
- [ ] 3.5 Field validation on the target device (macOS 26.6): confirm the durable telemetry captures the next real freeze and that the wrap-detection signal is correct, or switch the probe to the pixel-diff fallback (design D1 open question).

## 4. Hardening & docs

- [ ] 4.1 Update `AGENTS.md` "Recent Performance Improvements" with the new recovery/observability components and the recovery flags.
- [ ] 4.2 Review/extend localized strings (10 languages) for any new user-facing or log-only messages; add none if all changes are internal.
- [ ] 4.3 Run the full suite (`./build.sh test`) and confirm CI green before merging.
