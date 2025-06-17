import SwiftUI
import AppKit
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @State private var autoStartWallpaper = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
    @State private var muteVideo = UserDefaults.standard.bool(forKey: "MuteVideo")
    @State private var videoQuality = UserDefaults.standard.integer(forKey: "VideoQuality")
    
    @State private var isAutoChangeEnabled: Bool
    @State private var autoChangeIntervalMinutes: Int
    @State private var shouldAutoPlayOnSelection: Bool

    private let minIntervalMinutes = 1
    private let maxIntervalMinutes = 120

    init() {
        _isAutoChangeEnabled = State(initialValue: UserDefaults.standard.bool(forKey: "AutoChangeEnabled"))
        let savedInterval = UserDefaults.standard.double(forKey: "AutoChangeInterval")
        _autoChangeIntervalMinutes = State(initialValue: savedInterval > 0 ? Int(savedInterval / 60) : 10)
        _shouldAutoPlayOnSelection = State(initialValue: UserDefaults.standard.bool(forKey: "ShouldAutoPlayOnSelection"))
    }

    var body: some View {
        // Usar una Form para agrupar la configuración, común en macOS
        Form {
            // Sección de Reproducción General
            Section(header: Text("Reproducción General").font(.headline)) {
                Toggle("Iniciar fondo de pantalla automáticamente al abrir la app", isOn: $autoStartWallpaper)
                    .onChange(of: autoStartWallpaper) { _ in
                        UserDefaults.standard.set(autoStartWallpaper, forKey: "AutoStartWallpaper")
                    }
                
                Toggle("Silenciar videos", isOn: $muteVideo)
                    .onChange(of: muteVideo) { _ in
                        UserDefaults.standard.set(muteVideo, forKey: "MuteVideo")
                        // wallpaperManager.setMuted(muteVideo) // Notificar al manager
                    }
                
                Picker("Calidad de video (si aplica conversión):", selection: $videoQuality) {
                    Text("Baja").tag(0)
                    Text("Media").tag(1)
                    Text("Alta").tag(2)
                    Text("Original").tag(3)
                }
                .onChange(of: videoQuality) { _ in
                    UserDefaults.standard.set(videoQuality, forKey: "VideoQuality")
                }
                
                Toggle("Reproducir video al seleccionarlo en la lista", isOn: $shouldAutoPlayOnSelection)
                    .onChange(of: shouldAutoPlayOnSelection) { _ in
                        wallpaperManager.shouldAutoPlayOnSelection = shouldAutoPlayOnSelection
                        wallpaperManager.saveAutoChangeSettings()
                    }
            }
            
            Divider()
            
            // Sección de Configuración del Sistema
            Section(header: Text("Sistema").font(.headline)) {
                Toggle("Iniciar Live Walls con el sistema", isOn: Binding(
                    get: { launchManager.isLaunchAtLoginEnabled },
                    set: { newValue in
                        launchManager.setLaunchAtLogin(newValue)
                    }
                ))
                .help("Inicia automáticamente Live Walls cuando inicies sesión en macOS")
                
                if #unavailable(macOS 13.0) {
                    Text("⚠️ Para macOS < 13.0, configura manualmente en Preferencias del Sistema > Usuarios y Grupos > Objetos de inicio")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            // Sección de Cambio Automático de Wallpaper
            Section(header: Text("Cambio Automático de Wallpaper").font(.headline)) {
                Toggle("Activar cambio automático de wallpaper", isOn: $isAutoChangeEnabled)
                    .onChange(of: isAutoChangeEnabled) { _ in
                        wallpaperManager.isAutoChangeEnabled = isAutoChangeEnabled
                        wallpaperManager.saveAutoChangeSettings()
                    }
                
                if isAutoChangeEnabled {
                    Picker("Intervalo de cambio (minutos):", selection: $autoChangeIntervalMinutes) {
                        ForEach(minIntervalMinutes...maxIntervalMinutes, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .onChange(of: autoChangeIntervalMinutes) { _ in
                        wallpaperManager.autoChangeInterval = TimeInterval(autoChangeIntervalMinutes * 60)
                        wallpaperManager.saveAutoChangeSettings()
                    }
                }
            }
            
            Divider()

            Section(header: Text("Gestión de Videos").font(.headline)) {
                Text("Videos guardados: \(wallpaperManager.videoFiles.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Limpiar todos los videos") {
                    // Añadir alerta de confirmación
                    wallpaperManager.videoFiles.removeAll()
                    wallpaperManager.stopWallpaperSafe() // Usar la versión segura
                    wallpaperManager.saveVideos() // Guardar la lista vacía
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            HStack {
                Text("Live Walls v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cerrar Ventana") {
                    NSApp.keyWindow?.close() // Cierra la ventana de configuración
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 520) // Aumentar altura para la nueva sección
        // Cargar el estado del wallpaperManager cuando la vista aparece
        // Esto asegura que los @State locales se sincronicen con el manager
        .onAppear {
            self.isAutoChangeEnabled = wallpaperManager.isAutoChangeEnabled
            self.autoChangeIntervalMinutes = Int(wallpaperManager.autoChangeInterval / 60)
            self.shouldAutoPlayOnSelection = wallpaperManager.shouldAutoPlayOnSelection
            
            // Cargar también los valores que no están directamente en el manager pero sí en UserDefaults
            self.autoStartWallpaper = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
            self.muteVideo = UserDefaults.standard.bool(forKey: "MuteVideo")
            self.videoQuality = UserDefaults.standard.integer(forKey: "VideoQuality")
        }
    }
}

// Vista previa temporalmente deshabilitada para resolver errores de inicialización
// struct SettingsView_Previews: PreviewProvider {
//     static var previews: some View {
//         let manager = WallpaperManager()
//         SettingsView()
//             .environmentObject(manager)
//     }
// }
