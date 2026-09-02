## Context

See `proposal.md` (§Why/§What Changes) for motivation. This document describes *how* to make the change.

Today the recovery machinery exists but cannot observe the thing that actually breaks and can get itself stuck. The relevant current state, as traced in the source tree:

- `WallpaperManager.didWake` performs a full teardown + rebuild of the desktop windows when `isPlayingWallpaper` is true, but it **bypasses** the `WallpaperOperationActor` and races several other rebuild triggers (`didBecomeActive`, `activeSpaceDidChange`, and the scheduled health checks at 1/5/15/120 s).
- `WallpaperOperationActor.withExclusiveAccess` is defined as `return try await operation()` — i.e., it provides **no mutual exclusion**. So rebuilds interleave.
- `ensurePlaying`/`changeToNextVideo`/`changeToNextVideoWithTransition` gate on booleans (`isEnsurePlayingRunning`, `isChangingVideo`, `isTransitioning`). `ensurePlaying`'s gate is released inside a spawned `Task { @MainActor … }` with **no timeout**, so if that task is delayed it latches and later requests silently no-op.
- `PlaybackHealthChecker.checkPlaybackHealth` judges "playing" from decoder `timeControlStatus == .playing` / `rate > 0`, **not** from whether rendered output advances. A stalled-but-not-failed player is declared healthy, so recovery is never triggered.
- Security-scoped access accounting in `BookmarkActor` guards by path string with a "skip stop if not in set" rule, and `stopAllSecurityScopedAccess` reconstructs URLs via `URL(string:)` (unescaped) — both can desync after a racy rebuild.
- `startWallpaperSafe` generates the static fallback frame on a detached task and applies it via `NSWorkspace.setDesktopImageURL` **on the main queue** (`DispatchQueue.main.async`); that call is synchronous and slow, and in the wake cascade it can starve the main run loop, which would freeze the `MenuBarExtra(.window)` panel (a plausible contributor to "controls don't respond").
- The app logs almost everything at `.info`/`.debug`; those levels are evicted from the queryable unified log, so a real freeze left **no trail**.

Constraints: must remain a no-op when playback is healthy; must not add per-frame cost; must keep the UI responsive; must not leave multiple frozen windows stacked; must keep the existing single-spec (`liquid-glass-ui`) untouched.

## Goals / Non-Goals

**Goals:**
- A render-advancement signal that is true for "visibly advancing" and false for "stalled," including the stalled-but-decoder-playing case, and that does not false-positive on an expected pause.
- A recovery that is bounded, non-latching, serialized, and race-safe, and that re-establishes a *fresh* rendering pipeline (fresh `AVQueuePlayer`/`AVPlayerLooper`/`AVPlayerLayer`) with correct window order, plus balanced security-scoped access.
- UI responsiveness preserved throughout recovery (no main-run-loop starvation).
- Durable, retained-level telemetry for the suspend→wake→recover→verify lifecycle, plus an off-by-default deterministic stall hook for testing.
- Phased delivery so the observability first de-risks the self-heal, and each increment is independently shippable and rollback-able.

**Non-Goals:**
- Not a redesign of the video selection/shuffle logic or the `liquid-glass-ui` visuals.
- Not a change to *when* or *at what interval* normal auto-change rotation fires.
- Not a move off AVFoundation or off `AVPlayerLooper`.
- Not per-frame pixel sampling in the hot path (the probe is periodic and lightweight).

## Decisions

### D1 — Render-advance probe based on playhead "advance-or-wrap", sampled periodically
Decision: a single probe, invoked on a fixed period (≈2–3 s) **only when playback is expected** (wallpaper active, not user-paused, not full-screen-paused), that decides "advancing" if and only if either (a) the item's playhead advanced forward since the last sample **or** (b) it *wrapped* (decreased), which with `AVPlayerLooper` indicates a loop restart occurred — both are progress. A genuine stall = no advance and no wrap for N periods. This is loop-safe without re-introducing the removed end-of-item observer.

Rationale: measures the *output* (progress of the displayed position), which is the actual failure mode, not the decoder's self-reported status. It correctly flags the "decoder says playing but pixels are frozen" case.

Alternatives considered:
- *CADisplayLink / rendered-frame diff*: most direct, but per-frame or even periodic pixel diff on `AVPlayerLayer` is expensive and can itself be the thing that breaks after wake — rejected as the primary; kept as a fallback only if playhead-based detection proves insufficient on the target OS.
- *Rely on `timeControlStatus`*: rejected; that is exactly what is blind today.

Open detail (see Open Questions): confirm the wrap-detection signal holds for `AVPlayerLooper` on the target OS (a real-device check, enabled by the probe + telemetry).

### D2 — Switch the health check to the probe; keep a bounded, retrying recovery
Decision: replace the `timeControlStatus`-based judgment in `PlaybackHealthChecker` with the D1 probe. When a stall is confirmed, trigger the **full rebuild** (D3) with a bounded, retrying policy (a few escalating attempts), after which it stops and logs. This replaces the "believes it's healthy, does nothing" behavior.

Rationale: makes recovery react to the correct signal; bounds the cost and avoids infinite rebuild loops during a truly broken display (e.g., the external display is genuinely off).

### D3 — Full, fresh, race-safe rebuild
Decision: on wake or stall, teardown *and* recreate **fresh** objects — new `AVQueuePlayer` + `AVPlayerLooper` + a new `AVPlayerLayer` attached to the content view, with an explicit `orderOut → orderFront → orderBack` + a short settle + a first-frame probe to confirm the new layer actually renders before declaring success; retry if the new one also reports stalled. This is what the existing `createDesktopWindows` path creates — the fix is ensuring it truly runs on the wake path and that it (and the security-scoped access, D4) are consistent.

