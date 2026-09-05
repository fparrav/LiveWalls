# playback-recovery Specification

## Purpose
Guarantees that live desktop-wallpaper playback stays live across a system suspend/wake and self-recovers from a render-stall, without the user having to relaunch the application, while keeping the user interface responsive throughout.

## Requirements

### Requirement: Automatic recovery after a system wake
The system SHALL restore live wallpaper playback on all displays after a system wake when the wallpaper was playing before the suspend, and SHALL NOT require the user to relaunch the application to recover.

#### Scenario: Wake with the wallpaper active
- **WHEN** the system wakes and the wallpaper was playing before the suspend
- **THEN** the system re-establishes live, advancing playback on every display automatically
- **AND** no user action or relaunch is required

#### Scenario: Wake with the wallpaper not active
- **WHEN** the system wakes and the wallpaper was not playing before the suspend
- **THEN** the system does not start playback and does not enter a frozen or broken state

#### Scenario: Wake followed by a render-stall
- **WHEN** the system wakes and a wake-recovery attempt does not result in advancing playback on one or more displays
- **THEN** the system detects the stalled output and attempts recovery again rather than leaving a static frame

### Requirement: Stall detection is based on rendered output
The system SHALL determine that displayed video has stopped advancing even when the underlying decoder reports it as playing, and SHALL treat this as a recoverable fault distinct from an expected pause.

#### Scenario: Static frame while decoder reports playing
- **WHEN** the video shows the same frame repeatedly although the decoder reports an active play state
- **THEN** the system classifies the output as stalled and initiates recovery

#### Scenario: Normally-advancing video
- **WHEN** the displayed video is visibly advancing over time
- **THEN** the system does not classify the output as stalled

#### Scenario: Expected pause is not a stall
- **WHEN** the video is paused because the user stopped it or because a detected full-screen application pausing occurred
- **THEN** the system does not classify the pause as a recoverable stall

### Requirement: Recovery restores visible, advancing output
After a detected stall or a failed automatic wake-recovery, the system SHALL re-establish a visible, advancing video on each affected display, and SHALL NOT leave a frozen static frame, an empty display, or a stale window stacked above a working one.

#### Scenario: Single-display recovery
- **WHEN** rendering stalls on a single display
- **THEN** the system restores a fresh, advancing video on that display

#### Scenario: Multi-display recovery
- **WHEN** rendering stalls on one or more of several displays
- **THEN** the system restores advancing video on each affected display independently of the others

#### Scenario: No residual frozen window
- **WHEN** recovery recreates the presentation on a display
- **THEN** no previously frozen window remains visible above or behind the restored one

### Requirement: Recovery is bounded and cannot permanently latch
Each guarded recovery or video-change operation SHALL complete or time out within a bounded interval, and its guard SHALL be released regardless of the outcome, so that a slow or interrupted recovery cannot permanently prevent later playback or video-change requests.

#### Scenario: An interrupted recovery does not block later requests
- **WHEN** a recovery attempt times out or is interrupted
- **THEN** the guard is released and a subsequent user request (play, pause, next, or select a new video) is honored

#### Scenario: A video change during recovery is honored
- **WHEN** the user requests a new video while a recovery attempt is in progress
- **THEN** the request is not silently ignored and takes effect once the guard clears

### Requirement: Concurrent rebuilds of the presentation are serialized
Triggers that all request a rebuild of the desktop presentation (for example wake, application activation, a space change, and a scheduled health check) SHALL NOT interleave their teardown and recreation, so the system converges on exactly one consistent presentation and does not tear down a window whose replacement is still being created.

#### Scenario: Multiple triggers during wake
- **WHEN** wake, application activation, and a health check all request a rebuild in quick succession
- **THEN** the system applies the rebuilds in an exclusive manner and does not end in an empty or inconsistent presentation state

#### Scenario: No double teardown of shared resources
- **WHEN** two rebuild requests race for the same presentation windows
- **THEN** the shared per-display video and access resources are not torn down twice

### Requirement: Security-scoped access stays balanced
Security-scoped access to video files SHALL remain balanced across rebuilds: every successfully granted access SHALL be released exactly once, and the system SHALL return to a balanced state even after an interrupted or failed rebuild, so that later requests can grant access again.

#### Scenario: Access after an interrupted rebuild
- **WHEN** a rebuild is interrupted or fails mid-way
- **THEN** a subsequent video selection is still able to grant access and play

#### Scenario: Failed start does not create a dangling release
- **WHEN** a request to grant access fails
- **THEN** the system does not later attempt to release access that was never granted

### Requirement: The user interface remains responsive during recovery
The status-bar and main-window controls SHALL remain interactive before, during, and after a recovery attempt, and slow system operations invoked by recovery SHALL NOT block the user-interface event loop.

#### Scenario: Status menu during recovery
- **WHEN** a recovery attempt is in progress
- **THEN** the status-bar menu still opens and its controls still respond

#### Scenario: Selecting a new video during recovery is not ignored
- **WHEN** the user selects or fixes a new wallpaper while the system is recovering
- **THEN** the selection takes effect rather than being silently dropped

### Requirement: Recovery has no effect when playback is healthy
The recovery machinery SHALL have no observable effect while playback is healthy: it must not recreate windows, must not re-apply the static fallback frame, and must not cause presentation thrash.

#### Scenario: Steady-state playback
- **WHEN** the displayed video is advancing normally
- **THEN** the system neither recreates the presentation windows nor re-applies the static fallback frame
