## Purpose

Define how the Settings panel commits, discards, and applies user preference
changes so that a change the user made is never lost silently regardless of how
the panel is dismissed.

## ADDED Requirements

### Requirement: Confirming dismissal persists preference changes

The Settings panel SHALL persist every pending preference change when it is
dismissed by any confirming action. A confirming action is any dismissal that is
not an explicit "Cancel": clicking outside the panel, pressing the panel's
default/accept action, or closing it through the window/host chrome.

Persisted preferences include at minimum: automatic wallpaper start
(`AutoStartWallpaper`), mute videos (`MuteVideo`), duplicate-handling preference,
and auto-change enablement and interval. On persistence, the corresponding
in-memory managers SHALL be synchronized so the running app reflects the new
values without requiring a restart.

#### Scenario: Dismiss by clicking outside the panel

- **WHEN** the user toggles "Iniciar wallpaper automáticamente" on and dismisses
  the panel by clicking outside it
- **THEN** `AutoStartWallpaper` is stored as `true`
- **AND** the value is still `true` when the panel is reopened
- **AND** the value is still `true` in the next app session

#### Scenario: Dismiss with the accept action

- **WHEN** the user changes one or more preferences and activates the panel's
  accept action
- **THEN** all changed preferences are stored and the managers are synchronized

#### Scenario: Dismiss with the Escape key

- **WHEN** the user changes a preference and presses Escape
- **THEN** the behavior matches the documented Escape semantics for the panel
  (either treated as Cancel or as a confirming dismissal), and that semantics is
  consistent with the visible affordance the user was given

### Requirement: Explicit cancel reverts pending changes

The Settings panel SHALL provide an explicit "Cancel" action that reverts every
pending preference change to the value it held when the panel was opened,
including reverting launch-at-login if it was changed during the session, and
SHALL NOT write any pending change to storage.

#### Scenario: Cancel after changing preferences

- **WHEN** the user changes several preferences and activates "Cancel"
- **THEN** no preference is written to storage
- **AND** any launch-at-login change made during the session is reverted
- **AND** reopening the panel shows the original values

### Requirement: Panel opens with the current stored state

Each time the Settings panel is opened it SHALL display the currently stored
values for every preference and the current state of launch-at-login, so that a
confirming dismissal without edits is a no-op that cannot regress a value.

#### Scenario: Reopen without editing

- **WHEN** the user opens the panel and dismisses it without changing anything
- **THEN** every stored preference and the launch-at-login state are unchanged

### Requirement: Immediate-apply controls take effect on toggle

Controls that are documented as immediate-apply (for example launch-at-login,
which is backed directly by the system service) SHALL take effect the moment the
user toggles them, independently of how the panel is later dismissed, and their
revert on "Cancel" is governed by the explicit-cancel requirement above.

#### Scenario: Toggle launch-at-login then click outside

- **WHEN** the user enables launch-at-login and dismisses the panel by clicking
  outside
- **THEN** launch-at-login remains enabled