Rationale: a fresh `AVPlayerLayer` after wake is the known workaround for a suspended compositor/display-link; verifying a rendered first frame prevents the "recreated but still frozen" trap and the "stale window stacked behind" symptom.

### D4 — Make `withExclusiveAccess` real and route *all* rebuilds through it
Decision: implement genuine mutual exclusion (an actor-backed async mutex / binary-semaphore with a timeout, or Swift Concurrency `actor` + an unstructured task the caller awaits) so wake, activation, space-change, health-check and manual changes all serialize. `didWake` and every trigger use the *same* lock; the wake path may additionally "rebalance" (cancel in-flight, ensure clean state) before rebuilding.

Rationale: eliminates the interleaving that can tear down a window whose replacement is mid-creation, the empty/inconsistent state, and the double teardown of shared resources.

### D5 — Replace latching boolean gates with timeout + guaranteed release
Decision: the guarded operations run under `Async` with a hard timeout and **always release** the guard on any exit path (structured concurrency / `defer`-equivalent on a single exit point), so an interrupted or slow recovery cannot latch a `guard !… else return` and swallow later user requests. A user video-change requested during a recovery is **queued** to run once the guard clears, not dropped.

Rationale: directly fixes "status-bar controls / new-video selection silently ignored after a failed recovery" without a relaunch.

### D6 — Single source of truth + ref-counted security-scoped access, reconciled on recovery
Decision: `BookmarkActor` becomes the single authority for security-scoped access with a ref-count per URL; double-stop is a no-op, and a start-after-failure does not create a dangling stop; provide a `reconcile()` that, on recovery, makes the active set match reality. Fix `stopAllSecurityScopedAccess` to use the resolved URL directly instead of reconstructing via `URL(string:)`.

Rationale: prevents the "desynced access → every subsequent selection fails forever → only relaunch rebalances" state.

### D7 — Keep the main run loop free during recovery
Decision: move the static fallback (`NSWorkspace.setDesktopImageURL`) and other slow system calls onto a background queue (off `DispatchQueue.main`), and ensure recovery never holds the main actor for a long synchronous call. `MenuBarExtra(.window)` content is main-thread; the goal is for recovery to be non-blocking there.

Rationale: the main candidate for "menu doesn't respond" is main-thread starvation by the slow synchronous static-image apply in the wake cascade.

### D8 — Observability: durable store + retained-level decisions + deterministic hook
Decision: (1) a small durable writer (append to a rolling file in the app's container) that records one compact entry per lifecycle stage (suspend/wake/recover/verify + outcome) so it survives unified-log eviction; (2) emit the recover-decision and outcome at `.error`/`.fault` (retained) in addition to the existing logs; (3) an off-by-default, gated stall hook (build/test or a debug toggle) that forces a static frame while the decoder reports playing, so D1–D7 can be validated on demand and as a regression test. Telemetry and the hook are inert in the healthy steady state.

Rationale: the freeze is rare; without durability we cannot diagnose the next one, and on-demand reproduction is the only reliable way to regression-test. All three are additive and inert when healthy.

### D9 — Delivery order (phasing)
Decision: ship **Phase A** (observability + D1 probe) first as an independent, low-risk increment; then **Phase B** (D2–D7 self-heal, ideally each behind a debug-default flag that can be rolled back); the deterministic hook (part of D8) lands with Phase A so Phase B is testable. Rationale: A alone makes the next freeze catchable; B is the actual fix; C lets us validate B deterministically.

## Risks / Trade-offs [Risk] → [Mitigation]
- [Playhead wrap-detection may be OS/version-specific on `AVPlayerLooper`] → D1 keeps a CADisplayLink pixel-diff fallback; D8 telemetry + C hook validate on the target device.
- [Forcing a rebuild on a genuinely broken/absent display (e.g., an unplugged external monitor) could thrash] → D2 bounds attempts and stops; D-no-effect-when-healthy ensures no rebuild when advancing.
- [Re-balancing security-scoped access on recovery could momentarily deny access in-flight] → D4 serializes; `reconcile()` runs once at start of a rebuild inside the lock.
- [Telemetry writes add I/O] → D8 bounds writes to lifecycle events only, never per-frame; verify no steady-state cost.
- [Off-main static-image apply changes timing of the Mission Control/Exposé static frame] → acceptable and cosmetic; gate it and observe via telemetry.
- [Over-eager rebuilds on a flaky display cause visible flicker] → D3 settles + verifies a first frame and retries sparingly; the full rebuild only fires on a *confirmed* stall or wake, not on every health-check tick.

## Migration Plan
- Additive, feature-flagged where it changes behavior: D1–D8 behind build/debug flags defaulting on for the fix, with a kill-switch so a regression can be disabled by flag or build variant (no schema/data change, so no user data migration).
- Rollback: revert to the pre-flag behavior (decoder-based health check, no probe, no durable store) by flipping flags; durable telemetry may remain on since it is inert when healthy.
- No persisted user-state changes; security-scoped access is an in-process concept. No migration of existing video files.

## Open Questions (deferrable; do not change specs or approach)
- Confirm `AVPlayerLooper` playhead wrap-detection is the reliable stall signal on the target OS (macOS reported 26.6); validate with the D8 hook/telemetry and switch to a pixel-diff probe only if it misfires.
- Exact probe period and stall-threshold (default ≈2–3 s per check, N periods of no progress); tune from telemetry.
- Whether to gate each Phase B increment behind an individual flag vs. one switch; default to per-feature flags for independent rollback.
- Whether the durable store should also capture the current window/display topology to explain "one of several displays" failures.
