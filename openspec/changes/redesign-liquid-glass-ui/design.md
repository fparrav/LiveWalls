## Context

LiveWalls is a native SwiftUI macOS app (`LiveWalls/`, `Package.swift`, `LiveWalls.xcodeproj`). Today:
- `ContentView.swift` builds the main window with `NavigationSplitView` — a fixed-width (200pt) opaque `.ultraThinMaterial` sidebar (`sidebarView`) holding playback/auto-rotation/audio/import/settings controls, and a detail pane with a video grid (`mainContentView`) plus a `bottomControlsView` HStack.
- `GlassCard.swift` defines three view wrappers (`GlassCard`, `HoverableGlassCard`, `SelectableGlassCard`) already used by `VideoThumbnailCard`, all backed by `Material.ultraThinMaterial` with a `.white.opacity(0.15)` border — a reasonable base to extend rather than replace.
- `SettingsView.swift` uses `GroupBox` sections inside a fixed 480×600 sheet.
- `StatusBarMenuView.swift` is a plain `VStack` of native `Button`/`Toggle` rows shown in an `NSMenu`-hosted SwiftUI view (menu bar dropdown) — it cannot use blur/backdrop `Material` layering the same way a window can, since it renders inside `NSStatusItem`'s menu.
- `AboutView.swift` is a plain centered `VStack` in a 360pt-wide window.
- The approved mockup (`LiveWalls Mockup.dc.html`, read via the Claude Design MCP) specifies exact pixel metrics (20px margins, 36px pill height, 240px rail, 8pt-multiple spacing) and two surface treatments (`.glass`, `.glass-dark`) expressed in CSS `backdrop-filter`/`box-shadow`, which this design maps onto SwiftUI `Material` + `.background`/`.overlay`/`.shadow`.
- No accent/token system currently exists in code (colors are ad hoc `Color.accentColor`, `.green`, `.blue`, etc.); the mockup introduces one accent color (`#ec3013`, a red-orange) for active/primary state.

See `proposal.md` for motivation ("Why"/"What Changes") and `specs/liquid-glass-ui/spec.md` for the behavioral contract this design must satisfy.

## Goals / Non-Goals

**Goals:**
- Introduce a small set of reusable SwiftUI style primitives (glass surface, glass-dark surface, standard control metrics) that every affected view composes, so the visual language is defined once.
- Restructure `ContentView`'s main window to a `ZStack` of the live preview + floating glass panels, matching the mockup's layout and metrics.
- Restyle `SettingsView`, `StatusBarMenuView`, and `AboutView` to the glass-dark system without changing their underlying state/behavior logic.
- Preserve all existing playback, import, auto-rotation, HEVC-optimization, and library-management functionality — this is presentation-layer only.

**Non-Goals:**
- No changes to `WallpaperManager`, `PersistenceActor`, `BookmarkActor`, `VideoOptimizer`, or any playback/scheduling logic.
- No new accessibility framework or design-token build pipeline (e.g. no `.xcassets` color set generation) — colors/metrics are defined as Swift constants.
- No redesign of the video-grid/library browsing experience beyond moving it into the new rail (card layout, drag-and-drop, and context menu behavior stay as-is).
- Not attempting true `backdrop-filter`-equivalent live background blur inside the `NSMenu`-hosted status bar view, since AppKit menus don't support arbitrary compositing the way an app window does (see Decisions).

## Decisions

**1. Extend `GlassCard.swift` with two new style structs instead of introducing a new file/module.**
Add `GlassSurface` (light) and `GlassDarkSurface` (dark) as `ViewModifier`s (or a `.glassSurface(_:)`/`.glassDarkSurface(_:)` view-extension pair) alongside the existing `GlassCard`/`HoverableGlassCard`/`SelectableGlassCard`. Alternative considered: replace `GlassCard.swift` outright — rejected because `VideoThumbnailCard` already depends on the existing structs and a full replacement risks an unrelated regression in the video grid, which is out of scope.

