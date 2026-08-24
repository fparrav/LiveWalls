## Purpose

Defines the floating "liquid glass" visual language — shared surface, spacing, and control-metric rules, and how the main window, settings window, status bar menu, and about window must apply them — so LiveWalls presents one consistent glass aesthetic across all its windows and menus.

## ADDED Requirements

### Requirement: Shared glass surface styles
The system SHALL provide two reusable glass surface treatments — a light "glass" style for controls floating over the video preview, and a darker "glass-dark" style for panels shown over an opaque background (settings, status bar menu, about) — and every floating control or panel introduced by this change SHALL use one of these two styles rather than a one-off background.

#### Scenario: Floating controls over the video preview use the light glass style
- **WHEN** a control (traffic-light pill, transport pill, library-toggle button, library rail, rotation bar) is rendered directly over the live video preview in the main window
- **THEN** it is rendered with the light glass surface (translucent blur, subtle light border, soft outer shadow)

#### Scenario: Panels over opaque backgrounds use the glass-dark style
- **WHEN** a panel is rendered in the settings window, the status bar menu, or the about window
- **THEN** it is rendered with the glass-dark surface (darker translucent blur, subtle light border, outer shadow) rather than the light glass style

### Requirement: 8-point spacing and macOS HIG control metrics
All floating controls and panels SHALL align to an 8-point spacing grid and use consistent control metrics: a 20px outer margin from the window edge, 36px height for the top-row pill controls, 240px width for the library rail, 20px corner radius on cards/rails, 12px corner radius on inner controls, and 1px dividers at 14–16% opacity.

#### Scenario: Top-row controls share height and vertical position
- **WHEN** the main window renders the traffic-light pill, the transport pill, and the library-toggle button
- **THEN** all three sit 20px from the top edge of the window and are 36px tall

#### Scenario: Library rail respects the standard sidebar width
- **WHEN** the library rail is visible in the main window
- **THEN** it is 240px wide and positioned with 20px clearance from the window's trailing edge

### Requirement: Main window presents a floating-glass layout over the live preview
The main window SHALL show the active video wallpaper filling the window as a live background, with all playback and library controls presented as floating glass panels over that preview instead of a fixed opaque sidebar.

#### Scenario: Transport controls are reachable without an always-visible sidebar
- **WHEN** the user opens the main window
- **THEN** play/pause, previous/next, and the current filename are available in a floating glass pill centered at the top of the window, and no permanently-docked opaque sidebar occupies the left edge

#### Scenario: Library is opened via a toggle rather than shown by default
- **WHEN** the user clicks the library-toggle button in the top-right of the main window
- **THEN** the glass library rail appears on the right edge showing the video list, with the active video visually marked, and an action to import more videos

#### Scenario: Rotation controls are grouped in a bottom glass bar
- **WHEN** auto-rotation is available in the main window
- **THEN** its enable/disable toggle, interval display, and Lista/Aleatorio (list/shuffle) mode selector are grouped together in a single glass bar anchored to the bottom of the window, alongside the total video count

### Requirement: Settings, status bar menu, and about windows use the glass-dark system
The settings window, the status bar menu, and the about window SHALL present their controls and content grouped in glass-dark cards/panels using the shared spacing and control-metric rules, replacing their current system-default (`GroupBox`, plain menu list, plain `VStack`) presentation.

#### Scenario: Settings sections are grouped in glass-dark cards
- **WHEN** the user opens the settings window
- **THEN** playback toggles, system options, and library-management actions are each presented inside a glass-dark card with 20px corner radius and 20px internal padding, separated by 1px dividers at the shared opacity

#### Scenario: Destructive settings actions are visually distinguished
- **WHEN** the settings window renders the "delete all videos" action
- **THEN** it is visually distinguished from non-destructive actions (e.g. tinted accent color) so it is not confused with a routine action

#### Scenario: Status bar menu matches the glass-dark system
- **WHEN** the user opens the status bar menu
- **THEN** its content is presented on the glass-dark surface with the shared spacing rules, showing the current wallpaper, transport actions, and quick settings consistent with the rest of the app

#### Scenario: About window matches the glass-dark system
- **WHEN** the user opens the about window
- **THEN** the app icon, name, version, and links are presented on the glass-dark surface with the shared spacing and typography rules
