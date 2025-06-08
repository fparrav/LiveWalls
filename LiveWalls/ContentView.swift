import SwiftUI
import AVKit // Necesario para VideoPlayer y AVPlayer en la vista de detalle
import Foundation

struct ContentView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var isImporting = false
    @State private var selectedVideo: VideoFile?

    @State private var showMainWindow: Bool = true

    var body: some View {
        NavigationSplitView {
            sidebarView // Vista de la barra lateral
        } detail: {
            detailView // Vista de detalle
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
                Button("Configuración App") { // Renombrado para diferenciar del enlace en sidebar
                    // Aquí se puede abrir una ventana de configuración global de la app
                    // Por ejemplo, usando SettingsLink en macOS 14+ o una hoja/ventana modal
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowMainWindow"))) { _ in
            // Si la ventana está oculta, traerla al frente
            if let window = NSApp.windows.first(where: { !$0.isVisible && !($0 is NSPanel) }) ?? NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // Vista computada para la barra lateral
    @ViewBuilder
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Encabezado con título y botón de agregar
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
            .padding([.horizontal, .top])
            .padding(.bottom, 8) // Espacio antes de la lista

            // Lista de videos y enlace de configuración
            List(selection: $selectedVideo) {
                ForEach(wallpaperManager.videoFiles) { video in
                    VideoRowView(video: video)
                        .tag(video) // Necesario para que la selección funcione con List
                        .onTapGesture {
                            // Al seleccionar un video, se establece automáticamente como activo
                            // y se actualiza selectedVideo para la NavigationSplitView
                            wallpaperManager.setActiveVideo(video)
                            // selectedVideo se actualiza automáticamente por el binding de List
                        }
                        .contextMenu {
                            Button("Eliminar", role: .destructive) {
                                wallpaperManager.removeVideo(video)
                            }
                        }
                }
                
                // Sección para otros enlaces como "Configuración"
                Section(header: Text("Opciones")) {
                    NavigationLink("Configuración Video") { // Enlace a una vista de configuración específica
                        Text("Ventana de Configuración de Video (Placeholder)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .navigationTitle("Configuración Video")
                    }
                }
            }
            .listStyle(.sidebar) // Estilo apropiado para la barra lateral

            // Controles de reproducción en la parte inferior de la barra lateral
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
                .padding(.horizontal)

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
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // Vista computada para el área de detalle
    @ViewBuilder
    private var detailView: some View {
        if let video = selectedVideo {
            VideoDetailView(video: video, selectedVideo: $selectedVideo)
        } else {
            ContentUnavailableView(
                "Selecciona un video",
                systemImage: "video.fill",
                description: Text("Elige un video de la lista para ver una vista previa y detalles.")
            )
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
    @Binding var selectedVideo: VideoFile? // Binding para actualizar la selección

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
            .onChange(of: showVideoPreview) { _, newValue in
                if newValue {
                    if urlAccesible == nil {
                        urlAccesible = wallpaperManager.resolveBookmark(for: video)
                    }
                } else {
                    urlAccesible?.stopAccessingSecurityScopedResource()
                    urlAccesible = nil
                }
            }
            .onDisappear {
                urlAccesible?.stopAccessingSecurityScopedResource()
                urlAccesible = nil
            }

            if showVideoPreview {
                if let urlAccesible = urlAccesible {
                    // Vista previa usando AVKit.VideoPlayer con interacción deshabilitada
                    // Se ocultan los controles mediante configuración y deshabilitación de interacción
                    VideoPlayer(player: AVPlayer(url: urlAccesible))
                        .frame(maxWidth: 400, maxHeight: 300)
                        .cornerRadius(8)
                        .padding(.bottom)
                        .allowsHitTesting(false) // Deshabilitamos completamente la interacción
                        .onAppear {
                            // Configuración adicional para ocultar controles si es posible
                        }
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
                    .frame(maxWidth: 400, maxHeight: 300)
                    .cornerRadius(8)
                    .padding(.bottom)
            } else {
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

            Text("Ubicación: \(video.url.path(percentEncoded: false))")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)

            HStack {
                if video.isActive {
                    Label("Activo", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            // Botones de navegación para testing
            HStack(spacing: 16) {
                Button("← Video Anterior") {
                    navigationToPreviousVideo()
                }
                .buttonStyle(.bordered)
                .disabled(wallpaperManager.videoFiles.count <= 1)
                
                Button("Video Siguiente →") {
                    navigationToNextVideo()
                }
                .buttonStyle(.bordered)
                .disabled(wallpaperManager.videoFiles.count <= 1)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    
    // Función para navegar al video anterior
    private func navigationToPreviousVideo() {
        guard let currentVideo = selectedVideo,
              let currentIndex = wallpaperManager.videoFiles.firstIndex(of: currentVideo),
              currentIndex > 0 else {
            // Si no hay video actual o estamos en el primero, ir al último
            guard let lastVideo = wallpaperManager.videoFiles.last else { return }
            selectedVideo = lastVideo
            wallpaperManager.setActiveVideo(lastVideo)
            return
        }
        let previousVideo = wallpaperManager.videoFiles[currentIndex - 1]
        selectedVideo = previousVideo
        wallpaperManager.setActiveVideo(previousVideo)
    }
    
    // Función para navegar al video siguiente
    private func navigationToNextVideo() {
        guard let currentVideo = selectedVideo,
              let currentIndex = wallpaperManager.videoFiles.firstIndex(of: currentVideo),
              currentIndex < wallpaperManager.videoFiles.count - 1 else {
            // Si no hay video actual o estamos en el último, ir al primero
            guard let firstVideo = wallpaperManager.videoFiles.first else { return }
            selectedVideo = firstVideo
            wallpaperManager.setActiveVideo(firstVideo)
            return
        }
        let nextVideo = wallpaperManager.videoFiles[currentIndex + 1]
        selectedVideo = nextVideo
        wallpaperManager.setActiveVideo(nextVideo)
    }
}

// Preview temporalmente deshabilitado para resolver errores de compilación
//#Preview {
//    ContentView()
//        .environmentObject(WallpaperManager())
//}
