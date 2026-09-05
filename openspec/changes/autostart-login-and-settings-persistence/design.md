## Context

See `proposal.md` — Why. Three code facts shape the approach:

- `SettingsView` is presented by `ContentView.settingsPanel` as a floating glass
  panel. `onClose` only sets `showSettings = false`; it never calls
  `saveAllSettings()`. Preferences are `@State` locals committed to `UserDefaults`
  only inside `saveAllSettings()`, which only the "Aceptar" button invokes.
  `cancelChanges()` reverts locals and reverts launch-at-login. Escape is bound
  to `.cancelAction` (→ Cancel).
- `WallpaperManager.attemptAutoStart()` runs once in `init`, guarded by
  `autoStartScheduled`. It delegates to `StartupCoordinator.coordinateStartup()`
  (backoff `[0.2, 0.5, 1.0, 2.0, 4.0]`, `maxRetries: 5`). On success it calls
  `startWallpaperSafe()`. On failure nothing reschedules. `ensurePlaying()` has an
  auto-start branch (`!isPlayingWallpaper && AutoStartWallpaper → startWallpaperSafe()`)
  but its only login-relevant trigger is `didBecomeActive`, which does not fire
  for a background accessory app.
- `startWallpaperSafe()` calls `resolveBookmark(for:)` once; `nil` → error
  notification, no retry. Scheduled health checks are armed only *inside*
  `startWallpaperSafe()`, so they never run if the start never happened.
- The `wake-recovery-hardening` branch is concurrently editing `ensurePlaying()`,
  `StartupCoordinator`, and recovery telemetry.

## Goals / Non-Goals

**Goals:**

- No preference change is lost by dismissing the Settings panel any way other
  than explicit Cancel.
- Auto-start survives a hostile login environment: bounded retry plus a rescue
  that does not depend on app activation.
- Bookmark resolution in the auto-start path tolerates a briefly-unavailable
  volume/iCloud item.
- "Launch at login" reliably produces *playing wallpaper*, and the UI copy makes
  the two toggles' relationship clear.

**Non-Goals:**

- No persistence of "was playing at last quit" session state — auto-start stays
  preference-driven.
- No change to the wake/Space-change recovery machinery beyond what is needed to
  arm a login rescue (leave that to `wake-recovery-hardening`).
- No new settings-storage backend; keep `UserDefaults` + `PersistenceActor`.
- No redesign of the Settings panel layout.

## Decisions

### D1: Settings panel — commit-on-dismiss, keep an explicit Cancel

`onClose` (the tap-outside / host-chrome path) calls `saveAllSettings()` before
clearing `showSettings`. "Aceptar" keeps calling `saveAllSettings()`. "Cancelar"
keeps calling `cancelChanges()`. This makes the default gesture safe, matching
how the panel now visually reads (a popover, not a modal form).

- Alternative — *apply each toggle immediately via `.onChange`*: cleaner mental
  model but a larger diff (every control grows a side effect), loses the atomic
  Cancel, and risks half-applied state mid-edit. Rejected for now; the commit-on
  -dismiss change is small and reversible.
- Alternative — *remove Cancel/Accept, pure immediate-apply*: same downsides plus
  it strands the "revert launch-at-login" behavior.

### D2: Escape key → treat as confirming dismissal

Rebind the panel's Escape handling so Escape commits like tap-outside, and the
only revert path is the visible "Cancelar" button. Rationale: once tap-outside
commits, Escape-as-cancel is a hidden, surprising exception. A user pressing
Escape to "close" the popover expects their toggle to stick.

- Alternative — *keep Escape = Cancel*: retains an AppKit convention but
  contradicts D1 and the popover affordance. If we keep it, the specs' Escape
  scenario resolves to "Cancel" and we must make the Cancel button visually
  prominent.

### D3: Auto-start — retry loop that re-checks the preference, plus a login rescue

Replace the one-shot with:

