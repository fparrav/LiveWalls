## Purpose

Define automatic wallpaper playback when the app launches — including when the
system launches it at login — its retry-and-rescue policy, and how it relates to
the "launch at login" setting.

## ADDED Requirements

### Requirement: Auto-start begins playback when enabled

When the "auto-start wallpaper" preference is enabled, the app SHALL start
wallpaper playback automatically after launch, without user interaction, as soon
as a current video and at least one screen are available.

#### Scenario: Normal launch with auto-start enabled

- **WHEN** the app launches with auto-start enabled, a persisted current video,
  and a screen connected
- **THEN** playback starts automatically within a few seconds
- **AND** the user does not have to press play

#### Scenario: Auto-start disabled

- **WHEN** the app launches with auto-start disabled
- **THEN** playback does not start automatically

### Requirement: Auto-start is resilient to a slow or hostile launch environment

Auto-start SHALL NOT be a single attempt. If the first attempt cannot start
playback because a precondition is not yet met — persisted data not loaded,
security-scoped bookmark not yet resolvable, no screen ready, or a transient
start failure — the app SHALL keep retrying with backoff for a bounded period and
SHALL leave a rescue path armed afterward, so that a transient failure during a
login launch does not leave playback permanently off.

The rescue path SHALL NOT depend solely on the app becoming the active
application, because at login the app starts in the background as an accessory
and may never be activated by the user.

#### Scenario: Persisted data loads late

- **WHEN** auto-start runs before the persisted current video has finished
  loading, and loading completes shortly after
- **THEN** auto-start still starts playback once the video is available, without
  user interaction

#### Scenario: First start attempt fails transiently

- **WHEN** the first start attempt fails for a recoverable reason during a login
  launch
- **THEN** the app retries and playback ends up running without the user pressing
  play

#### Scenario: Exhausted retries still leave a rescue armed

- **WHEN** the bounded retry window is exhausted with playback still off and
  auto-start enabled
- **THEN** a later rescue (for example a periodic health check or a system event)
  can still start playback without requiring the user to press play

### Requirement: Bookmark resolution retries before giving up during auto-start

During auto-start, if resolving the current video's security-scoped bookmark
fails for a potentially transient reason (volume or iCloud item not yet mounted
or downloaded), the app SHALL retry resolution with bounded backoff before
surfacing an error to the user.

#### Scenario: Video on a volume that mounts shortly after login

- **WHEN** the current video lives on a volume that is not mounted at the instant
  auto-start runs, and mounts a few seconds later
- **THEN** auto-start resolves the bookmark on a later retry and starts playback
- **AND** no "cannot access video file" error is shown for that transient window

#### Scenario: Video genuinely unavailable

- **WHEN** bookmark resolution keeps failing past the retry budget
- **THEN** the app surfaces a clear error and stops retrying

### Requirement: Launch-at-login and auto-start are coherent

Enabling "launch at login" SHALL result in the wallpaper actually playing after
login, not merely the app process starting. The app SHALL achieve this by
coupling the two settings: enabling launch-at-login enables auto-start (offering
the user the choice where a prompt is appropriate), and the settings UI copy and
help text SHALL make the relationship between the two options unambiguous.

#### Scenario: User enables launch at login

- **WHEN** the user enables "launch at login"
- **THEN** auto-start is enabled as part of the same action (directly or via an
  explicit offer the user accepts)
- **AND** after the next system login the wallpaper is playing without the user
  pressing play

#### Scenario: Copy communicates the relationship

- **WHEN** the user reads the labels and help text for the two options
- **THEN** it is clear that one controls whether the app launches at login and
  the other controls whether playback starts automatically, and how they combine
