## Context

`redesign-liquid-glass-ui` shipped the glass visual language, but left six gaps against the approved mockup (`LiveWalls Mockup v2.dc.html`), all in already-identified locations:

- `ContentView.trafficLightPill` (:200-235) draws three decorative `Circle()`s with `.accessibilityHidden(true)` while the real system traffic lights still render on top of the native title bar — two sets of controls.
- `ContentView.videoPreviewLayer` (:88-110) renders `Image(nsImage: NSImage(data: thumbnailData))` — a single static frame, not playing video.
- `ContentView.libraryRow` (:402-457) uses a 64×36 thumbnail with only `.onTapGesture { selectedVideo = video }` (:455) — no other actions.
- `ContentView.sidebarView` (:526-706) and `mainContentView` (:709-745) are dead code (unreferenced from `body`, per the project's own comments at :24-33 and :118-136 marking them for retirement); `VideoThumbnailCard` (:865-1048) is only reachable through the dead `mainContentView`. The mute control (`sidebar_mute_button`, :669) lives only inside this dead code, with no floating equivalent (comment at :129-131 already flags this).
- `libraryToggleButton` (:311-327) uses SF Symbol `"rectangle.grid.1x2"` (:320) instead of a four-cell grid glyph.
- `AboutView` (62 lines) is a plain view wrapped in `.padding(...).glassDarkSurface().frame(width: 360)` and hosted by a normal `WindowGroup(id: "about")` (LiveWallsApp.swift :55-57) — a glass card floating inside a system-drawn frame, rather than the window itself being the glass surface.

Two further gaps aren't location-specific fixes but system-wide recipe/behavior changes: `GlassSurfaceModifier`/`GlassDarkSurfaceModifier` (GlassCard.swift :202-226, :280-315) currently chain only `.background` → `.cornerRadius` → a flat single-opacity `.overlay(stroke)` → one `.shadow(...)` — flatter than the mockup's specular-border/layered-shadow recipe. And `StatusBarMenuView` is hosted with `.menuBarExtraStyle(.menu)` (LiveWallsApp.swift :48-53), which renders as a native AppKit menu that cannot display the view's own styling at all, regardless of what `StatusBarMenuView`'s body contains.

`DesktopVideoWindowMejorada.setupPlayer(with:preloadedAsset:)` (:179-321) already implements the exact muted/looping playback pattern needed for a live preview: `AVQueuePlayer` (`.volume = 0`, `.isMuted = true`) + `AVPlayerLooper` + `AVPlayerLayer` (`.videoGravity = .resizeAspectFill`) added as a sublayer.

## Goals / Non-Goals

**Goals:**
- Close each of the six mockup-documented discrepancies plus window sizing/resizability, the deeper glass material recipe, and the status bar menu's rendering style — all scoped to presentation code.
- Reuse the existing `AVQueuePlayer`/`AVPlayerLooper`/`AVPlayerLayer` pattern from `DesktopVideoWindowMejorada` rather than inventing a second playback implementation.
- Preserve every existing behavior currently reachable only through the dead `sidebarView` (mute, playback, auto-change, mode) by relocating it to floating/rail controls before deleting the dead code.

**Non-Goals:**
- No changes to `WallpaperManager`, `PersistenceActor`, `BookmarkActor`, or any playback/persistence business logic — only how it's presented and which views invoke it.
- No new video-decoding or thumbnail-generation pipeline; the live preview reuses existing playback wiring, it does not change how videos are imported or optimized.
- Not re-litigating the overall glass design language (spacing grid, color tokens) established by `redesign-liquid-glass-ui` — only the specific gaps listed in the proposal.

## Decisions

**Live preview: reuse `DesktopVideoWindowMejorada`'s player pattern via a new lightweight `NSViewRepresentable`, not the class itself.** `DesktopVideoWindowMejorada` is an `NSWindow` subclass tied to desktop-wallpaper window management; embedding it inside `ContentView` would pull in unrelated window-lifecycle code. Instead, a small `NSViewRepresentable` wraps just the `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer` construction (mirroring :234-261), taking the current video's asset/URL as input and updating the player item when `wallpaperManager.currentVideo` changes. `videoPreviewLayer` swaps its `Image(nsImage:)` branch for this representable, keeping the same empty-state/black fallback.

**Traffic lights: delete the decorative `Circle()` pill, don't restyle it.** The mockup explicitly shows real native controls with no glass pill behind them (mockup section 1 / bottom render). Alternative considered: keep a glass pill but make it non-decorative (wire real close/minimize/zoom actions to it) — rejected because it would duplicate `NSWindow` behavior AppKit already provides for free once the title bar is transparent, adding a second control surface with no benefit. `titlebarAppearsTransparent = true` and `titleVisibility = .hidden` are applied to the underlying `NSWindow` (via an `NSViewRepresentable`/`NSWindow` accessor already idiomatic for this codebase's window customization, matching how `DesktopVideoWindowMejorada` configures its own `NSWindow` properties) so the real traffic lights float directly over the video preview.

