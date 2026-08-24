import SwiftUI
import AppKit
import os.log

/// Vista del menú del status bar simplificada y robusta
struct StatusBarMenuView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage("MuteVideo") private var isMuteEnabled: Bool = false
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "StatusBarMenu")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Task 8.2: now-playing header -- small thumbnail + current
            // filename, reusing `wallpaperManager.currentVideo`.
            // Task 8.3: real transport buttons (previous/play-pause/next),
            // replacing the old text-only playback rows, wrapped together
            // with the header in `.glassDarkSurface()`.
            VStack(alignment: .leading, spacing: 10) {
                if let currentVideo = wallpaperManager.currentVideo {
                    HStack(spacing: 8) {
                        nowPlayingThumbnail(for: currentVideo)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("current_wallpaper", comment: "Current wallpaper"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            // Scrolls marquee-style (like a music player's
                            // now-playing title) instead of truncating when
                            // the filename doesn't fit the menu's width.
                            MarqueeText(text: currentVideo.name)
                                .id(currentVideo.name)
                        }
                    }
                } else {
                    Text(NSLocalizedString("current_wallpaper", comment: "Current wallpaper"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Apple's Control Center-style transport row: circular
                // hover-highlighted buttons with a real hit target and
                // spacing, rather than bare borderless SF Symbols.
                HStack(spacing: 4) {
                    Spacer(minLength: 0)

                    TransportButton(
                        systemImage: "backward.fill",
                        isDisabled: !wallpaperManager.canGoToPreviousWallpaper,
                        accessibilityIdentifier: "statusbar_transport_previous_button"
                    ) {
                        Task { await wallpaperManager.previousWallpaper() }
                    }

                    TransportButton(
                        systemImage: wallpaperManager.isPlayingWallpaper ? "pause.fill" : "play.fill",
                        isDisabled: wallpaperManager.currentVideo == nil,
                        accessibilityIdentifier: "statusbar_transport_play_toggle_button"
                    ) {
                        wallpaperManager.toggleWallpaper()
                    }
                    .keyboardShortcut(wallpaperManager.isPlayingWallpaper ? "s" : "p", modifiers: .command)

                    TransportButton(
                        systemImage: "forward.fill",
                        isDisabled: !wallpaperManager.canGoToNextWallpaper,
                        accessibilityIdentifier: "statusbar_transport_next_button"
                    ) {
                        Task { await wallpaperManager.nextWallpaper() }
                    }
                    .keyboardShortcut("n", modifiers: .command)

                    TransportButton(
                        systemImage: isMuteEnabled ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        accessibilityIdentifier: "statusbar_transport_mute_button"
                    ) {
                        isMuteEnabled.toggle()
                        wallpaperManager.applyMuteSettingToActiveWindows()
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            // Matches the 12px `controlCornerRadius` and lighter shadow used
            // by inner controls elsewhere in the menu, rather than the
            // heavier 20px `cardCornerRadius` meant for full panels/rails --
            // at this card's small size the panel metric read as an
            // unrelated floating card instead of the menu's own top row.
            .glassDarkSurface(
                cornerRadius: LiquidGlassMetrics.controlCornerRadius,
                shadowRadius: 6,
                shadowY: 2
            )

            Divider()

            // Controles principales
            MenuRow(title: NSLocalizedString("open_app", comment: "Open app"), key: "o") {
                openMainApplication()
            }

            Divider()

            // Configuraciones rápidas -- checkmark-style row (matches how a
            // native NSMenu shows a boolean menu item's state) rather than a
            // boxed `Toggle` switch/checkbox.
            MenuRow(
                title: NSLocalizedString("auto_launch", comment: "Auto launch"),
                isChecked: launchManager.isLaunchAtLoginEnabled
            ) {
                launchManager.setLaunchAtLogin(!launchManager.isLaunchAtLoginEnabled)
            }

            Divider()

            // Actualizaciones
            MenuRow(title: NSLocalizedString("check_for_updates", comment: "Check for updates"), key: "u") {
                InAppUpdater.shared.checkForUpdates()
            }

            MenuRow(title: NSLocalizedString("about", comment: "About")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }

            Divider()

            // Salir
            MenuRow(title: NSLocalizedString("quit_app", comment: "Quit app"), key: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    /// Small now-playing thumbnail for the status bar menu header (task 8.2).
    /// Reuses the video's already-generated `thumbnailData`; falls back to a
    /// placeholder glyph when no thumbnail is available.
    @ViewBuilder
    private func nowPlayingThumbnail(for video: VideoFile) -> some View {
        Group {
            if let data = video.thumbnailData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 32, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    /// Abre la aplicación principal de manera simple y confiable usando solo SwiftUI
    private func openMainApplication() {
        logger.info("🚀 Abriendo aplicación principal desde status bar")
        
        DispatchQueue.main.async {
            // Verificar si ya existe una ventana principal visible
            if let existingWindow = self.findMainWindow(), existingWindow.isVisible {
                self.logger.info("✅ Ventana existente encontrada - activándola")
                self.activateExistingWindow(existingWindow)
                return
            }
            
            // Activar app y crear ventana con SwiftUI - simple y directo
            self.logger.info("🆕 Creando nueva ventana con SwiftUI")
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            self.openWindow(id: "main")
        }
    }
    
    /// Encuentra la ventana principal de la aplicación de manera simple
    private func findMainWindow() -> NSWindow? {
        // Buscar ventanas principales excluyendo las del status bar
        let candidateWindows = NSApp.windows.filter { window in
            let className = window.className
            return !className.contains("StatusBar") &&
                   !className.contains("MenuWindow") &&
                   !className.contains("NSPanel") &&
                   window.canBecomeMain
        }
        
        // Priorizar ventana visible y no minimizada
        return candidateWindows.first(where: { $0.isVisible && !$0.isMiniaturized }) ??
               candidateWindows.first(where: { $0.isMiniaturized }) ??
               candidateWindows.first
    }
    
    /// Activa una ventana existente de manera simple
    private func activateExistingWindow(_ window: NSWindow) {
        logger.info("🎯 Activando ventana existente")
        
        // Restaurar si está minimizada
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        
        // Activar ventana y aplicación
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        logger.info("✅ Ventana activada correctamente")
    }
}

/// A native-menu-style row for the `.window`-style status bar menu.
///
/// `.window`-style `MenuBarExtra` content is a plain floating view, not a
/// real `NSMenu`, so a stock SwiftUI `Button`/`Toggle` in it falls back to
/// the default macOS control chrome -- a boxed, bordered pill per row, as
/// seen in the mockup gap this fixes -- instead of the borderless,
/// full-width, hover-highlighted rows every native macOS menu (Control
/// Center, the Wi-Fi/Bluetooth menu extras, etc.) uses. This reproduces that
/// look by hand: `.buttonStyle(.plain)` strips the boxed chrome, an
/// `.onHover`-driven accent background mimics `NSMenuItem` highlighting, and
/// a leading checkmark (rather than a boxed `Toggle` switch/checkbox)
/// represents a boolean item's state, matching how a real `NSMenu` shows a
/// checked item.
private struct MenuRow: View {
    let title: String
    var isChecked: Bool? = nil
    var key: KeyEquivalent? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12)
                        .opacity(isChecked ? 1 : 0)
                }
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(isHovered ? Color.white : Color.primary)
        .onHover { isHovered = $0 }
        .modifier(OptionalKeyboardShortcut(key: key))
    }
}

/// Applies `.keyboardShortcut(key, modifiers: .command)` only when `key` is
/// non-nil, so `MenuRow` can stay a single view type whether or not a row
/// has a shortcut.
private struct OptionalKeyboardShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

/// A circular, hover-highlighted transport control matching the sizing and
/// hit-target macOS uses for its own media controls (Control Center's
/// now-playing widget, the menu-bar Now Playing item) -- a 28pt circular
/// target around a 13pt icon, rather than a bare borderless SF Symbol with
/// no padding or hover feedback.
private struct TransportButton: View {
    let systemImage: String
    var isDisabled: Bool = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill((isHovered && !isDisabled) ? Color.white.opacity(0.14) : Color.clear)
        )
        .foregroundStyle(isDisabled ? Color.secondary.opacity(0.4) : Color.primary)
        .onHover { isHovered = $0 }
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}
