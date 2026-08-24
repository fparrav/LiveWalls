import SwiftUI
import Foundation
import AVKit

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @State private var isImporting = false
    @State private var selectedVideo: VideoFile?
    @State private var showSettings = false
    @State private var localIsShuffleMode: Bool = false
    @State private var localIsPlaying: Bool = false
     // Backed by the same "MuteVideo" UserDefaults key `DesktopVideoWindowMejorada`
     // reads at player setup. `@AppStorage` (not a plain UserDefaults read in the
     // button's body) so the speaker icon actually redraws when tapped -- a bare
     // `UserDefaults.standard.bool(forKey:)` read doesn't trigger a SwiftUI
     // view update, so the icon looked stuck even though the preference changed.
     @AppStorage("MuteVideo") private var isMuteEnabled: Bool = false
     // Task 2.4: local flag controlling the library rail's visibility in the
     // main window. Toggled by `libraryToggleButton`; consumed by the library
     // rail added in task 2.5.
     @State private var isLibraryRailVisible: Bool = false

     // Task 6.2: the window's current content size, tracked so the library
     // rail can be force-hidden as the window nears its 960x640 minimum,
     // where it would otherwise overlap the bottom rotation bar.
     @State private var windowSize: CGSize = .zero

     // Below this width/height the library rail is considered too close to
     // the 960x640 minimum to safely coexist with the bottom rotation bar.
     private let libraryRailAutoHideSize = CGSize(width: 1040, height: 700)

    var body: some View {
          // Floating-glass layout over a full-bleed video preview: the active
          // video renders as a live full-bleed background, with the
          // playback/library controls presented as floating glass panels on top.
        ZStack {
                 // Layer 1: full-bleed video preview background.
             videoPreviewLayer

                 // Layer 2: floating glass controls on top of the preview.
             floatingControlsLayer
          }
        .frame(minWidth: 960, minHeight: 640)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { windowSize = geometry.size }
                    .onChange(of: geometry.size) { newSize in
                        windowSize = newSize
                        if isLibraryRailVisible
                            && (newSize.width <= libraryRailAutoHideSize.width
                                || newSize.height <= libraryRailAutoHideSize.height) {
                            isLibraryRailVisible = false
                        }
                    }
            }
        )
          // Hide the native title bar so the real system traffic lights float
          // directly over the video preview, with no opaque strip beneath them.
          // The Scene-level `.windowStyle(.hiddenTitleBar)` (LiveWallsApp.swift)
          // does the heavy lifting; this just confirms the same intent at the
          // NSWindow level in case the window is ever hosted differently.
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // AppKit's own frame-autosave (keyed off the WindowGroup id) can
            // restore or cascade the window partly off-screen after a display
            // change (e.g. disconnecting an external monitor). Re-center
            // whenever the current frame isn't fully visible so controls near
            // the window edges stay reachable.
            if let screen = window.screen ?? NSScreen.main,
                !screen.visibleFrame.contains(window.frame) {
                window.center()
            }
        })
        .ignoresSafeArea()
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                print("🎬 Importando \(urls.count) videos: \(urls.map { $0.lastPathComponent })")
                Task {
                    await wallpaperManager.addVideoFiles(urls: urls)
                }
            case .failure(let error):
                print("❌ Error al importar videos: \(error.localizedDescription)")
            }
        }
        .onAppear {
            localIsShuffleMode = wallpaperManager.isShuffleMode
            localIsPlaying = wallpaperManager.isPlayingWallpaper
        }
        .onChange(of: wallpaperManager.isPlayingWallpaper) { newValue in
            localIsPlaying = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowMainWindow"))) { _ in
            // Si la ventana está oculta, traerla al frente
            if let window = NSApp.windows.first(where: { !$0.isVisible && !($0 is NSPanel) }) ?? NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    
    // MARK: - Vistas computadas
    
     /// Full-bleed video preview background layer.
     ///
     /// Shows the active wallpaper actually playing (muted, looping) via
     /// `LiveVideoPreviewView`, filling the window. Falls back to a solid dark
     /// background when there is no current video, surfacing the empty-state
     /// view when there are no videos at all.
     @ViewBuilder
    private var videoPreviewLayer: some View {
         if let currentVideo = wallpaperManager.currentVideo, currentVideo.bookmarkData != nil {
             LiveVideoPreviewView(video: currentVideo, bookmarkActor: wallpaperManager.bookmarkActor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
          } else {
             ZStack {
                 Color.black
                     .frame(maxWidth: .infinity, maxHeight: .infinity)
                 if wallpaperManager.videoFiles.isEmpty {
                     emptyStateView
                 }
             }
          }
      }

     /// Floating glass controls layer that sits on top of the video preview.
     ///
     /// Task 2.1 placeholder: intentionally empty. Tasks 2.2-2.6 add the transport
     /// pill, library-toggle button, library rail, and rotation bar as floating glass
     /// panels positioned inside this layer.
     ///
     /// Task 2.8 accessibility-identifier mapping (old `sidebarView`/`bottomControlsView`
     /// identifier -> new floating-control identifier):
     ///   sidebar_settings_button    -> main_settings_button   (trafficLightPill)
     ///   sidebar_play_toggle_button -> main_transport_play_toggle_button (transportPill)
     ///   sidebar_next_button        -> main_transport_next_button (transportPill; a new
     ///                                 main_transport_previous_button was also added,
     ///                                 no old equivalent existed)
     ///   sidebar_import_button      -> library_import_button  (libraryRail)
     ///   sidebar_autochange_toggle  -> bottom_bar_autochange_toggle (bottomGlassBar)
     ///   sidebar_interval_picker    -> bottom_bar_interval_picker  (bottomGlassBar)
     ///   sidebar_mode_picker        -> bottom_bar_mode_picker      (bottomGlassBar)
     ///   sidebar_mute_button        -> (no floating equivalent yet; mute stays
     ///                                 reachable only via the still-unused sidebarView
     ///                                 until it is fully retired)
     ///   bottom_set_wallpaper_button, bottom_delete_button -> (no floating equivalent
     ///                                 yet; per-video actions now live on `library_row_*`
     ///                                 taps, no dedicated set/delete controls added)
     ///   (new, no old equivalent) main_library_toggle_button, library_rail,
     ///                                 library_row_*, bottom_bar_video_count
     @ViewBuilder
    private var floatingControlsLayer: some View {
          // Tasks 2.3-2.6 add the transport pill, top-trailing controls, library
          // rail, and rotation bar as floating glass panels inside the SAME ZStack,
          // each with its own alignment/.position.
        ZStack(alignment: .topLeading) {
             // Tap-outside-to-dismiss catcher for the library rail and
             // settings panel: a near-invisible full-size layer placed BELOW
             // every floating control in z-order (declared first, so
             // transportPill/topTrailingControls/bottomGlassBar render on top
             // and keep receiving their own taps), that only exists while
             // one of the panels is visible and simply closes it on tap --
             // mirrors how a native popover dismisses when you click outside it.
            if isLibraryRailVisible || showSettings {
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLibraryRailVisible = false
                            showSettings = false
                        }
                    }
                    .accessibilityHidden(true)
            }

             // Task 2.3: top-center glass transport pill. Spans the full layered
             // width so it centers horizontally, anchored to the top edge with the
             // shared outer margin. Tasks 2.4-2.6 add the library toggle, library
             // rail, and rotation bar inside the SAME ZStack.
            transportPill
                  .frame(maxWidth: .infinity, alignment: .top)
                  .padding(.top, LiquidGlassMetrics.outerMargin)

             // Top-trailing control group: settings and library-toggle sit
             // together on the right (the native traffic lights are the only
             // thing at the top-left, so nothing else competes with them for
             // space there), matching icon sizes between the two.
            topTrailingControls
                // `containerRelativeFrame(.horizontal)` sizes THIS view to a
                // fraction of the ZStack's width and then places it inside
                // that ZStack per its own `.topLeading` alignment -- so a
                // 30%-wide box (meant for the transport pill's marquee
                // effect) ended up anchoring the settings/library icons near
                // the LEFT edge instead of the right. `.frame(maxWidth:
                // .infinity, alignment: .trailing)` is the correct way to
                // push a compact, content-sized view to the trailing edge of
                // a wider parent.
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, LiquidGlassMetrics.outerMargin)
                .padding(.trailing, LiquidGlassMetrics.outerMargin)
            // Task 2.5: right-side glass-dark library rail. Anchored to the
            // trailing edge, revealed only when `isLibraryRailVisible` is true
            // (toggled by `libraryToggleButton`). The top padding keeps it below
            // the top control row (pill height + two outer margins) so it never
            // overlaps `trafficLightPill` / `transportPill` / `libraryToggleButton`.
            if isLibraryRailVisible {
                libraryRail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, LiquidGlassMetrics.pillHeight + LiquidGlassMetrics.outerMargin * 2)
                .padding(.trailing, LiquidGlassMetrics.outerMargin)
                // Clears the bottom glass bar (height + its own bottom margin),
                // which otherwise overlaps the rail's last row and blocks its
                // per-card action buttons (set wallpaper / delete / shuffle).
                .padding(.bottom, LiquidGlassMetrics.bottomBarHeight + LiquidGlassMetrics.outerMargin * 2)
                .transition(.move(edge: .trailing))
            }

            // Settings floating panel: same top-trailing anchor and z-order
            // as the library rail (never shown at the same time -- opening
            // one closes the other, see `topTrailingControls`), replacing the
            // old modal `.sheet` so it can be dismissed by tapping outside it
            // like a native popover, via the shared catcher above.
            if showSettings {
                settingsPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, LiquidGlassMetrics.pillHeight + LiquidGlassMetrics.outerMargin * 2)
                .padding(.trailing, LiquidGlassMetrics.outerMargin)
                .padding(.bottom, LiquidGlassMetrics.outerMargin)
                .transition(.move(edge: .trailing))
            }
            // Task 2.6: bottom glass bar with the auto-rotation controls and
            // video count. Anchored to the bottom edge of the layered controls,
            // centered, and sized to `bottomBarWidthRatio` of the window's
            // current width so it reads as a distinct, narrower control strip
            // rather than spanning edge to edge like the top-row pills.
            bottomGlassBar
                .frame(width: windowSize.width > 0 ? windowSize.width * LiquidGlassMetrics.bottomBarWidthRatio : nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, LiquidGlassMetrics.outerMargin)
            }
     }

      /// Top-trailing glass control group for the main window's floating-glass
      /// layer: settings entry point and library-toggle button, side by side,
      /// both on the right so neither competes with the native traffic lights
      /// (top-left) or the transport pill (top-center). Both buttons share the
      /// same `LiquidGlassMetrics.pillHeight` (36px) and `.imageScale(.medium)`
      /// icon size so they read as one consistent pair rather than two
      /// mismatched controls.
      @ViewBuilder
    private var topTrailingControls: some View {
        HStack(spacing: 12) {
             // Settings entry point - the only way to reach `SettingsView` once
             // the old `sidebarView`'s `sidebar_settings_button` is retired.
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLibraryRailVisible = false
                    showSettings.toggle()
                }
             }) {
                Image(systemName: "gearshape.fill")
                     .imageScale(.medium)
             }
             .buttonStyle(.borderless)
             .padding(.horizontal, 12)
             .frame(height: LiquidGlassMetrics.pillHeight)
             .glassSurface()
             .accessibilityIdentifier("main_settings_button")
             .accessibilityLabel(NSLocalizedString("settings_button", comment: "Settings button"))

            libraryToggleButton
         }
     }

    /// Top-center glass transport pill for the main window's floating-glass layer.
    ///
    /// Presents a "previous / play-pause / next" transport group plus the current
    /// wallpaper filename as a single floating glass pill. Actions reuse the
    /// `sidebarView` playback logic: play/pause toggles through the local
    /// `localIsPlaying` mirror, while next and previous route through the async
    /// `wallpaperManager` methods, which already honor the configured list/shuffle
    /// mode. `previous` is disabled when the manager reports it is unavailable.
    @ViewBuilder
    private var transportPill: some View {
        HStack(spacing: 4) {
             // Previous wallpaper - disabled when no earlier video is available.
            Button(action: {
                Task {
                    await wallpaperManager.previousWallpaper()
                 }
             }) {
                Image(systemName: "backward.fill")
             }
              .buttonStyle(.borderless)
              .disabled(!wallpaperManager.canGoToPreviousWallpaper)
              .accessibilityIdentifier("main_transport_previous_button")
              .padding(.horizontal, 4)

             // Play/Stop button - same local-mirror pattern as `sidebarView`.
            Button(action: {
                if localIsPlaying {
                    localIsPlaying = false
                    wallpaperManager.stopWallpaperSafe()
                 } else {
                    localIsPlaying = true
                    wallpaperManager.startWallpaperSafe()
                 }
             }) {
                Image(systemName: localIsPlaying ? "stop.fill" : "play.fill")
             }
              .buttonStyle(.borderless)
              .imageScale(.large)
              .accessibilityIdentifier("main_transport_play_toggle_button")
              .padding(.horizontal, 4)

             // Current wallpaper filename, with a localized fallback when nil.
             // MarqueeText scrolls long filenames (same pattern as
             // StatusBarMenuView); .id() resets the scroll when the video changes.
            Group {
                if let currentVideo = wallpaperManager.currentVideo {
                    MarqueeText(text: currentVideo.name, font: .subheadline, foregroundColor: .primary)
                        .id(currentVideo.name)
                } else {
                    Text(NSLocalizedString("no_active_wallpaper", comment: "No active wallpaper"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
             }
              // `MarqueeText`'s internal `GeometryReader` has no intrinsic
              // width, so without a `maxWidth` cap here it greedily fills all
              // remaining HStack space and stretches the whole pill edge to
              // edge instead of staying a compact floating control.
              .frame(minWidth: 120, maxWidth: 220, alignment: .center)

             // Next wallpaper.
            Button(action: {
                Task {
                    await wallpaperManager.nextWallpaper()
                 }
             }) {
                Image(systemName: "forward.fill")
             }
              .buttonStyle(.borderless)
              .accessibilityIdentifier("main_transport_next_button")
              .padding(.horizontal, 4)

            Divider()
                 .frame(height: 16)
                 .overlay(LiquidGlassMetrics.dividerColor)

             // Mute/unmute - same `UserDefaults`/`MuteVideo` logic previously
             // only reachable via the dead `sidebarView`'s `sidebar_mute_button`.
             // Also pushes the new value to any already-playing desktop
             // wallpaper windows, since they read this preference once at
             // player setup and otherwise wouldn't pick up the change until
             // the video/window was recreated.
            Button(action: {
                isMuteEnabled.toggle()
                wallpaperManager.applyMuteSettingToActiveWindows()
             }) {
                Image(systemName: isMuteEnabled ? "speaker.slash.fill" : "speaker.wave.2.fill")
             }
              .buttonStyle(.borderless)
              .accessibilityIdentifier("main_transport_mute_button")
              .padding(.horizontal, 4)
              .accessibilityLabel(
                isMuteEnabled
                    ? NSLocalizedString("unmute_button", comment: "Unmute button")
                    : NSLocalizedString("mute_button", comment: "Mute button")
              )
        }
        .frame(height: LiquidGlassMetrics.bottomBarHeight)
        .glassSurface()
    }

     /// Top-right glass library-toggle button for the main window's
     /// floating-glass layer.
     ///
     /// Presents a pill with a library icon (`rectangle.grid.1x2`) that toggles
     /// `isLibraryRailVisible`, revealing the glass library rail added in task 2.5.
     /// Rendered with the shared light `glassSurface()` treatment, sized to the
     /// standard `LiquidGlassMetrics.pillHeight` (36px), and anchored to the
     /// top-right with the shared `LiquidGlassMetrics.outerMargin` (20px) clearance
     /// from the window edges via the host ZStack framing in `floatingControlsLayer`.
     @ViewBuilder
     private var libraryToggleButton: some View {
         Button(action: {
             // Local show/hide state -- not persisted (design decision 4).
             // The library rail consumed by this flag arrives in task 2.5.
             withAnimation(.easeInOut(duration: 0.2)) {
                 showSettings = false
                 isLibraryRailVisible.toggle()
             }
         }) {
             Image(systemName: "square.grid.2x2")
                 .imageScale(.medium)
         }
         .buttonStyle(.borderless)
         .padding(.horizontal, 12)
         .frame(height: LiquidGlassMetrics.pillHeight)
         .glassSurface()
         .accessibilityIdentifier("main_library_toggle_button")
     }

      /// Right-side glass-dark library rail (240px) for the main window's
      /// floating-glass layer.
      ///
      /// Task 2.5: a tall panel anchored to the trailing window edge, rendered with
      /// the shared dark `glassDarkSurface()` treatment. This is a panel over an
      /// opaque background (not a control floating over the live preview), so it
      /// uses the dark style per design.md. Presents, top-down:
      ///      - a "Biblioteca" header with an "Importar" action wired to the existing
      ///        `isImporting` file importer already mounted on the `body`,
      ///      - a scrollable list of `wallpaperManager.videoFiles`, one compact row
      ///    per video (name + path), with an accent badge on the current wallpaper.
      ///
      /// Reuses existing shared state only (`videoFiles`, `currentVideo`,
      /// `selectedVideo`, `isImporting`) -- no new manager behavior. Tapping a row
      /// sets `selectedVideo`. Empty-library state reuses existing localized copy.
      @ViewBuilder
     private var libraryRail: some View {
         VStack(alignment: .leading, spacing: 12) {
              // Header: title + Importar action (reuses the `isImporting` importer).
             HStack(spacing: 8) {
                 Text("Biblioteca")
                      .font(.headline)
                      .foregroundStyle(.primary)

                 Spacer(minLength: 8)

                 Button(action: { isImporting = true }) {
                     Image(systemName: "plus.circle.fill")
                          .imageScale(.large)
                  }
                  .buttonStyle(.borderless)
                  .help(NSLocalizedString("import_button", comment: "Import button"))
                  .accessibilityIdentifier("library_import_button")
              }

             Divider()
                  .overlay(LiquidGlassMetrics.dividerColor)

              // Scrollable video list, or the localized empty state.
             if wallpaperManager.videoFiles.isEmpty {
                 VStack(spacing: 8) {
                     Text(NSLocalizedString("no_videos_title", comment: "No videos title"))
                          .font(.subheadline)
                          .foregroundStyle(.secondary)
                     Text(NSLocalizedString("no_videos_description", comment: "No videos description"))
                          .font(.caption)
                          .foregroundStyle(.secondary)
                          .multilineTextAlignment(.center)
                  }
                  .frame(maxWidth: .infinity, alignment: .center)
                  .padding(.vertical, 16)
              } else {
                 ScrollView {
                     LazyVStack(spacing: 12) {
                         ForEach(Array(wallpaperManager.videoFiles.enumerated()), id: \.element.id) { index, video in
                             libraryRow(video: video, index: index)
                                 .onDrop(of: [.text], delegate: VideoDropDelegate(
                                    wallpaperManager: wallpaperManager,
                                    currentIndex: index,
                                    isShuffleMode: localIsShuffleMode
                                 ))
                          }
                      }
                      .padding(.horizontal, 4)
                  }
              }
         }
         .padding(LiquidGlassMetrics.cardCornerRadius)
         .frame(width: LiquidGlassMetrics.railWidth)
         .glassDarkSurface()
         // Without `.contain`, this container's own identifier leaks onto
         // every descendant (including ones with their own identifier, e.g.
         // `library_import_button`), overriding them in the AX tree.
         .accessibilityElement(children: .contain)
         .accessibilityIdentifier("library_rail")
     }

      /// Top-right floating settings panel for the main window's
      /// floating-glass layer.
      ///
      /// Replaces the old modal `.sheet(isPresented: $showSettings)`
      /// presentation with an inline `SettingsView`, anchored the same way as
      /// `libraryRail` so it can be dismissed by tapping outside it (via the
      /// shared catcher in `floatingControlsLayer`) instead of requiring its
      /// own Cancel/Accept button.
      @ViewBuilder
     private var settingsPanel: some View {
         SettingsView(onClose: {
             withAnimation(.easeInOut(duration: 0.2)) {
                 showSettings = false
             }
         })
         .environmentObject(wallpaperManager)
         .environmentObject(launchManager)
         .accessibilityElement(children: .contain)
         .accessibilityIdentifier("settings_panel")
     }

      /// Full-width 16:9 library-rail card for a single video.
      ///
      /// Anatomy matches the mockup: thumbnail (with an on-demand resolution
      /// badge and an "EN PANTALLA" badge on the active card), filename, and a
      /// per-card action row - set as background, delete, reorder (drag handle),
      /// and an "en aleatorio" (include-in-shuffle) checkbox - wired to the same
      /// `wallpaperManager`/`selectedVideo` calls the dead `sidebarView`/
      /// `VideoThumbnailCard` already used.
      @ViewBuilder
     private func libraryRow(video: VideoFile, index: Int) -> some View {
         let isActive = wallpaperManager.currentVideo?.id == video.id

         VStack(alignment: .leading, spacing: 8) {
              // Thumbnail (16:9) with badges overlay.
             //
             // The badges are attached via `.overlay(alignment:)` on the
             // ALREADY-SIZED thumbnail `Group` rather than as a `ZStack`
             // sibling. A `ZStack` re-negotiates size across every child
             // simultaneously, and `aspectRatio(...) .frame(maxWidth:
             // .infinity)` inside a `LazyVStack` can resolve to an
             // oversized/ambiguous proposal in that negotiation -- which
             // silently anchored the "EN PANTALLA" badge to a frame far
             // wider than what's actually visible, pushing it outside the
             // card. `.overlay` positions its content strictly against the
             // base view's own already-resolved frame, so the badge can
             // never be placed (or clipped) relative to the wrong size.
             Group {
                 if let thumbnailData = video.thumbnailData,
                    let nsImage = NSImage(data: thumbnailData) {
                     Image(nsImage: nsImage)
                          .resizable()
                          .aspectRatio(contentMode: .fill)
                  } else {
                     RoundedRectangle(cornerRadius: LiquidGlassMetrics.controlCornerRadius)
                          .fill(Color.white.opacity(0.10))
                  }
              }
              .frame(maxWidth: .infinity)
              .aspectRatio(16.0 / 9.0, contentMode: .fill)
              .clipShape(RoundedRectangle(cornerRadius: LiquidGlassMetrics.controlCornerRadius))
              .overlay(alignment: .topTrailing) {
                 VStack(alignment: .trailing, spacing: 4) {
                     if isActive {
                         Text(NSLocalizedString("on_screen_badge", comment: "On-screen badge"))
                              .font(.system(size: 10, weight: .semibold))
                              .lineLimit(1)
                              .fixedSize()
                              .padding(.horizontal, 6)
                              .padding(.vertical, 3)
                              .background(LiquidGlassMetrics.accentColor, in: Capsule())
                              .foregroundStyle(.white)
                              .accessibilityIdentifier("library_row_\(video.id)_on_screen_badge")
                      }
                     LibraryRowResolutionBadge(video: video, bookmarkActor: wallpaperManager.bookmarkActor)
                  }
                  .padding(6)
              }

              // Name + path.
             VStack(alignment: .leading, spacing: 2) {
                 Text(video.name)
                      .font(.system(size: 13, weight: .medium))
                      .lineLimit(1)
                 Text(video.url.lastPathComponent)
                      .font(.system(size: 11))
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
              }

              // Per-card actions: set as background, delete, reorder, shuffle-inclusion.
             HStack(spacing: 14) {
                 Button(action: { wallpaperManager.setAsCurrentWallpaper(video: video) }) {
                     Image(systemName: "pin.fill")
                  }
                  .buttonStyle(.borderless)
                  .help(NSLocalizedString("set_as_wallpaper", comment: "Set as wallpaper"))
                  .accessibilityIdentifier("library_row_\(video.id)_set_wallpaper_button")

                 Button(action: {
                     wallpaperManager.removeVideo(video)
                     if selectedVideo?.id == video.id { selectedVideo = nil }
                  }) {
                     Image(systemName: "trash")
                  }
                  .buttonStyle(.borderless)
                  .help(NSLocalizedString("delete_button", comment: "Delete"))
                  .accessibilityIdentifier("library_row_\(video.id)_delete_button")

                 Toggle(isOn: Binding(
                     get: { video.isEnabledForRandomPlay },
                     set: { _ in wallpaperManager.toggleVideoRandomPlayEnabled(video) }
                 )) {
                     Image(systemName: "shuffle")
                 }
                 .toggleStyle(.button)
                 .buttonStyle(.borderless)
                 .help(NSLocalizedString(
                    video.isEnabledForRandomPlay ? "disable_for_random" : "enable_for_random",
                    comment: "Include in shuffle rotation"
                 ))
                 .accessibilityIdentifier("library_row_\(video.id)_shuffle_toggle")

                 Spacer(minLength: 4)

                 // Reorder drag handle.
                 Image(systemName: "line.3.horizontal")
                      .foregroundStyle(.secondary)
                      .accessibilityIdentifier("library_row_\(video.id)_reorder_handle")
                      .onDrag {
                          let indexString = "\(index)" as NSString
                          return NSItemProvider(object: indexString)
                      }
              }
              .imageScale(.medium)
         }
         .padding(10)
         .background(
             RoundedRectangle(cornerRadius: LiquidGlassMetrics.controlCornerRadius)
                 .fill(isActive ? LiquidGlassMetrics.accentColor.opacity(0.15) : Color.white.opacity(0.06))
         )
         .overlay(
             RoundedRectangle(cornerRadius: LiquidGlassMetrics.controlCornerRadius)
                 .stroke(
                     isActive ? LiquidGlassMetrics.accentColor.opacity(0.6) : LiquidGlassMetrics.dividerColor,
                     lineWidth: LiquidGlassMetrics.dividerWidth
                 )
         )
         .contentShape(Rectangle())
         .onTapGesture { selectedVideo = video }
         // See `libraryRail`: without `.contain`, this row's own identifier
         // would leak onto its per-card action buttons, overriding them.
         .accessibilityElement(children: .contain)
         .accessibilityIdentifier("library_row_\(video.id)")
     }


    /// Bottom glass bar with the auto-rotation controls and video count.
        ///
        /// Task 2.6: floating light-glass bar anchored to the bottom edge of the
        /// layered controls. Reuses the exact same bindings as the `sidebarView`
        /// rotation controls (which remain until tasks 2.7-2.9 retire them):
        /// the auto-change toggle, the interval menu picker (visible only when
        /// auto-change is enabled), the playlist/shuffle segmented picker
        /// (mirrored through the existing `localIsShuffleMode` state), and the
        /// localized total video count.
        @ViewBuilder
        private var bottomGlassBar: some View {
            HStack(spacing: 12) {
                // Auto-rotation toggle - same get/set binding as `sidebarView`.
                Toggle(NSLocalizedString("enable_auto_change", comment: "Enable auto-change toggle"), isOn: Binding(
                    get: { wallpaperManager.isAutoChangeEnabled },
                    set: { newValue in wallpaperManager.isAutoChangeEnabled = newValue }
                ))
                .toggleStyle(.switch)
                .accessibilityIdentifier("bottom_bar_autochange_toggle")

                // Interval picker - visible only when auto-change is enabled.
                if wallpaperManager.isAutoChangeEnabled {
                    Picker("", selection: Binding(
                        get: { Int(wallpaperManager.autoChangeInterval / 60) },
                        set: { newValue in wallpaperManager.autoChangeInterval = TimeInterval(newValue * 60) }
                    )) {
                        ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("bottom_bar_interval_picker")
                }

                // Playlist/shuffle segmented picker - visible only when auto-change
                // is enabled. Mirrors the manager value through `localIsShuffleMode`
                // exactly like `sidebarView` does.
                if wallpaperManager.isAutoChangeEnabled {
                    Picker("", selection: $localIsShuffleMode) {
                        Text(NSLocalizedString("playlist_mode", comment: "Playlist mode")).tag(false)
                        Text(NSLocalizedString("shuffle_mode", comment: "Shuffle mode")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("bottom_bar_mode_picker")
                    .onChange(of: localIsShuffleMode) { newValue in
                        wallpaperManager.isShuffleMode = newValue
                    }
                    .onChange(of: wallpaperManager.isShuffleMode) { newValue in
                        if localIsShuffleMode != newValue {
                            localIsShuffleMode = newValue
                        }
                    }
                }

                Spacer(minLength: 8)

                // Total video count - same localization key as `sidebarView`.
                Text(String(format: NSLocalizedString("videos_total", comment: "Videos total count"), wallpaperManager.videoFiles.count))
                    .accessibilityIdentifier("bottom_bar_video_count")
            }
            .padding(.horizontal, 12)
            .frame(height: LiquidGlassMetrics.bottomBarHeight)
            .glassSurface()
        }

    /// Vista para estado vacío
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "video.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(NSLocalizedString("no_videos_title", comment: "No videos title"))
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text(NSLocalizedString("no_videos_description", comment: "No videos description"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: {
                isImporting = true
            }) {
                Label(NSLocalizedString("import_videos_button", comment: "Import videos button"), systemImage: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("empty_import_button")
            
            Spacer()
        }
    }
    

    
    /// Controles inferiores con acciones para el video seleccionado
    @ViewBuilder
    private var bottomControlsView: some View {
        HStack {
            // Información del video actual
            VStack(alignment: .leading, spacing: 4) {
                if let currentVideo = wallpaperManager.currentVideo {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(String(format: NSLocalizedString("active_wallpaper", comment: "Active wallpaper status"), currentVideo.name))
                            .font(.caption)
                            .lineLimit(1)
                    }
                } else {
                    Text(NSLocalizedString("no_active_wallpaper", comment: "No active wallpaper"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(String(format: NSLocalizedString("videos_total", comment: "Videos total count"), wallpaperManager.videoFiles.count))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Drag & drop hint (only show if there are videos)
                if !wallpaperManager.videoFiles.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down.circle")
                            .font(.caption2)
                        Text(NSLocalizedString("drag_drop_hint", comment: "Drag and drop hint"))
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Botones de acción para video seleccionado
            HStack(spacing: 12) {
                // Botón establecer como wallpaper
                Button(action: {
                    if let video = selectedVideo {
                        print("🌟 Estableciendo wallpaper: \(video.name) (ID: \(video.id))")
                        wallpaperManager.setAsCurrentWallpaper(video: video)
                        print("✅ Comando setAsCurrentWallpaper enviado")
                    } else {
                        print("❌ No hay video seleccionado para establecer como wallpaper")
                    }
                }) {
                    Label(NSLocalizedString("set_as_wallpaper", comment: "Set as wallpaper"), systemImage: "pin.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedVideo == nil)
                .accessibilityIdentifier("bottom_set_wallpaper_button")
                
                // Botón eliminar
                Button(action: {
                    if let video = selectedVideo {
                        wallpaperManager.removeVideo(video)
                        selectedVideo = nil
                    }
                }) {
                    Label(NSLocalizedString("delete_button", comment: "Delete"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(selectedVideo == nil)
                .accessibilityIdentifier("bottom_delete_button")
            }
        }
        .padding()
    }
}

// MARK: - Componentes de UI

// Mantenemos VideoRowView por compatibilidad (por si se usa en otro lugar)
struct VideoRowView: View {
    let video: VideoFile

    var body: some View {
        HStack {
            // Debug: Mostrar información del video
            if let thumbnailData = video.thumbnailData, let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 40)
                    .cornerRadius(4)
                    .clipped()
            } else {
                // Mostrar icono por defecto con indicador visual
                Image(systemName: "video.slash")
                    .frame(width: 60, height: 40)
                    .foregroundColor(.gray)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(video.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(video.url.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(spacing: 4) {
                if video.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Drag & Drop Support (PHASE 4)

/// Drop delegate for reordering videos via drag and drop
/// Active in both Playlist and Shuffle modes for library organization
// MARK: - Library Row Resolution Badge

/// On-demand resolution badge for a library-rail card.
///
/// `VideoFile` does not persist the video's real pixel dimensions (its stored
/// thumbnail is a fixed 120x80 clamp, not representative), and per design.md
/// this change does not touch `WallpaperManager`/persistence to add a new
/// stored field. Instead this reads the natural size directly from the
/// video's `AVAsset` track each time the row appears, purely for display; the
/// badge is simply omitted while loading or if it cannot be read.
private struct LibraryRowResolutionBadge: View {
    let video: VideoFile
    let bookmarkActor: BookmarkActor

    @State private var resolutionText: String?

    var body: some View {
        Group {
            if let resolutionText {
                Text(resolutionText)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .task(id: video.id) {
            resolutionText = nil
            guard let bookmarkData = video.bookmarkData else { return }
            do {
                let url = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
                guard await bookmarkActor.startAccessingSecurityScopedResource(url: url) else { return }
                defer { Task { await bookmarkActor.stopAccessingSecurityScopedResource(url: url) } }

                let asset = AVURLAsset(url: url)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let size = naturalSize.applying(transform)
                let width = Int(abs(size.width))
                let height = Int(abs(size.height))
                if width > 0 && height > 0 {
                    resolutionText = "\(width)×\(height)"
                }
            } catch {
                // Best-effort presentation-only badge; silently omit on failure.
            }
        }
    }
}

// MARK: - Live Main-Window Preview Player

/// Full-bleed, muted, looping live preview of the active wallpaper video shown
/// in the main window's `videoPreviewLayer`.
///
/// Mirrors `DesktopVideoWindowMejorada.setupPlayer(with:preloadedAsset:)`'s
/// `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer` pattern (muted,
/// `.resizeAspectFill`) rather than embedding that `NSWindow` subclass
/// directly, since it is tied to desktop-wallpaper window management. Updates
/// the player item whenever `video` changes.
struct LiveVideoPreviewView: NSViewRepresentable {
    let video: VideoFile
    let bookmarkActor: BookmarkActor

    func makeNSView(context: Context) -> NSView {
        let containerView = VideoPreviewContainerView()
        containerView.wantsLayer = true
        containerView.layer = CALayer()
        containerView.layer?.backgroundColor = CGColor.black
        configurePlayer(for: video, in: containerView, coordinator: context.coordinator)
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.currentVideoID != video.id else { return }
        configurePlayer(for: video, in: nsView, coordinator: context.coordinator)
    }

    private func configurePlayer(for video: VideoFile, in containerView: NSView, coordinator: Coordinator) {
        coordinator.currentVideoID = video.id
        coordinator.teardown()

        guard let bookmarkData = video.bookmarkData else { return }

        Task {
            do {
                let resolvedURL = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
                let accessGranted = await bookmarkActor.startAccessingSecurityScopedResource(url: resolvedURL)
                guard accessGranted else { return }

                await MainActor.run {
                    guard coordinator.currentVideoID == video.id else {
                        // A newer video was selected while resolving; drop this stale result.
                        Task { await bookmarkActor.stopAccessingSecurityScopedResource(url: resolvedURL) }
                        return
                    }

                    let playerItem = AVPlayerItem(url: resolvedURL)
                    let queuePlayer = AVQueuePlayer(playerItem: playerItem)
                    queuePlayer.volume = 0
                    queuePlayer.isMuted = true

                    let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

                    let playerLayer = AVPlayerLayer(player: queuePlayer)
                    playerLayer.videoGravity = .resizeAspectFill
                    playerLayer.frame = containerView.bounds
                    containerView.layer?.addSublayer(playerLayer)
                    (containerView as? VideoPreviewContainerView)?.playerLayer = playerLayer

                    coordinator.player = queuePlayer
                    coordinator.looper = looper
                    coordinator.playerLayer = playerLayer
                    coordinator.bookmarkActor = bookmarkActor
                    coordinator.resolvedURL = resolvedURL

                    queuePlayer.play()
                }
            } catch {
                print("❌ LiveVideoPreviewView: Failed to resolve bookmark: \(error.localizedDescription)")
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        var currentVideoID: UUID?
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
        var bookmarkActor: BookmarkActor?
        var resolvedURL: URL?

        func teardown() {
            player?.pause()
            player?.removeAllItems()
            looper?.disableLooping()
            looper = nil
            player = nil
            playerLayer?.removeFromSuperlayer()
            playerLayer = nil

            if let resolvedURL = resolvedURL, let bookmarkActor = bookmarkActor {
                Task { await bookmarkActor.stopAccessingSecurityScopedResource(url: resolvedURL) }
            }
            resolvedURL = nil
        }
    }
}

/// Backing view for `LiveVideoPreviewView` that keeps its `AVPlayerLayer`
/// filling the view's bounds across AppKit-driven resizes (window resize,
/// split-view/rail changes) that don't go through SwiftUI's `updateNSView`.
/// `updateNSView` only re-runs when this representable's own inputs change,
/// not merely because the host window resized, so relying on it to keep the
/// layer's frame in sync left stale (non-fullscreen) video during a resize.
/// Overriding `layout()` lets AppKit itself keep the layer's frame current.
final class VideoPreviewContainerView: NSView {
    var playerLayer: AVPlayerLayer?

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}

// MARK: - Video Preview Player
/// Component that displays a looping video preview on hover
struct VideoPreviewPlayer: NSViewRepresentable {
    let video: VideoFile
    let bookmarkActor: BookmarkActor
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer = CALayer()
        
        // Resolve bookmark asynchronously and create player
        Task {
            do {
                // Resolve bookmark to get access to file
                guard let bookmarkData = video.bookmarkData else {
                    print("⚠️ VideoPreviewPlayer: No bookmark data for \(video.name)")
                    return
                }
                
                let resolvedURL = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
                print("✅ VideoPreviewPlayer: Bookmark resolved for \(video.name)")
                
                // Start security scoped access
                let accessGranted = await bookmarkActor.startAccessingSecurityScopedResource(url: resolvedURL)
                guard accessGranted else {
                    print("❌ VideoPreviewPlayer: Failed to start security scoped access for \(video.name)")
                    return
                }
                print("🔓 VideoPreviewPlayer: Security scoped access granted for \(video.name)")
                
                // Create player on main thread
                await MainActor.run {
                    // Create AVPlayer with resolved URL
                    let player = AVPlayer(url: resolvedURL)
                    player.isMuted = true // No audio for preview
                    
                    // Create player layer
                    let playerLayer = AVPlayerLayer(player: player)
                    playerLayer.videoGravity = .resizeAspectFill
                    playerLayer.frame = containerView.bounds
                    
                    // Add layer to view
                    containerView.layer?.addSublayer(playerLayer)
                    
                    // Store player, layer, and URL in coordinator for cleanup
                    context.coordinator.player = player
                    context.coordinator.playerLayer = playerLayer
                    context.coordinator.video = video
                    context.coordinator.bookmarkActor = bookmarkActor
                    context.coordinator.resolvedURL = resolvedURL
                    
                    // Setup looping
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { _ in
                        player.seek(to: .zero)
                        player.play()
                    }
                    
                    // Start playing
                    player.play()
                }
            } catch {
                print("❌ VideoPreviewPlayer: Failed to resolve bookmark: \(error.localizedDescription)")
            }
        }
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update player layer frame if needed
        if let playerLayer = context.coordinator.playerLayer {
            playerLayer.frame = nsView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var video: VideoFile?
        var bookmarkActor: BookmarkActor?
        var resolvedURL: URL?
        
        deinit {
            // Stop bookmark access
            if let resolvedURL = resolvedURL, let bookmarkActor = bookmarkActor {
                Task {
                    await bookmarkActor.stopAccessingSecurityScopedResource(url: resolvedURL)
                    print("🔒 VideoPreviewPlayer: Stopped security scoped access")
                }
            }
            
            // Clean up player and observers
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
            playerLayer?.removeFromSuperlayer()
            playerLayer = nil
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // Ensure cleanup happens
        coordinator.player?.pause()
        coordinator.player?.replaceCurrentItem(with: nil)
        coordinator.player = nil
        coordinator.playerLayer?.removeFromSuperlayer()
        coordinator.playerLayer = nil
    }
}

// MARK: - Video Drop Delegate
struct VideoDropDelegate: DropDelegate {
    let wallpaperManager: WallpaperManager
    let currentIndex: Int
    let isShuffleMode: Bool
    
    func validateDrop(info: DropInfo) -> Bool {
        // Allow drops in both modes (Playlist and Shuffle)
        print("🔍 validateDrop called: isShuffleMode=\(isShuffleMode)")
        return info.hasItemsConforming(to: [.text])
    }
    
    func dropEntered(info: DropInfo) {
        print("👆 dropEntered: hovering over index \(currentIndex)")
    }
    
    func performDrop(info: DropInfo) -> Bool {
        print("🎯 Drop triggered: currentIndex=\(currentIndex), isShuffleMode=\(isShuffleMode)")
        
        // Allow drops in both modes (Playlist and Shuffle)
        // User can organize library regardless of playback mode
        
        guard let item = info.itemProviders(for: [.text]).first else {
            print("⚠️ Drop failed: no text item provider found")
            return false
        }
        
        // Load the dragged video's index asynchronously using NSString
        item.loadObject(ofClass: NSString.self) { (object, error) in
            if let error = error {
                print("❌ Drop failed with error: \(error.localizedDescription)")
                return
            }
            
            guard let sourceIndexString = object as? String,
                  let sourceIndex = Int(sourceIndexString) else {
                print("❌ Drop failed: could not decode index from object")
                return
            }
            
            print("✅ Drop data received: sourceIndex=\(sourceIndex) → currentIndex=\(self.currentIndex)")
            
            // Perform reordering on main thread
            DispatchQueue.main.async {
                self.wallpaperManager.reorderVideos(from: sourceIndex, to: self.currentIndex)
                print("✅ Reordering completed: moved video from \(sourceIndex) to \(self.currentIndex)")
            }
        }
        
        // Return true to indicate drop is accepted and being processed asynchronously.
        return true
    }
}

// Preview temporalmente deshabilitado para resolver errores de compilación
//#Preview {
//    ContentView()
//        .environmentObject(WallpaperManager())
//}
