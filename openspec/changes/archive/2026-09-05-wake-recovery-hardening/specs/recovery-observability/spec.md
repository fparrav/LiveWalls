## Purpose

Makes the suspend → wake → recover → verify lifecycle diagnosticable after the fact and reproducible on demand, so the recovery machinery can be validated and regression-tested without depending on the rare real-world condition (a long session followed by a long suspend and wake).

## ADDED Requirements

### Requirement: Durable recovery-lifecycle telemetry
The system SHALL record the suspend, wake, recovery-attempt, and verification stages of playback recovery into a persisted store that survives ordinary log eviction, with enough detail to determine after the fact whether wake was observed, whether a recovery was attempted, the attempt's outcome, and the verification result.

#### Scenario: A complete lifecycle is preserved after a real event
- **WHEN** the system suspends, wakes, and attempts recovery
- **THEN** the persisted store contains an entry for each of: suspend observed, wake observed, recovery attempted, attempt outcome, and verification result

#### Scenario: The stored detail distinguishes failure modes
- **WHEN** reading the persisted telemetry after the fact
- **THEN** an operator can distinguish "wake not observed" from "recovery attempted but failed" from "recovered" from "verification failed"

#### Scenario: Telemetry is bounded and lightweight
- **WHEN** the system is operating in a healthy steady state
- **THEN** telemetry recording causes no per-frame writes and no added presentation windows

### Requirement: Decision-critical recovery logging is retained
The decision of whether to recover from a stall and the outcome of that recovery SHALL be emitted at a log level that a persistent unified log retains, so the next real occurrence is diagnosable with standard log tooling rather than being evicted.

#### Scenario: A retained record of the recovery decision exists
- **WHEN** a stall is detected or a wake triggers recovery
- **THEN** the decision and its outcome are written at a retained log level and remain visible after hours in the persistent log history

### Requirement: Render-advancement is an observable signal
The system SHALL expose, as an observable and queryable signal, whether the currently displayed video is advancing or stalled, independent of the underlying decoder's reported status, and this signal is both the input to recovery decisions and part of the telemetry.

#### Scenario: A static-but-reportedly-playing video is reported stalled
- **WHEN** the displayed video is static although the decoder reports it is playing
- **THEN** the observable signal reports the output as stalled

#### Scenario: A normally playing video is reported advancing
- **WHEN** the displayed video is visibly advancing
- **THEN** the observable signal reports the output as advancing

### Requirement: On-demand deterministic stall reproduction
The system SHALL provide a test hook, disabled by default, that reproduces the post-wake render-stall state on demand — rendering a static frame while the decoder reports a healthy playing state — so the recovery path and this capability's acceptance criteria can be validated and regression-tested without a real long suspend.

#### Scenario: Simulating a stall triggers recovery
- **WHEN** the simulation is enabled in a test or debug context
- **THEN** the system behaves as if a post-wake stall occurred and runs the recovery path

#### Scenario: The hook is inert in normal operation
- **WHEN** the simulation is not enabled
- **THEN** it has no effect on playback and introduces no observable overhead

#### Scenario: The hook is controllable
- **WHEN** a test enables, observes, and then clears the simulation
- **THEN** the system returns to a normal, advancing state after clearing

### Requirement: Diagnostics do not degrade normal operation
Telemetry recording and the stall-reproduction hook SHALL be lightweight and inert when no fault is being observed or simulated: they must not trigger a recovery, add presentation windows, or add measurable cost to the healthy steady state.

#### Scenario: Healthy steady state is unaffected by diagnostics
- **WHEN** the system is in a healthy steady state with diagnostics active
- **THEN** no recovery is triggered by diagnostics, no extra presentation windows are created, and there is no measurable per-frame cost
