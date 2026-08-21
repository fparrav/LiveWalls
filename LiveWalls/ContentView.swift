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
     // Task 2.4: local flag controlling the library rail's visibility in the
     // main window. Toggled by `libraryToggleButton`; consumed by the library
     // rail added in task 2.5.
     @State private var isLibraryRailVisible: Bool = false

    // Grid columns para la vista de miniaturas
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
          // Task 2.1: floating-glass layout over a full-bleed video preview.
          // Replaces the previous NavigationSplitView (fixed opaque sidebar + detail pane).
          // The active video now renders as a live full-bleed background, with the
          // playback/library controls to be presented as floating glass panels on top.
          //
          // Incremental step 2.1: only the preview layer and the floating-controls
          // container are wired here. The actual controls (transport pill, library
          // toggle, library rail, rotation bar) arrive in tasks 2.2-2.6. For now the
          // floating layer is an empty placeholder so the preview is visible and the
          // file keeps compiling while the sidebar view code stays in place (unused).
        ZStack {
                 // Layer 1: full-bleed video preview background.
             videoPreviewLayer

                 // Layer 2: floating glass controls on top of the preview.
                 // TODO: transport pill, library toggle, library rail, rotation bar
                 //       are added in tasks 2.2-2.6.
             floatingControlsLayer
          }
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(wallpaperManager)
                .environmentObject(launchManager)
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
    
     /// Full-bleed video preview background layer (task 2.1 placeholder).
     ///
     /// Shows the active video's thumbnail (reusing the existing `thumbnailData`)
     /// scaled to fill the window, falling back to a solid dark background when there
     /// is no current video or thumbnail. A live, rendering video preview is deferred
     /// to a later task; for step 2.1 this layer only needs to be visible and compile.
     @ViewBuilder
    private var videoPreviewLayer: some View {
         if let currentVideo = wallpaperManager.currentVideo,
            let thumbnailData = currentVideo.thumbnailData,
            let nsImage = NSImage(data: thumbnailData) {
             Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
          } else {
             // Task 2.7: surface the preserved empty-state view when there are no
             // videos at all; a simple black background remains for the edge case
             // of videos present but no currentVideo.
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
          // Task 2.2: top-left decorative traffic-light glass pill added.
          // Tasks 2.3-2.6 add the transport pill, library-toggle button, library
          // rail, and rotation bar as floating glass panels inside the SAME ZStack,
          // each with its own alignment/.position.
        ZStack(alignment: .topLeading) {
            trafficLightPill

             // Task 2.3: top-center glass transport pill. Spans the full layered
             // width so it centers horizontally, anchored to the top edge with the
             // shared outer margin. Tasks 2.4-2.6 add the library toggle, library
             // rail, and rotation bar inside the SAME ZStack.
            transportPill
                  .frame(maxWidth: .infinity, alignment: .top)
                  .padding(.top, LiquidGlassMetrics.outerMargin)

             // Task 2.4: top-right glass library-toggle button. Anchored to the
             // top-trailing edge with the shared outer margin on the top and trailing
             // sides (mirrors `trafficLightPill`, which sits top-leading). The rail it
             // reveals arrives in task 2.5.
            libraryToggleButton
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
                .padding(.bottom, LiquidGlassMetrics.outerMargin)
                .transition(.move(edge: .trailing))
            }
            // Task 2.6: bottom glass bar with the auto-rotation controls and
            // video count. Anchored to the bottom edge of the layered controls
            // with the shared outer margin; spans the full width so the
            // controls stay horizontally distributed.
            bottomGlassBar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, LiquidGlassMetrics.outerMargin)
            }
     }

      /// Top-left glass pill for the main window's floating-glass layer.
      ///
      /// Combines the decorative macOS-style traffic-light dots (close / minimize
      /// / zoom - visual only, the real window controls remain the system-provided
      /// native chrome) with the app's settings entry point. The settings button
      /// is the only way to reach `SettingsView` once the old `sidebarView` (whose
      /// `sidebar_settings_button` previously opened it) is retired in tasks
      /// 2.8/2.9 - design.md/spec.md did not carve out a dedicated settings
      /// control for the new floating layout, so it lives here alongside the
      /// other top-left window chrome. Rendered with the shared light
      /// `glassSurface()` treatment and sized to the standard
      /// `LiquidGlassMetrics.pillHeight` (36px), placed at the top-left with the
      /// shared `LiquidGlassMetrics.outerMargin` (20px) clearance from the window
      /// edge via the outer `.padding` below (the host ZStack is `.topLeading`).
      @ViewBuilder
    private var trafficLightPill: some View {
        HStack(spacing: 8) {
             // Decorative dots only - no tappable actions. Colors reference the
             // macOS window-control palette (close / minimize / zoom).
            HStack(spacing: 8) {
                Circle()
                     .fill(Color(red: 1.0, green: 0x5F / 255.0, blue: 0x57 / 255.0))
                     .frame(width: 12, height: 12)
                Circle()
                     .fill(Color(red: 0xFE / 255.0, green: 0xBC / 255.0, blue: 0x2E / 255.0))
                     .frame(width: 12, height: 12)
                Circle()
                     .fill(Color(red: 0x28 / 255.0, green: 0xC8 / 255.0, blue: 0x40 / 255.0))
                     .frame(width: 12, height: 12)
             }
             .accessibilityHidden(true)

            Divider()
                 .frame(height: 16)
                 .overlay(LiquidGlassMetrics.dividerColor)

             // Settings entry point - the only way to reach `SettingsView` once
             // the old `sidebarView`'s `sidebar_settings_button` is retired.
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                     .imageScale(.small)
             }
             .buttonStyle(.borderless)
             .accessibilityIdentifier("main_settings_button")
             .accessibilityLabel(NSLocalizedString("settings_button", comment: "Settings button"))
         }
         .padding(.horizontal, 12)
         .frame(height: LiquidGlassMetrics.pillHeight)
         .glassSurface()
         .padding(LiquidGlassMetrics.outerMargin)
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
        HStack(spacing: 8) {
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

             // Current wallpaper filename, with a localized fallback when nil.
            Text(
                wallpaperManager.currentVideo?.name
                        ?? NSLocalizedString("no_active_wallpaper", comment: "No active wallpaper")
             )
              .font(.subheadline)
              .foregroundStyle(.primary)
              .lineLimit(1)
              .multilineTextAlignment(.center)
              .frame(minWidth: 120, alignment: .center)

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
        }
        .frame(height: LiquidGlassMetrics.pillHeight)
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
                 isLibraryRailVisible.toggle()
             }
         }) {
             Image(systemName: "rectangle.grid.1x2")
                 .imageScale(.large)
         }
         .buttonStyle(.borderless)
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
                     LazyVStack(spacing: 8) {
                         ForEach(wallpaperManager.videoFiles, id: \.id) { video in
                             libraryRow(video: video)
                          }
                      }
                      .padding(.horizontal, 4)
                  }
              }
         }
         .padding(LiquidGlassMetrics.cardCornerRadius)
         .frame(width: LiquidGlassMetrics.railWidth)
         .glassDarkSurface()
         .accessibilityIdentifier("library_rail")
     }

      /// Compact library-rail row for a single video.
      ///
      /// Shows a thumbnail (when available) plus the video name and path, and an
      /// accent dot/badge when this video is the current wallpaper. Tapping sets
      /// `selectedVideo` (the same selection state used elsewhere in the view).
      @ViewBuilder
     private func libraryRow(video: VideoFile) -> some View {
         let isActive = wallpaperManager.currentVideo?.id == video.id

         HStack(spacing: 10) {
              // Thumbnail or fallback placeholder.
             Group {
                 if let thumbnailData = video.thumbnailData,
                    let nsImage = NSImage(data: thumbnailData) {
                     Image(nsImage: nsImage)
                          .resizable()
                          .aspectRatio(contentMode: .fill)
                  } else {
                     RoundedRectangle(cornerRadius: 6)
                          .fill(Color.white.opacity(0.10))
                  }
              }
              .frame(width: 64, height: 36)
              .clipShape(RoundedRectangle(cornerRadius: 6))

              // Name + path.
             VStack(alignment: .leading, spacing: 2) {
                 Text(video.name)
                      .font(.system(size: 12, weight: .medium))
                      .lineLimit(1)
                 Text(video.url.lastPathComponent)
                      .font(.system(size: 10))
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
              }
              .frame(maxWidth: .infinity, alignment: .leading)

              // Active badge (accent color) -- only for the current wallpaper.
             if isActive {
                 Circle()
                      .fill(LiquidGlassMetrics.accentColor)
                      .frame(width: 8, height: 8)
              }
         }
         .padding(.vertical, 6)
         .padding(.horizontal, 8)
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
            .frame(height: LiquidGlassMetrics.pillHeight)
            .glassSurface()
        }


        @ViewBuilder
            private var sidebarView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Playback Controls Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("playback_section", comment: "Playback section header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    
                    HStack(spacing: 8) {
                        // Play/Stop Button
                        Button(action: {
                            if localIsPlaying {
                                localIsPlaying = false
                                wallpaperManager.stopWallpaperSafe()
                            } else {
                                localIsPlaying = true
                                wallpaperManager.startWallpaperSafe()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: localIsPlaying ? "stop.fill" : "play.fill")
                                Text(localIsPlaying ? NSLocalizedString("stop_button", comment: "Stop button") : NSLocalizedString("play_button", comment: "Play button"))
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .accessibilityIdentifier("sidebar_play_toggle_button")
                        
                        // Next Wallpaper Button
                        Button(action: {
                            Task {
                                await wallpaperManager.nextWallpaper()
                            }
                        }) {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityIdentifier("sidebar_next_button")
                    }
                }
                
                Divider()
                
                // Auto-Change Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("auto_change_section_header", comment: "Auto-change section header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    
                    VStack(spacing: 12) {
                        Toggle(NSLocalizedString("enable_auto_change", comment: "Enable auto-change toggle"), isOn: Binding(
                            get: { wallpaperManager.isAutoChangeEnabled },
                            set: { newValue in wallpaperManager.isAutoChangeEnabled = newValue }
                        ))
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("sidebar_autochange_toggle")
                        
                        if wallpaperManager.isAutoChangeEnabled {
                            HStack {
                                Text(NSLocalizedString("every_label", comment: "Every label for interval"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Picker("", selection: Binding(
                                    get: { Int(wallpaperManager.autoChangeInterval / 60) },
                                    set: { newValue in wallpaperManager.autoChangeInterval = TimeInterval(newValue * 60) }
                                )) {
                                    ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { minutes in
                                        Text("\(minutes) min").tag(minutes)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                                .accessibilityIdentifier("sidebar_interval_picker")
                            }
                        }
                    }
                }
                
                // Mode Selection Section (only visible when auto-change is enabled)
                if wallpaperManager.isAutoChangeEnabled {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("mode_section", comment: "Mode section header"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        
                        Picker("", selection: $localIsShuffleMode) {
                            Text(NSLocalizedString("playlist_mode", comment: "Playlist mode")).tag(false)
                            Text(NSLocalizedString("shuffle_mode", comment: "Shuffle mode")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("sidebar_mode_picker")
                        .onChange(of: localIsShuffleMode) { newValue in
                            wallpaperManager.isShuffleMode = newValue
                        }
                        .onChange(of: wallpaperManager.isShuffleMode) { newValue in
                            if localIsShuffleMode != newValue {
                                localIsShuffleMode = newValue
                            }
                        }
                    }
                }
                
                Divider()
                
                // Audio Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("audio_section", comment: "Audio section header"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    
                    Button(action: {
                        let currentMute = UserDefaults.standard.bool(forKey: "MuteVideo")
                        UserDefaults.standard.set(!currentMute, forKey: "MuteVideo")
                    }) {
                        HStack {
                            Image(systemName: UserDefaults.standard.bool(forKey: "MuteVideo") ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            Text(UserDefaults.standard.bool(forKey: "MuteVideo") ? NSLocalizedString("unmute_button", comment: "Unmute button") : NSLocalizedString("mute_button", comment: "Mute button"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sidebar_mute_button")
                }
                
                Spacer()
                
                Divider()
                
                // Settings & Import Buttons
                VStack(spacing: 8) {
                    Button(action: {
                        isImporting = true
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text(NSLocalizedString("import_button", comment: "Import button"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sidebar_import_button")
                    
                    Button(action: {
                        showSettings = true
                    }) {
                        HStack {
                            Image(systemName: "gear")
                            Text(NSLocalizedString("settings_button", comment: "Settings button"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sidebar_settings_button")
                }
            }
            .padding()
        }
        .background(.ultraThinMaterial)
    }
    
    /// Contenido principal con grid de videos
    @ViewBuilder
    private var mainContentView: some View {
        if wallpaperManager.videoFiles.isEmpty {
            // Estado vacío
            emptyStateView
        } else {
            // Grid de videos
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(Array(wallpaperManager.videoFiles.enumerated()), id: \.element.id) { index, video in
                        VideoThumbnailCard(
                            video: video,
                            isSelected: selectedVideo?.id == video.id,
                            isActive: wallpaperManager.currentVideo?.id == video.id,
                            index: index,
                            isShuffleMode: localIsShuffleMode,
                            onTap: {
                                selectedVideo = video
                                print("🎯 Video seleccionado: \(video.name) (ID: \(video.id))")
                            },
                            wallpaperManager: wallpaperManager
                        )
                        // PHASE 4: Drop delegate for drag & drop reordering
                        .onDrop(of: [.text], delegate: VideoDropDelegate(
                            wallpaperManager: wallpaperManager,
                            currentIndex: index,
                            isShuffleMode: localIsShuffleMode
                        ))
                    }
                }
                .padding()
            }
            .onReceive(wallpaperManager.$videoFiles) { videoFiles in
                print("🔄 ContentView recibió actualización: \(videoFiles.count) videos")
            }
        }
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

    /// Tarjeta de miniatura para mostrar un video en el grid
struct VideoThumbnailCard: View {
    let video: VideoFile
    let isSelected: Bool
    let isActive: Bool
    let index: Int  // Add index for drag & drop
    let isShuffleMode: Bool  // Add shuffle mode flag
    let onTap: () -> Void
    let wallpaperManager: WallpaperManager
    
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false
    
    var body: some View {
        // Using GlassCard instead of HoverableGlassCard to avoid gesture conflicts with drag & drop
        GlassCard(padding: 8, cornerRadius: 12) {
        VStack(spacing: 8) {
            // Contenedor de miniatura
            ZStack {
                // Miniatura o icono por defecto
                if let thumbnailData = video.thumbnailData, let nsImage = NSImage(data: thumbnailData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 160, height: 90)
                        .overlay {
                            Image(systemName: "video.slash")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                }
                
                // Video preview overlay on hover (with delay to allow drag to start)
                if isHovering && !isDragging, video.bookmarkData != nil {
                    VideoPreviewPlayer(video: video, bookmarkActor: wallpaperManager.bookmarkActor)
                        .frame(width: 160, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                        .allowsHitTesting(false) // Don't interfere with drag gestures
                }
                
                // Indicadores superpuestos
                VStack {
                    HStack {
                        Spacer()
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, .green)
                                .font(.title3)
                                .shadow(radius: 2)
                        }
                        if video.bookmarkData != nil {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                                .shadow(radius: 2)
                        }
                    }
                    Spacer()
                    
                    // Bottom row: play indicator (left) and checkbox (right)
                    HStack {
                        // Indicador de reproducción si es el video activo
                        if isActive {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.white, .blue)
                                .font(.title2)
                                .shadow(radius: 2)
                        }
                        
                        Spacer()
                        
                        // Checkbox para aleatoriedad en bottom-right
                        Toggle(isOn: Binding(
                            get: { video.isEnabledForRandomPlay },
                            set: { _ in wallpaperManager.toggleVideoRandomPlayEnabled(video) }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .frame(width: 24, height: 24)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityIdentifier("videoToggle_\(video.id)")
                        .allowsHitTesting(true)
                    }
                }
                .padding(6)
            }
            // Fix for binding synchronization bug: Force view recreation when video state changes
            // by using .id() modifier. This ensures SwiftUI refreshes the view when the underlying
            // video object in the array is mutated by toggleVideoRandomPlayEnabled().
            .id(video.id)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            // Información del video
            VStack(spacing: 2) {
                Text(video.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 160)
                
                Text(video.url.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 160)
            }
            }
         }
        .onDrag {
            // Drag & drop enabled in both modes (Playlist and Shuffle)
            // User can organize library regardless of playback mode
            
            // Hide preview during drag
            self.isDragging = true
            self.isHovering = false
            
            print("📦 Drag started from card: index=\(index), video=\(video.name)")
            
            // Use NSString for better NSItemProvider compatibility
            let indexString = "\(index)" as NSString
            let provider = NSItemProvider(object: indexString)
            
            // Reset dragging state after drag ends
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isDragging = false
            }
            
            return provider
        }
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button(NSLocalizedString("set_as_wallpaper", comment: "Set as wallpaper"), systemImage: "pin.fill") {
                wallpaperManager.setAsCurrentWallpaper(video: video)
            }
            
            Divider()
            
            Button(video.isEnabledForRandomPlay ? NSLocalizedString("disable_for_random", comment: "Disable for random rotation") : NSLocalizedString("enable_for_random", comment: "Enable for random rotation"), 
                   systemImage: video.isEnabledForRandomPlay ? "minus.circle" : "plus.circle") {
                wallpaperManager.toggleVideoRandomPlayEnabled(video)
            }
            
            Divider()
            
            Button(NSLocalizedString("delete_button", comment: "Delete"), systemImage: "trash", role: .destructive) {
                wallpaperManager.removeVideo(video)
            }
        }
        .onAppear {
            print("🔍 VideoThumbnailCard apareció: \(video.name) (ID: \(video.id))")
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Show preview immediately on hover (no delay needed)
                // .onDrag only activates when user actually drags, not on hover
                if !isDragging {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = true
                    }
                }
            case .ended:
                // Hide preview when hover ends
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = false
                }
            }
        }
    }
}

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
