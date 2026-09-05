## 1. Settings panel — commit-on-dismiss (D1, D2)

- [ ] 1.1 In `ContentView.settingsPanel`, make the `onClose` closure commit
      pending changes before hiding the panel (call into a `SettingsView` save
      entry point rather than only setting `showSettings = false`).
- [ ] 1.2 In `SettingsView`, expose a save path callable from `onClose` (e.g.
      route `onClose` through a closure that runs `saveAllSettings()` then the
      host's dismiss), keeping `saveAllSettings()` as the single write point.
- [ ] 1.3 Rebind Escape: remove `.cancelAction` as the implicit
      commit-bypass — Escape commits like tap-outside. Keep the visible
      "Cancelar" button as the only revert path; give it clear prominence.
- [ ] 1.4 Verify `loadCurrentSettings()` still runs on every open so the panel
      always shows stored state (no-op dismissal cannot regress a value).
- [ ] 1.5 Confirm `cancelChanges()` still reverts every local (incl.
      launch-at-login) and writes nothing.

## 2. Settings ↔ launch-at-login coupling + copy (D5)

- [ ] 2.1 In `SettingsView.launchAtLoginBinding` setter, when enabling
      launch-at-login also set the pending `autoStartWallpaper` local to `true`
      (visible toggle flip). Disabling launch-at-login leaves auto-start
      untouched.
- [ ] 2.2 Ensure the flipped `autoStartWallpaper` is persisted through the normal
      commit path (covered by section 1) and reverted by "Cancelar".
- [ ] 2.3 Update `auto_start_wallpaper`, `launch_at_login`, `launch_at_login_help`
      in `LiveWalls/Resources/Localizations/*.lproj/Localizable.strings` (all
      shipped locales) so the labels state the relationship between the two
      options. Confirm only the `LiveWalls/Resources/Localizations` tree is
      edited (top-level `*.lproj` is dead).

## 3. Auto-start retry + login rescue (D3)

- [ ] 3.1 Change `autoStartScheduled` from a permanent latch to an
      "in-flight" guard: cleared when `coordinateStartup` returns.
- [ ] 3.2 Add the live `AutoStartWallpaper` preference check to the coordinator's
      success predicate (abort cleanly if the user turns auto-start off during
      retries).
- [ ] 3.3 After `coordinateStartup` returns without playback while auto-start is
      still enabled, arm a bounded periodic rescue via
      `ScheduledHealthCheckManager` (coarse intervals, e.g. `[5, 15, 60]`s) whose
      action is `ensurePlaying(reason: "post-login autostart rescue")`.
- [ ] 3.4 Ensure the rescue stops on the first `isPlayingWallpaper == true` and
      after its interval budget is exhausted (then rely on the existing error
      notification).
- [ ] 3.5 Rebase / sequence against `wake-recovery-hardening`: align with its
      final `ensurePlaying()` signature and `StartupCoordinator` changes; do not
      duplicate its recovery logic.

## 4. Bookmark resolution retry on the auto-start path (D4)

- [ ] 4.1 Add a bounded retry wrapper (≈3 attempts, `[1, 2, 4]`s) around
      `resolveBookmark(for:)` used by the auto-start start action only.
- [ ] 4.2 Where the API allows, distinguish transient (parent volume absent /
      iCloud item not downloaded) from permanent (stale bookmark); retry
      transient, fail fast on permanent.
- [ ] 4.3 Leave the manual `startWallpaperSafe()` / "press play" path unchanged
      (immediate error on failure).
- [ ] 4.4 After the retry budget with no resolution, show the existing
      "No se pudo acceder al archivo de video" notification once (no spam).

## 5. Tests

- [ ] 5.1 Settings persistence: toggling `autoStartWallpaper` then dismissing via
      the `onClose` path stores `true` (unit/UI test around the save entry point).
- [ ] 5.2 Settings cancel: `cancelChanges()` writes nothing and reverts
      launch-at-login.
- [ ] 5.3 Coupling: enabling launch-at-login flips the pending `autoStartWallpaper`
      local; "Cancelar" reverts both.
- [ ] 5.4 Auto-start retry: coordinator succeeds after persisted data loads late
      (extend/adjust existing `StartupCoordinator` tests).
- [ ] 5.5 Login rescue: with auto-start enabled and playback off after
      coordination, the armed rescue calls `ensurePlaying` and stops once
      playback is running.
- [ ] 5.6 Bookmark retry: transient nil resolves on a later attempt and starts
      playback without showing an error; permanent failure notifies after the
      budget.

## 6. Manual verification

- [ ] 6.1 Enable launch-at-login, reboot, confirm the wallpaper is playing at the
      desktop without pressing play.
- [ ] 6.2 Toggle `autoStartWallpaper` in Settings, dismiss by clicking outside,
      reopen — value persists; confirm across an app relaunch.
- [ ] 6.3 Put the current video on an external volume, reboot with the volume
      slow to mount, confirm playback starts once it mounts (no premature error).
- [ ] 6.4 Regression: `wake-recovery-hardening` wake/Space-change recovery still
      behaves as before.
