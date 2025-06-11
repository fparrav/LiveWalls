import SwiftUI
// import AVKit // Necesario para VideoPlayer y AVPlayer en la vista de detalle // Eliminado ya que VideoPlayerView usa AVFoundation
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
                Button("Configuración App") {
                    // Aquí se puede abrir una ventana de configuración global de la app
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

            // Lista de videos
            List(selection: $selectedVideo) {
                ForEach(wallpaperManager.videoFiles) { video in
                    VideoRowView(video: video)
                        .tag(video)
                        .onTapGesture {
                            wallpaperManager.setActiveVideo(video)
                        }
                        .contextMenu {
                            Button("Fijar como Fondo", systemImage: "pin.fill") {
                                wallpaperManager.setAsCurrentWallpaper(video: video)
                            }
                            Button("Eliminar", systemImage: "trash", role: .destructive) {
                                wallpaperManager.removeVideo(video)
                            }
                        }
                }
                
                // Sección para otros enlaces como "Configuración"
                Section(header: Text("Opciones")) {
                    NavigationLink("Configuración General") {
                        SettingsView()
                    }
                }
            }
            .listStyle(.sidebar) // Estilo apropiado para la barra lateral

            // Controles de reproducción en la parte inferior de la barra lateral
            VStack(spacing: 12) {
                Divider()
                HStack {
                    Button(action: {
                        if wallpaperManager.isPlayingWallpaper {
                            wallpaperManager.stopWallpaperSafe()
                        } else {
                            wallpaperManager.startWallpaperSafe()
                        }
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
                
                // Área para información adicional (sin botones de debug)
                // Dejamos comentado por si se necesita agregar información en el futuro
                /*
                VStack(spacing: 8) {
                    Divider()
                    
                    Text("Información")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                */
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
            VStack {
                if #available(macOS 14.0, *) {
                    ContentUnavailableView(
                        "Selecciona un video",
                        systemImage: "video.fill",
                        description: Text("Elige un video de la lista para ver una vista previa y detalles.")
                    )
                } else {
                    VStack {
                        Image(systemName: "video.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 10)
                        Text("Selecciona un video")
                            .font(.title2)
                            .padding(.bottom, 5)
                        Text("Elige un video de la lista para ver una vista previa y detalles.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                NavigationLink("Ir a Configuración") {
                    SettingsView()
                }
                .padding(.top)
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
    @Binding var selectedVideo: VideoFile? // Binding para actualizar la selección

    @EnvironmentObject var wallpaperManager: WallpaperManager // Acceder al manager
    @State private var showVideoPreview = false
    @State private var urlAccesible: URL? = nil // URL resuelta para vista previa

    var body: some View {
        VStack(alignment: .leading) {
            Text(video.name)
                .font(.largeTitle)
                .padding(.bottom, 5)

            Text("Ubicación: \(video.url.path(percentEncoded: false))")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.bottom, 20)

            HStack {
                Button {
                    showVideoPreview.toggle()
                } label: {
                    Label(showVideoPreview ? "Ocultar Vista Previa" : "Mostrar Vista Previa", systemImage: showVideoPreview ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    wallpaperManager.setAsCurrentWallpaper(video: video)
                } label: {
                    Label("Fijar como Fondo", systemImage: "pin.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Establece este video como el fondo de pantalla actual y detiene el cambio automático.")

            }
            .padding(.bottom)

            // Resolución y liberación del bookmark para la vista previa
            .onChange(of: showVideoPreview) { newValue in
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
                if let resolvedURL = urlAccesible {
                    // Vista previa usando AVPlayerLayer a través de VideoPlayerView
                    VideoPlayerView(url: resolvedURL, shouldLoop: true, aspectFill: true)
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

            HStack {
                if video.isActive {
                    Label("Activo (Reproduciendo o Seleccionado)", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                Spacer()
            }
            .padding(.top, 5)
            
            Spacer() // Empuja todo hacia arriba
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // Asegura que el contenido se alinee arriba
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
