import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @State private var autoStartWallpaper = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
    @State private var muteVideo = UserDefaults.standard.bool(forKey: "MuteVideo")
    @State private var videoQuality = UserDefaults.standard.integer(forKey: "VideoQuality")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configuración")
                .font(.title)
                .fontWeight(.bold)
            
            GroupBox("Reproducción") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Iniciar fondo de pantalla automáticamente", isOn: $autoStartWallpaper)
                        .onChange(of: autoStartWallpaper) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "AutoStartWallpaper")
                        }
                    
                    Toggle("Silenciar videos", isOn: $muteVideo)
                        .onChange(of: muteVideo) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "MuteVideo")
                        }
                    
                    HStack {
                        Text("Calidad de video:")
                        Picker("Calidad", selection: $videoQuality) {
                            Text("Baja").tag(0)
                            Text("Media").tag(1)
                            Text("Alta").tag(2)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: videoQuality) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "VideoQuality")
                        }
                    }
                }
                .padding()
            }
            
            GroupBox("Pantalla") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pantallas detectadas: \(NSScreen.screens.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("El fondo de pantalla se aplicará a todas las pantallas y espacios de trabajo conectados.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            GroupBox("Videos") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Videos guardados: \(wallpaperManager.videoFiles.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Limpiar todos los videos") {
                            wallpaperManager.videoFiles.removeAll()
                            wallpaperManager.stopWallpaper()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                }
                .padding()
            }
            
            Spacer()
            
            HStack {
                Text("Live Walls v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Cerrar") {
                    NSApp.setActivationPolicy(.accessory)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

#Preview {
    SettingsView()
        .environmentObject(WallpaperManager())
}