1. `attemptAutoStart()` keeps using `StartupCoordinator` but the coordinator's
   success predicate also requires the `AutoStartWallpaper` preference to still
   be true at check time (so toggling it off mid-retry aborts cleanly).
2. After the bounded retry window, if auto-start is still enabled and playback is
   still off, arm a lightweight periodic rescue (reuse
   `ScheduledHealthCheckManager` with a coarse interval, e.g. `[5, 15, 60]`s)
   whose action is `ensurePlaying(reason: "post-login autostart rescue")`. This
   reuses the existing auto-start branch in `ensurePlaying()` and stops itself
   once `isPlayingWallpaper` is true.
3. `autoStartScheduled` becomes a "coordination in flight" guard, not a
   "coordination done forever" latch — cleared when the coordinator returns so
   the rescue path (or a future explicit trigger) can re-enter.

- Alternative — *increase `maxRetries` / backoff ceiling*: simpler but just moves
  the cliff; still a single unrescued attempt and still tied to `init` timing.
- Alternative — *drive auto-start from `ContentView.onAppear` / a scene phase
  hook*: the main window may never appear for an accessory login launch.

Coordinate with `wake-recovery-hardening`: the rescue action funnels through
`ensurePlaying()` which that branch is already hardening — land this after it, or
rebase onto its `ensurePlaying` signature.

### D4: Bookmark resolution retry inside the auto-start path only

Add a bounded retry wrapper (e.g. 3 attempts, `[1, 2, 4]`s) around
`resolveBookmark(for:)` used by the auto-start start action. Distinguish
"transient" (nil result while the file's parent volume is absent / iCloud item
not downloaded) from "permanent" (bookmark stale/invalid) where the API allows;
when undeterminable, retry the bounded budget then notify. Do **not** change the
manual "press play" path — there the user is present and an immediate error is
the right feedback.

### D5: Couple launch-at-login → auto-start

When the user enables launch-at-login in Settings, set the pending
`autoStartWallpaper` local to `true` as well (visibly flipping that toggle so the
user sees it and can still turn it back off before dismissing). Disabling
launch-at-login does not touch auto-start. Update `Localizable.strings` for
`auto_start_wallpaper`, `launch_at_login`, `launch_at_login_help` across all
`*.lproj` so the labels state the relationship.

- Alternative — *modal prompt on enable* ("¿También iniciar la reproducción al
  entrar?"): more explicit but heavier; the visible toggle flip achieves consent
  with less friction and stays consistent with D1's commit-on-dismiss.
- Alternative — *hard-link them (one toggle)*: loses the valid "launch app at
  login but let me pick the video first" workflow.

## Risks / Trade-offs

- **Commit-on-dismiss surprises a user who expected tap-outside to cancel** →
  the explicit "Cancelar" button stays; changes are all individually reversible
  preferences, not destructive actions.
- **D5 flips a toggle the user didn't touch directly** → it happens on-screen
  before any commit, and it is a pending local the user can flip back; nothing is
  written until a confirming dismissal.
- **Periodic login rescue keeps a timer alive when a video is genuinely missing**
  → bound the rescue to a small number of attempts and stop on the first
  `isPlayingWallpaper == true`; after the budget, fall back to the existing
  error notification and stop.
- **Bookmark retry masks a real "file moved" error for a few seconds** → cap the
  retry budget low (~7s total) and only on the auto-start path; manual start is
  unchanged.
- **Merge conflict with `wake-recovery-hardening`** on `ensurePlaying()` /
  `StartupCoordinator` → sequence this change after that branch merges, or rebase
  onto it; the tasks list calls this out.

## Migration Plan

- Pure behavior/UI change; no data migration. `AutoStartWallpaper` keeps its key
  and meaning.
- Optional follow-up (not required here): register a default value for
  `AutoStartWallpaper`. Left out to avoid changing behavior for existing users.
- Rollback: revert the change; `UserDefaults` values written under the new
  commit-on-dismiss behavior remain valid under the old code.