**2. Define spacing/metric constants as a small `enum LiquidGlassMetrics` (or similar namespace) rather than hardcoding literals per view.**
Centralizes the 20px margin / 36px pill height / 240px rail width / 20px card radius / 12px control radius / 8pt grid values from the mockup so all four views reference the same source, satisfying the spec's "8-point spacing and macOS HIG control metrics" requirement without duplicating magic numbers.

**3. Rebuild `ContentView`'s main window as `ZStack { videoPreviewLayer; floatingControlsLayer }`, replacing `NavigationSplitView`.**
The mockup's layout (controls floating over a full-bleed preview) is structurally incompatible with `NavigationSplitView`'s fixed sidebar/detail split. Alternative considered: keep `NavigationSplitView` and only restyle the sidebar's background — rejected because it can't produce the "library rail toggles in/out over the preview" behavior the spec requires, and it leaves the always-visible sidebar the proposal explicitly removes.

**4. Library rail visibility is a local `@State` toggle in `ContentView`, not a new persisted preference.**
Matches the mockup (a plain show/hide button) and keeps scope minimal; nothing in the proposal asks for the library's open/closed state to persist across launches.

**5. Status bar menu gets the glass-dark *look* (colors, spacing, dividers) via `.background(Color)`/custom row styling, not `Material`/`backdrop-filter`.**
`NSMenu`-hosted SwiftUI content does not composite with the desktop or support live blur the way a normal window does; using `Material` there can render incorrectly or inconsistently across macOS versions. The design applies the glass-dark palette as solid/near-solid colors with the same spacing and divider rules, which satisfies the spec's "status bar menu matches the glass-dark system" scenario (visual consistency) without relying on unsupported compositing.

**6. Reuse the existing app icon asset for the about window instead of importing `assets/livewalls-icon.png` from the mockup project.**
The mockup's icon file is a design-tool asset; the Xcode target already ships an app icon in `Assets.xcassets`. The about window will reference the existing asset catalog entry to avoid a duplicate/out-of-sync icon asset.

**7. New accent color (`#EC3013`) is added as a Swift `Color` constant (e.g. in the metrics namespace), not a new asset-catalog color set.**
Keeps the change footprint small; promoting it to an asset-catalog color (for automatic dark/light variants) is left as a follow-up if a broader design-token system is introduced later.

## Risks / Trade-offs

- [Removing the always-visible sidebar changes muscle memory for existing users] → Keep the same keyboard/menu-bar affordances (status bar menu shortcuts like ⌘O/⌘P/⌘N are unaffected) and make the library-toggle button prominent and always visible in the top-right, so the library is never more than one click away.
- [`NavigationSplitView` removal touches accessibility identifiers used by `LiveWallsUITests/ContentViewUITests.swift`] → New floating controls must define new, documented accessibility identifiers; the UI test file is updated as part of this change's tasks so CI stays green.
- [Glass surfaces (blur + translucency) can reduce text/icon contrast, hurting readability and accessibility] → Follow the mockup's specified opacities/border treatment exactly (it was designed with contrast against varied video content in mind) and verify legibility manually over both light and dark sample videos before completing the change.
- [Status bar menu can't get true blur/backdrop compositing] → Documented in Decision 5; scenario is satisfied via matching colors/spacing rather than pixel-identical blur, which is the best achievable outcome given `NSMenu` hosting constraints.
- [Centralizing metrics in one namespace could be over-engineered for a 4-view change] → Kept intentionally small (a handful of constants + two view modifiers), not a full design-token system, to match the actual scope.

## Migration Plan

- Single-PR, presentation-only change; no data migration, no persisted-schema changes, no feature flag needed since it doesn't affect stored user data (video library, bookmarks, preferences) or app entitlements.
- Rollback is a plain revert of the UI commit(s) if visual regressions are found post-merge; underlying managers/persistence are untouched so rollback carries no data risk.
- Manual verification pass (documented in tasks.md) across main window, settings, status bar menu, and about window on the currently supported macOS versions before merging, since SwiftUI `Material` rendering can vary by OS version (see `SettingsView`'s existing `#unavailable(macOS 13.0)` compatibility check).
