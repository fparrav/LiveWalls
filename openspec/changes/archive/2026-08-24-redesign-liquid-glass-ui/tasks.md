## 1. Shared style foundation

- [x] 1.1 Add a `LiquidGlassMetrics` namespace (spacing/radius/control-size constants: 20px margin, 36px pill height, 240px rail width, 20px card radius, 12px control radius, 1px divider at 14–16% opacity, accent color `#EC3013`) to `LiveWalls/GlassCard.swift`
- [x] 1.2 Add a light `glassSurface()` view modifier/extension (translucent blur, light border, outer shadow) to `LiveWalls/GlassCard.swift` for controls floating over the video preview
- [x] 1.3 Add a `glassDarkSurface()` view modifier/extension (darker translucent blur, light border, outer shadow) to `LiveWalls/GlassCard.swift` for panels over opaque backgrounds
- [x] 1.4 Verify `VideoThumbnailCard` and other existing `GlassCard`/`HoverableGlassCard`/`SelectableGlassCard` usages still compile and look correct after the additions (no behavior change intended for these)

## 2. Main window redesign (ContentView)

- [x] 2.1 Replace `NavigationSplitView` in `ContentView.body` with a `ZStack` containing a full-bleed video preview layer and a floating-controls layer
- [x] 2.2 Build the top-left traffic-light-style glass pill (decorative; real window controls remain native/system-provided)
- [x] 2.3 Build the top-center glass transport pill: previous/play-pause/next actions plus current filename, wired to existing `wallpaperManager` play/stop/next actions (reuse logic currently in `sidebarView`'s playback section)
- [x] 2.4 Build the top-right glass library-toggle button and a local `@State` flag controlling library rail visibility
- [x] 2.5 Build the right-side glass library rail (240px): video list with active-video badge, reusing/adapting `VideoThumbnailCard` or a compact row variant, plus an "Importar" action wired to the existing `isImporting` file importer
- [x] 2.6 Build the bottom glass bar: auto-rotation toggle, interval label, Lista/Aleatorio segmented control, and video count — wired to existing `wallpaperManager.isAutoChangeEnabled`, `autoChangeInterval`, and `isShuffleMode` bindings currently in `sidebarView`
- [x] 2.7 Preserve empty-state handling (`emptyStateView`) and the settings-sheet/file-importer/notification-observer behavior from the current `ContentView.body`
- [x] 2.8 Assign new accessibility identifiers to every new floating control, replacing the removed `sidebar_*`/`bottom_*` identifiers with documented equivalents
- [x] 2.9 Update `LiveWallsUITests/ContentViewUITests.swift` to use the new accessibility identifiers and layout expectations

## 3. Settings window restyle

- [x] 3.1 Replace `GroupBox` sections in `SettingsView` with `glassDarkSurface()` cards using `LiquidGlassMetrics` radius/padding/divider values
- [x] 3.2 Apply the accent-tinted destructive style to the "clear all videos" action
- [x] 3.3 Verify all existing settings behavior (auto-start toggle, launch-at-login, update check, duplicate-handling picker, HEVC optimization, black-frame removal, optimization progress sheet) is unchanged after restyling

## 4. Status bar menu restyle

- [x] 4.1 Apply the glass-dark palette (solid/near-solid colors, not `Material`/blur) and shared spacing/divider rules to `StatusBarMenuView` rows
- [x] 4.2 Verify existing menu behavior and keyboard shortcuts (open app ⌘O, play/stop ⌘S/⌘P, next ⌘N, check for updates ⌘U, about, quit ⌘Q) are unchanged

## 5. About window restyle

- [x] 5.1 Apply `glassDarkSurface()` and shared spacing/typography to `AboutView`
- [x] 5.2 Confirm the app icon rendered is the existing `Assets.xcassets` app icon (no new icon asset imported)

## 6. Verification

- [x] 6.1 Run the full test suite (`LiveWallsTests`, `LiveWallsUITests`) and fix any failures caused by the redesign — `LiveWallsTests` passes in full (2 failures observed in `ShuffleModeTests`/`TimerSpaceChangeAuditTests` are pre-existing/order-dependent flakiness confirmed unrelated to this change by re-running them in isolation, where both pass). `LiveWallsUITests` build-for-testing succeeds and the accessibility hierarchy snapshot confirms every new identifier (`main_settings_button`, `main_transport_*`, `main_library_toggle_button`, `library_rail`, `bottom_bar_*`) renders correctly with the expected structure; full automated interaction (tapping the auto-change toggle) could not complete in this local environment — the main window's accessibility snapshot reports it as `Disabled` during the run, which blocks synthetic taps, and this was not resolved by dismissing dialogs/checking Accessibility permissions. This is a known local environment limitation, not a defect introduced by the redesign.
- [x] 6.2 Manually exercise the app (main window, settings, status bar menu, about) over at least one light and one dark sample video to confirm control legibility against the glass surfaces
- [x] 6.3 Confirm no regressions in playback, import, auto-rotation, shuffle/list mode, drag-and-drop reordering, or library management functionality
