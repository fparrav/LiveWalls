## 1. Glass surface recipe

- [x] 1.1 In `LiveWalls/GlassCard.swift`, update `GlassSurfaceModifier`'s clipping to `RoundedRectangle(cornerRadius:style: .continuous)`, replace the flat `.overlay(stroke)` with a top-bright/bottom-faded `LinearGradient` border, add a subtle surface-gradient overlay, and replace the single `.shadow` with a stacked contact + ambient shadow pair
- [x] 1.2 Apply the equivalent recipe to `GlassDarkSurfaceModifier`, replacing its flat `darkTintOpacity` solid fill with the same low-opacity gradient overlay approach
- [x] 1.3 Visually verify existing `glassSurface()`/`glassDarkSurface()` call sites (main window panels, settings cards, about card, status bar menu) still render correctly with no API changes required at call sites

## 2. Main window: native chrome and live preview

- [x] 2.1 Remove the decorative `Circle()` traffic-light pill from `ContentView.trafficLightPill`; keep only the app-name/settings entry in that pill
- [x] 2.2 Set `titlebarAppearsTransparent = true` and `titleVisibility = .hidden` on the main window (via the app's existing `NSWindow`-configuration approach) so the real system traffic lights float over the video preview
- [x] 2.3 Add an `NSViewRepresentable` wrapping a muted, looping `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer` (mirroring `DesktopVideoWindowMejorada.setupPlayer`), taking the current video's asset/URL and updating on `wallpaperManager.currentVideo` changes
- [x] 2.4 Replace the `Image(nsImage:)` thumbnail branch in `ContentView.videoPreviewLayer` with the new live-preview representable, preserving the existing black/empty-state fallback when no video is selected

## 3. Relocate sidebar-only functionality before deleting it

- [x] 3.1 Add a mute/unmute control to the floating transport pill, wired to the same `UserDefaults`/`MuteVideo` logic currently only reachable via `sidebar_mute_button`
- [x] 3.2 Confirm play/pause, next/previous, auto-change toggle, interval, and list/shuffle mode are already reachable from the floating transport pill and bottom bar (per `redesign-liquid-glass-ui`); wire up any that are missing

## 4. Library rail: widen and add per-card actions

- [x] 4.1 In `LiveWalls/GlassCard.swift`, change `LiquidGlassMetrics.railWidth` from 240 to 320
- [x] 4.2 Expand `ContentView.libraryRow` from a 64×36 thumbnail to a full-width 16:9 card, matching the mockup's card anatomy (thumbnail, filename, resolution badge, "EN PANTALLA" badge on the active card)
- [x] 4.3 Add per-card actions to `libraryRow`: set-as-background, delete, reorder (drag handle), and an "en aleatorio" (include-in-shuffle) checkbox, wired to the same `wallpaperManager`/`selectedVideo` calls currently used by the dead `sidebarView`/`VideoThumbnailCard`
- [x] 4.4 Change the library-toggle icon in `libraryToggleButton` from `"rectangle.grid.1x2"` to `"square.grid.2x2"`

## 5. Remove dead sidebar code

- [x] 5.1 Verify `sidebarView`, `mainContentView`, and `VideoThumbnailCard` are unreferenced from `ContentView.body` after tasks 3 and 4 (i.e. every capability they held has a floating/rail equivalent)
- [x] 5.2 Delete `sidebarView`, `mainContentView`, and `VideoThumbnailCard` from `ContentView.swift`, including their `sidebar_*` accessibility identifiers
- [x] 5.3 Update `LiveWallsUITests/ContentViewUITests.swift` to remove references to `sidebar_*` identifiers and add coverage for the new mute control and library-card actions' identifiers

## 6. Main window resizability

- [x] 6.1 In `LiveWalls/LiveWallsApp.swift`, change the main `WindowGroup`'s `.windowResizability(.contentSize)` to `.windowResizability(.contentMinSize)` and add `.frame(minWidth: 960, minHeight: 640)` to `ContentView`
- [x] 6.2 Default the library rail to hidden when the window is at or near its 960×640 minimum, so it does not overlap the bottom rotation bar

## 7. About window as its own glass surface

- [x] 7.1 Rework `AboutView`/its hosting `WindowGroup(id: "about")` so the window itself carries the glass-dark material (transparent title bar, `isMovableByWindowBackground`) instead of an inner `.frame(width: 360).glassDarkSurface()` card floating inside a plain system frame
- [x] 7.2 Confirm the About window keeps its fixed 360×420 sizing (no resizability change) and remains centered with only a close control

## 8. Status bar menu: window style and richer content

- [x] 8.1 In `LiveWalls/LiveWallsApp.swift`, change the `MenuBarExtra`'s style from `.menuBarExtraStyle(.menu)` to `.menuBarExtraStyle(.window)`
- [x] 8.2 Add a now-playing header (small thumbnail + current filename) to the top of `StatusBarMenuView`, reusing `wallpaperManager.currentVideo`
- [x] 8.3 Replace the text-only playback menu rows with real transport buttons (play/pause, next, previous) alongside the existing rotation toggle, wrapped in `.glassDarkSurface()`
- [x] 8.4 Verify existing keyboard shortcuts (⌘O open, ⌘S/⌘P play/stop, ⌘N next, ⌘U check for updates, about, ⌘Q quit) and click-outside-to-dismiss behavior still work under `.window` style

## 9. Verification

- [x] 9.1 Run the full test suite (`LiveWallsTests`, `LiveWallsUITests`) and fix any failures introduced by the dead-code removal or accessibility-identifier changes
- [x] 9.2 Manually exercise the main window across its size range (960×640 minimum, 1280×800 default, and a larger display size) to confirm the live preview, native traffic lights, transport pill, library rail, and bottom bar all lay out correctly with no overlap
- [x] 9.3 Manually exercise the settings window, about window, and status bar menu (`.window` style) to confirm the glass-dark recipe renders correctly and no existing functionality (mute, per-video library actions, rotation, shuffle/list mode, drag-and-drop reordering) regressed
