## MODIFIED Requirements

### Requirement: Shared glass surface styles
The system SHALL provide two reusable glass surface treatments — a light "glass" style for controls floating over the video preview, and a darker "glass-dark" style for panels shown over an opaque background (settings, status bar menu, about) — and every floating control or panel introduced by this change SHALL use one of these two styles rather than a one-off background. Both styles SHALL be clipped to a continuous-corner rounded rectangle, use a specular gradient border (brighter along the top edge, fading toward the bottom) rather than a flat single-opacity stroke, overlay a subtle surface gradient instead of a solid tint, and cast two stacked shadows — a tight contact shadow and a soft ambient shadow — rather than a single soft shadow.

#### Scenario: Floating controls over the video preview use the light glass style
- **WHEN** a control (traffic-light-adjacent settings pill, transport pill, library-toggle button, library rail, rotation bar) is rendered directly over the live video preview in the main window
- **THEN** it is rendered with the light glass surface: continuous-corner clipping, a top-bright/bottom-faded specular border gradient, a subtle surface gradient overlay, and layered contact + ambient shadows

#### Scenario: Panels over opaque backgrounds use the glass-dark style
- **WHEN** a panel is rendered in the settings window, the status bar menu, or the about window
- **THEN** it is rendered with the glass-dark surface (darker translucent blur, the same specular border gradient and layered shadows) rather than the light glass style or a solid opaque tint

### Requirement: 8-point spacing and macOS HIG control metrics
All floating controls and panels SHALL align to an 8-point spacing grid and use consistent control metrics: a 20px outer margin from the window edge, 36px height for the top-row pill controls, 320px width for the library rail, 20px corner radius on cards/rails, 12px corner radius on inner controls, and 1px dividers at 14–16% opacity.

#### Scenario: Top-row controls share height and vertical position
- **WHEN** the main window renders the settings pill, the transport pill, and the library-toggle button
- **THEN** all three sit 20px from the top edge of the window and are 36px tall

#### Scenario: Library rail respects the widened rail width
- **WHEN** the library rail is visible in the main window
- **THEN** it is 320px wide and positioned with 20px clearance from the window's trailing edge

#### Scenario: Library rail respects the standard sidebar width
- **WHEN** the library rail is visible in the main window
- **THEN** it is 240px wide and positioned with 20px clearance from the window's trailing edge
### Requirement: Main window presents a floating-glass layout over the live preview
The main window SHALL show the active video wallpaper actually playing (not a static thumbnail) filling the window as a live background, with all playback and library controls presented as floating glass panels over that preview instead of a fixed opaque sidebar or dead unused view code.

#### Scenario: The preview shows live, playing video
- **WHEN** the user opens the main window with a video selected
- **THEN** the video is rendered by a real playback layer that is actively playing and looping (muted), not a single static frame drawn from thumbnail data

#### Scenario: Transport controls are reachable without an always-visible sidebar
- **WHEN** the user opens the main window
- **THEN** play/pause, previous/next, mute, and the current filename are available in a floating glass pill centered at the top of the window, and no permanently-docked opaque sidebar or unused legacy view occupies the left edge

#### Scenario: Library is opened via a toggle rather than shown by default
- **WHEN** the user clicks the library-toggle button in the top-right of the main window
- **THEN** the glass library rail appears on the right edge showing the video list at full 16:9 card size, with the active video visually marked, and an action to import more videos

#### Scenario: Library toggle icon matches the four-cell grid design
- **WHEN** the library-toggle button is rendered
- **THEN** its icon is a symmetric four-cell grid glyph, not a two-row rectangle glyph

#### Scenario: Each library card exposes per-video management actions
- **WHEN** the user views a video card in the library rail
- **THEN** the card exposes actions to set it as the active background, delete it, reorder it within the list, and toggle whether it is included in shuffle rotation — not only a tap-to-select gesture

#### Scenario: Rotation controls are grouped in a bottom glass bar
- **WHEN** auto-rotation is available in the main window
- **THEN** its enable/disable toggle, interval display, and Lista/Aleatorio (list/shuffle) mode selector are grouped together in a single glass bar anchored to the bottom of the window, alongside the total video count

### Requirement: Settings, status bar menu, and about windows use the glass-dark system
The settings window, the status bar menu, and the about window SHALL present their controls and content grouped in glass-dark cards/panels using the shared spacing and control-metric rules, replacing their current system-default (`GroupBox`, plain menu list, plain `VStack`) presentation. The status bar menu SHALL render as a custom SwiftUI surface capable of displaying that styling, and the about window SHALL apply the glass-dark material to the window itself rather than to a card floating inside a separate system-drawn frame.

#### Scenario: Settings sections are grouped in glass-dark cards
- **WHEN** the user opens the settings window
- **THEN** playback toggles, system options, and library-management actions are each presented inside a glass-dark card with 20px corner radius and 20px internal padding, separated by 1px dividers at the shared opacity

#### Scenario: Destructive settings actions are visually distinguished
- **WHEN** the settings window renders the "delete all videos" action
- **THEN** it is visually distinguished from non-destructive actions (e.g. tinted accent color) so it is not confused with a routine action

#### Scenario: Status bar menu renders custom glass-dark content
- **WHEN** the user opens the status bar menu
- **THEN** it renders as a custom SwiftUI surface (not a plain native menu) presenting a now-playing thumbnail header, real transport buttons, and quick settings, all on the glass-dark surface with the shared spacing rules

#### Scenario: About window is the glass surface, not a card inside one
- **WHEN** the user opens the about window
- **THEN** the window itself has no visible system title bar and carries the glass-dark material directly; the app icon, name, version, and links are presented directly against that window surface with no separate glass card nested inside a plain system frame

#### Scenario: Status bar menu matches the glass-dark system
- **WHEN** the user opens the status bar menu
- **THEN** its content is presented on the glass-dark surface with the shared spacing rules, showing the current wallpaper, transport actions, and quick settings consistent with the rest of the app


#### Scenario: About window matches the glass-dark system
- **WHEN** the user opens the about window
- **THEN** the app icon, name, version, and links are presented on the glass-dark surface with the shared spacing and typography rules
## ADDED Requirements

### Requirement: Native window chrome provides window controls
The main window SHALL rely solely on the real system-provided window controls (close/minimize/zoom) for window management; it SHALL NOT render a decorative duplicate of those controls, and its title bar SHALL be hidden so the video preview and floating glass panels extend to the window's top edge.

#### Scenario: Only real controls are present
- **WHEN** the main window is displayed
- **THEN** the standard macOS traffic-light window controls are the only close/minimize/zoom affordance shown, rendered by the system over the video preview, with no separately drawn circles duplicating them

#### Scenario: No native title bar strip is shown
- **WHEN** the main window is displayed
- **THEN** the system title bar is transparent and its title is hidden, so no opaque strip separates the traffic-light controls from the video preview beneath them

### Requirement: Main window is resizable within defined bounds
The main window SHALL be user-resizable rather than fixed to its content size, remaining usable down to a documented minimum size, with the library rail hidden by default at that minimum to avoid overlapping the bottom bar.

#### Scenario: Window can be resized above the minimum
- **WHEN** the user drags the main window's resize edge
- **THEN** the window resizes freely between its minimum bound and larger sizes, with the video preview and floating panels adapting to the new size

#### Scenario: Library rail auto-hides at the minimum size
- **WHEN** the main window is at or near its minimum supported size
- **THEN** the library rail is hidden by default so it does not overlap the bottom rotation bar