**Library rail: widen to 320px and expand `libraryRow` in place**, rather than introducing a new row type. `LiquidGlassMetrics.railWidth` moves from 240 to 320; `libraryRow` grows its thumbnail to a full-width 16:9 `aspectRatio` card and gains a per-card action row (set-as-background, delete, reorder handle, shuffle-inclusion checkbox) matching the mockup's card anatomy, wired to the same `wallpaperManager`/`selectedVideo` calls the dead `sidebarView` and `VideoThumbnailCard` already use today — so no new business-logic wiring is invented, only relocated.

**Dead code removal happens only after every capability it held is relocated.** Order within tasks.md: (1) add mute control to the transport pill, (2) add per-card actions to `libraryRow`, (3) confirm no remaining references to `sidebarView`/`mainContentView`/`VideoThumbnailCard`/the `sidebar_*` identifiers, (4) delete them and update `ContentViewUITests.swift`. This avoids a window where functionality regresses mid-change.

**About window: make the `WindowGroup` itself borderless/transparent-titlebar and move `glassDarkSurface()` from an inner `.frame(width: 360)` wrapper to the window's root content view.** Alternative considered: keep `WindowGroup` and only strip its title bar via `.windowStyle(.hiddenTitleBar)` while leaving the inner glass card — rejected because the mockup shows no visible frame at all between the glass surface and the window edge (mockup section: "Acerca de — la ventana es la superficie"); the card must fill the window, not float inside it, matching the pattern the main window uses for `titlebarAppearsTransparent`/`isMovableByWindowBackground`.

**Glass recipe: extend the existing modifiers in place rather than adding new modifier names.** `GlassSurfaceModifier`/`GlassDarkSurfaceModifier` keep their public API (`View.glassSurface()`/`.glassDarkSurface()`) so no call sites elsewhere change; internally, the `.overlay(stroke)` becomes a `LinearGradient` stroke (white ~55% at the top edge fading to ~8-10% at the bottom, per the mockup's `.glass`/`.glass-dark` CSS reference), the `.background` gains a very low-opacity gradient overlay in place of `GlassDarkSurfaceModifier`'s flat `darkTintOpacity` solid fill, `.cornerRadius` becomes `RoundedRectangle(cornerRadius:style: .continuous)`-based clipping, and the single `.shadow` becomes two stacked shadow modifiers (small-radius/low-y contact shadow, larger-radius/higher-y ambient shadow).

**Status bar menu: switch to `.menuBarExtraStyle(.window)`.** This is the only style that renders arbitrary SwiftUI content (required for the glass-dark surface, now-playing thumbnail, and real transport buttons the mockup shows) instead of coercing content into native `NSMenu` items. `StatusBarMenuView`'s existing button/toggle actions are preserved; the body gains a now-playing header row (small thumbnail + title, reusing `wallpaperManager.currentVideo`) and transport buttons above the existing menu-style rows, all wrapped in `.glassDarkSurface()`.

**Resizability: `.windowResizability(.contentMinSize)` with `.frame(minWidth: 960, minHeight: 640)` on `ContentView`, applied only to the main `WindowGroup`.** The About `WindowGroup` keeps its current fixed sizing (no resizability change) since the mockup specifies it stays fixed at 360×420. The library rail's visibility toggle already exists as `@State`; at/below the minimum width it defaults to hidden (a `GeometryReader`-driven or window-frame-observed check, consistent with how the toggle already gates rail visibility) rather than adding a second independent visibility mechanism.

## Risks / Trade-offs

- [Embedding a second `AVQueuePlayer` construction path for the in-window preview, separate from `DesktopVideoWindowMejorada`'s desktop-wallpaper player] → Both play the same asset muted, so behavior stays consistent; keep the `NSViewRepresentable` thin (construction + item-swap only) so the pattern stays easy to compare against :234-261 if either needs to change later.
- [Making the main window resizable for the first time could expose layout edge cases in the floating panels (e.g. bottom bar width calc at `right:376px` fixed offset in the mockup) at sizes between 640 and full width] → Verify manually across the documented range (960×640 minimum through a large display) as part of tasks' verification step, per the mockup's own default/minimum/about size table.
- [Relocating mute and per-video actions before deleting `sidebarView` still touches a large, already-large `ContentView.swift` (1279 lines)] → Keep the relocation and the deletion as separate reviewable steps (see Decisions) rather than one large diff, so a regression is easy to bisect.
- [`.menuBarExtraStyle(.window)` changes how the status item behaves on click (window-style popover vs. native menu dismiss behavior)] → Confirm existing keyboard shortcuts (⌘O/⌘S/⌘P/⌘N/⌘U/⌘Q) and click-outside-to-dismiss still work under `.window` style during verification; this is a known behavioral difference of the API, not a bug to fix around.
