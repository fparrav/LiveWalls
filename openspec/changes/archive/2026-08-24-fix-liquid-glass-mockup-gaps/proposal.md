## Why

The `redesign-liquid-glass-ui` change shipped the floating-glass visual language across LiveWalls' four windows, but the approved mockup v2 (`LiveWalls Mockup v2.dc.html`) documents six concrete discrepancies between that implementation and the design: decorative fake window controls duplicating the real ones, a main preview that is a static thumbnail instead of live video, an undersized/uninteractive library rail, a mismatched library icon, an About window with a glass card floating inside a second system frame, and dead sidebar code left in `ContentView`. The mockup also specifies window sizing/resizability behavior, a glass material recipe with more depth than the current flat translucency, and a status bar menu that needs `.menuBarExtraStyle(.window)` to render custom content at all — none of which are implemented today. This change closes those gaps so the shipped app matches the approved design.

## What Changes

- Remove the decorative traffic-light `Circle()` pill and hide the native title bar (`titlebarAppearsTransparent` + `titleVisibility = .hidden`) so the real system window controls float directly over the video preview; the left glass pill keeps only the app name/settings entry.
- Replace the static `Image(nsImage:)` thumbnail in `videoPreviewLayer` with a live `AVPlayerLayer` (`NSViewRepresentable` + `AVQueuePlayer`/`AVPlayerLooper`, muted), reusing the existing looping setup from `DesktopVideoWindowMejorada`.
- Enlarge the library rail to 320px with full 16:9 card thumbnails and add per-video actions (set as background, delete, reorder, include-in-shuffle toggle) to `libraryRow`, replacing the current 64×36 tap-only row.
- Swap the library-toggle icon from `rectangle.grid.1x2` to `square.grid.2x2` to match the mockup's four-cell grid.
- **BREAKING**: Rework `AboutView` so the window itself is the glass surface (`titlebarAppearsTransparent`, `isMovableByWindowBackground`, material applied to the window, no interior 360px glass card) instead of a glass card floating inside a normal `WindowGroup` frame.
- Delete the unused `sidebarView`, `mainContentView`, and `VideoThumbnailCard` code paths in `ContentView.swift`, and move the mute control (currently only reachable from the dead sidebar) into the floating transport pill.
- Make the main window resizable (`.windowResizability(.contentMinSize)` with a 960×640 minimum) instead of fixed to `.contentSize`, with the library rail auto-hiding at the minimum size; keep the About window fixed at 360×420.
- Deepen the `glassSurface()`/`glassDarkSurface()` recipe: continuous-corner rounded-rect clipping, a specular top-edge gradient border in place of the flat 1px stroke, a subtle surface gradient overlay in place of `GlassDarkSurfaceModifier`'s solid 55% tint, and layered contact + ambient shadows instead of one soft shadow.
- Switch `StatusBarMenuView` from `.menuBarExtraStyle(.menu)` (native AppKit menu, unstyled) to `.menuBarExtraStyle(.window)` so the existing glass-dark styling actually renders, and add a now-playing thumbnail header and real transport buttons (not text-only menu rows) to match the mockup.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `liquid-glass-ui`: window-chrome behavior (native controls only, hidden title bar, resizability, About window as its own surface), the main preview becoming live video instead of a thumbnail, library rail sizing/interactivity, and the glass surface's visual recipe (specular border, surface gradient, layered shadows) and the status bar menu's rendering style all change from what `redesign-liquid-glass-ui` originally specified.

## Impact

- Affected code: `LiveWalls/ContentView.swift` (traffic-light pill, `videoPreviewLayer`, `libraryRow`/library rail, library-toggle icon, dead sidebar removal, mute control, window resizability), `LiveWalls/AboutView.swift` (window-as-surface rework), `LiveWalls/GlassCard.swift` (glass surface recipe), `LiveWalls/StatusBarMenuView.swift` (`.menuBarExtraStyle(.window)`, now-playing header, transport buttons), `LiveWalls/LiveWallsApp.swift` (window style/resizability declarations for the main and About `WindowGroup`s), `LiveWalls/DesktopVideoWindowMejorada.swift` (source of the reusable `AVQueuePlayer`/`AVPlayerLooper` setup).
- Affected tests: `LiveWallsUITests/ContentViewUITests.swift` for any accessibility identifiers tied to the removed sidebar code, the traffic-light pill, or the library rail's new controls.
- No changes to playback engine internals, persistence, bookmarking, or wallpaper-rotation logic beyond wiring the mute control and per-video library actions to the transport/library surfaces — this is a presentation-layer correction against the approved mockup.
