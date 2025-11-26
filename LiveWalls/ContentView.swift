import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @State private var isImporting = false
    @State private var selectedVideo: VideoFile?
    @State private var showSettings = false
    @State private var localIsShuffleMode: Bool = false
    @State private var localIsPlaying: Bool = false

    // Grid columns para la vista de miniaturas
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        NavigationSplitView {
            // Sidebar with glass effect
            sidebarView
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        } detail: {
            // Main content area
            VStack(spacing: 0) {
                // Video grid content
                mainContentView
                
                Divider()
                
                // Bottom controls
                bottomControlsView
            }
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
    
    /// Sidebar with glass effect containing all controls
    @ViewBuilder
    private var sidebarView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Playback Controls Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("PLAYBACK")
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
                    Text("AUTO-CHANGE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    
                    VStack(spacing: 12) {
                        Toggle("Enable Auto-Change", isOn: Binding(
                            get: { wallpaperManager.isAutoChangeEnabled },
                            set: { newValue in wallpaperManager.isAutoChangeEnabled = newValue }
                        ))
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("sidebar_autochange_toggle")
                        
                        if wallpaperManager.isAutoChangeEnabled {
                            HStack {
                                Text("Every")
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
                        Text("MODE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        
                        Picker("Playback Mode", selection: $localIsShuffleMode) {
                            Text("Playlist").tag(false)
                            Text("Shuffle").tag(true)
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
                    Text("AUDIO")
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
                            Text(UserDefaults.standard.bool(forKey: "MuteVideo") ? "Unmute" : "Mute")
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
                            onTap: {
                                selectedVideo = video
                                print("🎯 Video seleccionado: \(video.name) (ID: \(video.id))")
                            },
                            wallpaperManager: wallpaperManager
                        )
                        // PHASE 4: Drag & Drop reordering (only in playlist mode)
                        .onDrag {
                            // Only enable drag in playlist mode
                            print("🎯 Drag attempt: localIsShuffleMode=\(localIsShuffleMode), autoChangeEnabled=\(wallpaperManager.isAutoChangeEnabled)")
                            guard !localIsShuffleMode else {
                                print("🚫 Drag blocked: shuffle mode active")
                                return NSItemProvider()
                            }
                            
                            print("📦 Drag started: index=\(index), video=\(video.name)")
                            let data = "\(index)".data(using: .utf8)!
                            return NSItemProvider(item: data as NSData, typeIdentifier: "public.text")
                        }
                        .onDrop(of: [.text], delegate: VideoDropDelegate(
                            wallpaperManager: wallpaperManager,
                            currentIndex: index,
                            isShuffleMode: localIsShuffleMode  // Use local state instead of manager state
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
    let onTap: () -> Void
    let wallpaperManager: WallpaperManager
    
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
                
                // Indicadores superpuestos
                VStack {
                    HStack {
                        // Large checkbox Toggle para aleatoriedad en top-left
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
                    
                    // Indicador de reproducción si es el video activo
                    if isActive {
                        HStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.white, .blue)
                                .font(.title2)
                                .shadow(radius: 2)
                        }
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
/// Only active in playlist mode (not shuffle mode)
struct VideoDropDelegate: DropDelegate {
    let wallpaperManager: WallpaperManager
    let currentIndex: Int
    let isShuffleMode: Bool
    
    func dropEntered(info: DropInfo) {
        // Visual feedback not needed in this simple implementation
    }
    
    func performDrop(info: DropInfo) -> Bool {
        print("🎯 Drop triggered: currentIndex=\(currentIndex), isShuffleMode=\(isShuffleMode)")
        
        // Only allow drops in playlist mode
        guard !isShuffleMode else {
            print("🚫 Drop rejected: shuffle mode active")
            return false
        }
        
        guard let item = info.itemProviders(for: [.text]).first else {
            print("⚠️ Drop failed: no text item provider found")
            return false
        }
        
        // Load the dragged video's index asynchronously.
        // Return true immediately to indicate drop is accepted and being processed.
        // The actual reordering happens asynchronously in the closure below.
        item.loadItem(forTypeIdentifier: "public.text", options: nil) { (data, error) in
            guard let data = data as? Data,
                  let sourceIndexString = String(data: data, encoding: .utf8),
                  let sourceIndex = Int(sourceIndexString) else {
                print("❌ Drop failed: could not decode index from data")
                return
            }
            
            print("✅ Drop data received: sourceIndex=\(sourceIndex) → currentIndex=\(self.currentIndex)")
            
            // Perform reordering on main thread
            DispatchQueue.main.async {
                wallpaperManager.reorderVideos(from: sourceIndex, to: self.currentIndex)
                print("✅ Reordering completed: moved video from \(sourceIndex) to \(self.currentIndex)")
            }
        }
        
        // Return true to indicate drop is accepted and being processed asynchronously.
        // This fixes the race condition where the method was returning before the
        // closure could execute, causing the drop to always appear to fail.
        return true
    }
}

// Preview temporalmente deshabilitado para resolver errores de compilación
//#Preview {
//    ContentView()
//        .environmentObject(WallpaperManager())
//}
