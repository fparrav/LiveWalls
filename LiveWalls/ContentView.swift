import SwiftUI

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var isImporting = false
    @State private var selectedVideo: VideoFile?
    
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
                        .contextMenu {
                            Button("Establecer como fondo") {
                                wallpaperManager.setActiveVideo(video)
                            }
                            .disabled(video.isActive)
                            
                            Divider()
                            
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
                
                Text("⚠️ Vista previa para testing de crashes")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(.bottom)

            if showVideoPreview {
                // Vista previa real usando VideoPlayerView instrumentado
                VideoPlayerView(url: video.url, shouldLoop: true, aspectFill: true)
                    .frame(maxWidth: 400, maxHeight: 300)
                    .cornerRadius(8)
                    .overlay(
                        Text("🐛 INSTRUMENTADO")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4),
                        alignment: .topTrailing
                    )
                    .padding(.bottom)
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
                Button("Establecer como fondo de pantalla") {
                    wallpaperManager.setActiveVideo(video)
                }
                .buttonStyle(.borderedProminent)
                .disabled(video.isActive)

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
