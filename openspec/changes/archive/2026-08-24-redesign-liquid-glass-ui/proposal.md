## Why

LiveWalls' current UI (`ContentView`, `SettingsView`, `AboutView`, `StatusBarMenuView`) uses a generic `NavigationSplitView` + `.ultraThinMaterial` sidebar with system-default controls. The approved Claude Design mockup (`LiveWalls Mockup.dc.html`) defines a cohesive "liquid glass" visual language — floating glass panels over the desktop wallpaper preview, an 8pt spacing grid, and macOS HIG-aligned metrics (12px traffic-light-style dots, 36px control height, 240px sidebar, 1.5–2px SF-style strokes) — that better matches what LiveWalls actually does (a live desktop wallpaper player) and should replace the current chrome-heavy window across the app's four surfaces.

## What Changes

- Redesign the main window as a full-bleed video-preview canvas with floating glass controls instead of `NavigationSplitView` + opaque sidebar:
  - Top row: glass traffic-light pill (top-left, decorative — real window controls stay native), glass transport pill (top-center: prev/play-pause, filename, next), glass library-toggle button (top-right).
  - Right glass rail (240px): "Biblioteca" video library list with active-video badge and an "Importar" action, replacing the current left sidebar's video grid entry point.
  - Bottom glass bar: auto-rotation toggle + interval label + Lista/Aleatorio segmented control + video count, replacing the sidebar's auto-change and mode controls.
- Restyle `SettingsView` panels (playback toggles, library management actions, danger-styled "delete all" action) with the same glass-dark surface, 20px card radius, 12px control radius, and 16%-opacity 1px dividers.
- Restyle `StatusBarMenuView` (menu bar dropdown) and `AboutView` with the same glass-dark surface and spacing/typography rules for visual consistency across every window/menu the app shows.
- Introduce shared liquid-glass style building blocks (glass/glass-dark surface treatment, standard control heights/radii, toggle switch look) so all four surfaces draw from one definition instead of ad hoc `.background(.ultraThinMaterial)` calls. **BREAKING** for any code relying on the current `GlassCard`/`HoverableGlassCard`/`SelectableGlassCard` visual defaults, since their material, radius, and border values change to match the new system.
- **BREAKING**: Removes the current always-visible left `NavigationSplitView` sidebar; the video library moves into the right-side toggleable glass rail, changing where users find playback/import/settings controls.

## Capabilities

### New Capabilities
- `liquid-glass-ui`: The floating-glass visual design system (surfaces, spacing, control metrics, iconography) and its application across the main window, settings window, status bar menu, and about window.

### Modified Capabilities
(none — no existing `openspec/specs/` capabilities are tracked yet for this project's UI)

## Impact

- Affected code: `LiveWalls/ContentView.swift` (main window layout, sidebar → floating panels), `LiveWalls/GlassCard.swift` (surface/material primitives), `LiveWalls/SettingsView.swift`, `LiveWalls/AboutView.swift`, `LiveWalls/StatusBarMenuView.swift`.
- Affected tests: `LiveWallsUITests/ContentViewUITests.swift` and any test relying on current accessibility identifiers/layout of the sidebar (e.g. `sidebar_play_toggle_button`, `sidebar_autochange_toggle`, `sidebar_mode_picker`) will need updated identifiers/locations for the new floating controls.
- No changes to playback engine, persistence, bookmarking, or wallpaper-management logic — this is a presentation-layer redesign only.
- New static asset dependency: app icon artwork already exists at `LiveWalls/Assets.xcassets` (mockup references `assets/livewalls-icon.png`, which maps to the existing app icon).
