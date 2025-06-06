import SwiftUI

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var isImporting = false
    @State private var selectedVideo: VideoFile?
    
@State private var showMainWindow: Bool = true

var body: some View {
    NavigationSplitView {
        // Sidebar con lista de videos
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Videos")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    isImporting = true
                }) {
                    Image(systemName: "plus")
                }
                .help("Agregar videos")
            }
            .padding(.horizontal)
            
            List(wallpaperManager.videoFiles, selection: $selectedVideo) { video in
                VideoRowView(video: video)
                    .tag(video)
                    .onTapGesture {
                        // Al seleccionar un video, se establece automáticamente como activo
                        wallpaperManager.setActiveVideo(video)
                    }
                    .contextMenu {
                        Button("Eliminar", role: .destructive) {
                            wallpaperManager.removeVideo(video)
                        }
                    }
            }
            .listStyle(SidebarListStyle())
            
            // Controles de reproducción
            VStack(spacing: 12) {
                Divider()
                
                HStack {
                    Button(action: {
                        wallpaperManager.toggleWallpaper()
                    }) {
                        HStack {
                            Image(systemName: wallpaperManager.isPlayingWallpaper ? "stop.fill" : "play.fill")
                            Text(wallpaperManager.isPlayingWallpaper ? "Detener" : "Iniciar")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(wallpaperManager.currentVideo == nil)
                    
                    Spacer()
                }
                
                if let currentVideo = wallpaperManager.currentVideo {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Activo: \(currentVideo.name)")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    } detail: {
        // Área principal con vista previa
        Group {
            if let selectedVideo = selectedVideo {
                VideoDetailView(video: selectedVideo)
            } else {
                ContentUnavailableView(
                    "Selecciona un video",
                    systemImage: "video.fill",
                    description: Text("Elige un video de la lista para ver una vista previa")
                )
            }
        }
    }
    .fileImporter(
        isPresented: $isImporting,
        allowedContentTypes: [.movie],
        allowsMultipleSelection: true
    ) { result in
        switch result {
        case .success(let urls):
            wallpaperManager.addVideoFiles(urls: urls)
        case .failure(let error):
            print("Error al importar videos: \(error.localizedDescription)")
        }
    }
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Button("Configuración") {
                // Aquí se puede abrir una ventana de configuración
            }
        }
    }
    // Escuchar la notificación para forzar la aparición de la ventana principal
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowMainWindow"))) { _ in
        // Si la ventana está oculta, traerla al frente
        if let window = NSApp.windows.first(where: { !$0.isVisible && !($0 is NSPanel) }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct VideoRowView: View {
    let video: VideoFile

    var body: some View {
        HStack {
            if let thumbnailData = video.thumbnailData, let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 40) // Tamaño ajustado para la fila
                    .cornerRadius(4)
                    .clipped()
            } else {
                Image(systemName: "video.slash") // Icono si no hay miniatura
                    .frame(width: 60, height: 40)
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading) {
                Text(video.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Text(video.url.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if video.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 2)
    }
}

struct VideoDetailView: View {
    let video: VideoFile

    @EnvironmentObject var wallpaperManager: WallpaperManager // Acceder al manager
    @State private var showVideoPreview = false
    @State private var urlAccesible: URL? = nil // URL resuelta para vista previa

    var body: some View {
        VStack {
            Text(video.name)
                .font(.title)
                .padding(.bottom)

            // Botón para activar/desactivar vista previa del video
            HStack {
                Button(showVideoPreview ? "Mostrar Miniatura" : "Vista Previa Video") {
                    showVideoPreview.toggle()
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom)

            // Resolución y liberación del bookmark para la vista previa
            .onChange(of: showVideoPreview) {
                if $0 {
                    // Solo resolver si no está ya resuelta
                    if urlAccesible == nil {
                        urlAccesible = wallpaperManager.resolveBookmark(for: video)
                    }
                } else {
                    // Liberar el recurso cuando se oculta la vista previa
                    urlAccesible?.stopAccessingSecurityScopedResource()
                    urlAccesible = nil
                }
            }
            .onDisappear {
                // Liberar siempre al salir de la vista
                urlAccesible?.stopAccessingSecurityScopedResource()
                urlAccesible = nil
            }

            if showVideoPreview {
                if let urlAccesible = urlAccesible {
                    // Vista previa real usando VideoPlayerView instrumentado
                    VideoPlayerView(url: urlAccesible, shouldLoop: true, aspectFill: true)
                        .frame(maxWidth: 400, maxHeight: 300)
                        .cornerRadius(8)
                        .padding(.bottom)
                } else {
                    // Si no se pudo resolver el bookmark, mostrar error
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.red)
                    Text("No se pudo acceder al video para vista previa")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else if let thumbnailData = video.thumbnailData, let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 400, maxHeight: 300) // Tamaño más grande para el detalle
                    .cornerRadius(8)
                    .padding(.bottom)
            } else {
                // Vista previa más grande si no hay miniatura, o un mensaje
                Image(systemName: "video.slash.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 150)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
                Text("Miniatura no disponible")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Ubicación: \(video.url.path(percentEncoded: false))") // Mostrar la URL original
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)

            HStack {
                if video.isActive {
                    Label("Activo", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(WallpaperManager())
}
