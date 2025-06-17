import SwiftUI
import Foundation

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @State private var isImporting = false
    @State private var selectedVideo: VideoFile?
    @State private var showSettings = false

    // Grid columns para la vista de miniaturas
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Barra de herramientas superior
            toolbarView
            
            Divider()
            
            // Contenido principal
            mainContentView
            
            Divider()
            
            // Controles inferiores
            bottomControlsView
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                print("🎬 Importando \(urls.count) videos: \(urls.map { $0.lastPathComponent })")
                wallpaperManager.addVideoFiles(urls: urls)
            case .failure(let error):
                print("❌ Error al importar videos: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(launchManager)
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
    
    /// Barra de herramientas superior con botones principales
    @ViewBuilder
    private var toolbarView: some View {
        HStack {
            Text("LiveWalls")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            // Botones de acción
            HStack(spacing: 12) {
                Button(action: {
                    isImporting = true
                }) {
                    Label("Importar", systemImage: "plus")
                }
                .help("Agregar videos")
                .buttonStyle(.bordered)
                
                Button(action: {
                    showSettings = true
                }) {
                    Label("Configuración", systemImage: "gear")
                }
                .help("Configuración de la aplicación")
                .buttonStyle(.bordered)
            }
        }
        .padding()
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
                    ForEach(wallpaperManager.videoFiles) { video in
                        VideoThumbnailCard(
                            video: video,
                            isSelected: selectedVideo?.id == video.id,
                            isActive: video.isActive
                        ) {
                            selectedVideo = video
                        }
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
                Text("No hay videos agregados")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("Haz clic en 'Importar' para agregar videos y establecerlos como fondo de pantalla")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: {
                isImporting = true
            }) {
                Label("Importar Videos", systemImage: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
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
                        Text("Wallpaper activo: \(currentVideo.name)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                } else {
                    Text("Sin wallpaper activo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("\(wallpaperManager.videoFiles.count) videos total")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Botones de acción para video seleccionado
            HStack(spacing: 12) {
                // Botón de reproducción/parada
                Button(action: {
                    if wallpaperManager.isPlayingWallpaper {
                        wallpaperManager.stopWallpaperSafe()
                    } else {
                        wallpaperManager.startWallpaperSafe()
                    }
                }) {
                    HStack {
                        Image(systemName: wallpaperManager.isPlayingWallpaper ? "stop.fill" : "play.fill")
                        Text(wallpaperManager.isPlayingWallpaper ? "Detener" : "Reproducir")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(wallpaperManager.currentVideo == nil)
                
                // Botón establecer como wallpaper
                Button(action: {
                    if let video = selectedVideo {
                        wallpaperManager.setAsCurrentWallpaper(video: video)
                    }
                }) {
                    Label("Establecer como Wallpaper", systemImage: "pin.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedVideo == nil)
                
                // Botón eliminar
                Button(action: {
                    if let video = selectedVideo {
                        wallpaperManager.removeVideo(video)
                        selectedVideo = nil
                    }
                }) {
                    Label("Eliminar", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(selectedVideo == nil)
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
    
    var body: some View {
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
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("Establecer como Wallpaper", systemImage: "pin.fill") {
                // Usar EnvironmentObject aquí requeriría más configuración,
                // mejor manejar estas acciones desde el padre
                onTap()
            }
            Button("Eliminar", systemImage: "trash", role: .destructive) {
                // Similar al anterior
                onTap()
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

// Preview temporalmente deshabilitado para resolver errores de compilación
//#Preview {
//    ContentView()
//        .environmentObject(WallpaperManager())
//}
