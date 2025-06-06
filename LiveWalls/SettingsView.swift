import SwiftUI
import AppKit
import AVFoundation

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
                        .onChange(of: autoStartWallpaper) {
                            UserDefaults.standard.set($0, forKey: "AutoStartWallpaper")
                        }
                    
                    Toggle("Silenciar videos", isOn: $muteVideo)
                        .onChange(of: muteVideo) {
                            UserDefaults.standard.set($0, forKey: "MuteVideo")
                        }
                    
                    HStack {
                        Text("Calidad de video:")
                        Picker("Calidad", selection: $videoQuality) {
                            Text("Baja").tag(0)
                            Text("Media").tag(1)
                            Text("Alta").tag(2)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: videoQuality) {
                            UserDefaults.standard.set($0, forKey: "VideoQuality")
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
                
                // Botón para cerrar solo la ventana principal (no la app)
                Button("Cerrar") {
                    // Oculta la ventana principal, la app sigue viva y visible en el Dock y status bar
                    NSApp.keyWindow?.orderOut(nil)
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
