import SwiftUI
import AppKit
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @Environment(\.dismiss) private var dismiss
    
    // Estados locales para las configuraciones
    @State private var autoStartWallpaper: Bool
    @State private var muteVideo: Bool
    @State private var isAutoChangeEnabled: Bool
    @State private var autoChangeIntervalMinutes: Int
    
    // Estados originales para poder cancelar cambios
    @State private var originalAutoStartWallpaper: Bool
    @State private var originalMuteVideo: Bool
    @State private var originalIsAutoChangeEnabled: Bool
    @State private var originalAutoChangeIntervalMinutes: Int
    @State private var originalLaunchAtLogin: Bool

    private let minIntervalMinutes = 1
    private let maxIntervalMinutes = 120

    init() {
        // Cargar valores actuales de UserDefaults
        let autoStart = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        let mute = UserDefaults.standard.bool(forKey: "MuteVideo")
        let autoChangeEnabled = UserDefaults.standard.bool(forKey: "AutoChangeEnabled")
        let savedInterval = UserDefaults.standard.double(forKey: "AutoChangeInterval")
        
        // Estados actuales
        _autoStartWallpaper = State(initialValue: autoStart)
        _muteVideo = State(initialValue: mute)
        _isAutoChangeEnabled = State(initialValue: autoChangeEnabled)
        _autoChangeIntervalMinutes = State(initialValue: savedInterval > 0 ? Int(savedInterval / 60) : 10)
        
        // Estados originales para poder cancelar
        _originalAutoStartWallpaper = State(initialValue: autoStart)
        _originalMuteVideo = State(initialValue: mute)
        _originalIsAutoChangeEnabled = State(initialValue: autoChangeEnabled)
        _originalAutoChangeIntervalMinutes = State(initialValue: savedInterval > 0 ? Int(savedInterval / 60) : 10)
        _originalLaunchAtLogin = State(initialValue: false) // Se actualizará en onAppear
    }

    var body: some View {
        VStack(spacing: 0) {
            // Contenido principal con scroll
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Título
                    Text(NSLocalizedString("settings_title", comment: "Settings title"))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 10)
                    
                    // Sección de Reproducción General
                    GroupBox(NSLocalizedString("general_playback_section", comment: "General playback section")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(NSLocalizedString("auto_start_wallpaper", comment: "Auto start wallpaper"), isOn: $autoStartWallpaper)
                                .toggleStyle(SwitchToggleStyle())
                            
                            Toggle(NSLocalizedString("mute_videos", comment: "Mute videos"), isOn: $muteVideo)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        .padding(12)
                    }
                    
                    // Sección de Sistema
                    GroupBox(NSLocalizedString("system_section", comment: "System section")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(NSLocalizedString("launch_at_login", comment: "Launch at login"), isOn: Binding(
                                get: { launchManager.isLaunchAtLoginEnabled },
                                set: { newValue in
                                    // Solo actualizar visualmente, guardar en aceptar
                                    launchManager.setLaunchAtLogin(newValue)
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())
                            .help(NSLocalizedString("launch_at_login_help", comment: "Launch at login help"))
                            
                            if #unavailable(macOS 13.0) {
                                Text(NSLocalizedString("macos_compatibility_warning", comment: "macOS compatibility warning"))
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                    }

                    // Sección de Cambio Automático
                    GroupBox(NSLocalizedString("auto_change_section", comment: "Auto change section")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(NSLocalizedString("enable_auto_change", comment: "Enable auto change"), isOn: $isAutoChangeEnabled)
                                .toggleStyle(SwitchToggleStyle())
                            
                            if isAutoChangeEnabled {
                                HStack {
                                    Text(NSLocalizedString("interval_label", comment: "Interval label"))
                                    Spacer()
                                    Picker("", selection: $autoChangeIntervalMinutes) {
                                        ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { minutes in
                                            Text(String(format: NSLocalizedString("minutes_format", comment: "Minutes format"), minutes)).tag(minutes)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(width: 100)
                                }
                            }
                        }
                        .padding(12)
                    }
                    
                    // Sección de Gestión de Videos
                    GroupBox(NSLocalizedString("video_management_section", comment: "Video management section")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(format: NSLocalizedString("videos_saved", comment: "Videos saved"), wallpaperManager.videoFiles.count))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button(NSLocalizedString("clear_all_videos", comment: "Clear all videos")) {
                                limpiarTodosLosVideos()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            
            // Barra inferior con botones
            Divider()
            
            HStack {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Live Walls v\(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(NSLocalizedString("app_version", comment: "App version"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(NSLocalizedString("cancel_button", comment: "Cancel button")) {
                        cancelarCambios()
                        cerrarVentana()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    
                    Button(NSLocalizedString("accept_button", comment: "Accept button")) {
                        guardarTodasLasConfiguraciones()
                        cerrarVentana()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 480, height: 500)
        .onAppear {
            cargarConfiguracionesActuales()
        }
    }
    
    // MARK: - Funciones de gestión de configuraciones
    
    /// Carga las configuraciones actuales desde UserDefaults y managers
    private func cargarConfiguracionesActuales() {
        // Sincronizar con estados actuales
        self.isAutoChangeEnabled = wallpaperManager.isAutoChangeEnabled
        self.autoChangeIntervalMinutes = Int(wallpaperManager.autoChangeInterval / 60)
        
        // Cargar desde UserDefaults
        self.autoStartWallpaper = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        self.muteVideo = UserDefaults.standard.bool(forKey: "MuteVideo")
        
        // Guardar estados originales para poder cancelar
        self.originalAutoStartWallpaper = autoStartWallpaper
        self.originalMuteVideo = muteVideo
        self.originalIsAutoChangeEnabled = isAutoChangeEnabled
        self.originalAutoChangeIntervalMinutes = autoChangeIntervalMinutes
        self.originalLaunchAtLogin = launchManager.isLaunchAtLoginEnabled
    }
    
    /// Guarda todas las configuraciones en UserDefaults y sincroniza con los managers
    private func guardarTodasLasConfiguraciones() {
        // Guardar configuraciones en UserDefaults
        UserDefaults.standard.set(autoStartWallpaper, forKey: "AutoStartWallpaper")
        UserDefaults.standard.set(muteVideo, forKey: "MuteVideo")
        UserDefaults.standard.set(isAutoChangeEnabled, forKey: "AutoChangeEnabled")
        UserDefaults.standard.set(TimeInterval(autoChangeIntervalMinutes * 60), forKey: "AutoChangeInterval")
        
        // Sincronizar con WallpaperManager
        wallpaperManager.isAutoChangeEnabled = isAutoChangeEnabled
        wallpaperManager.autoChangeInterval = TimeInterval(autoChangeIntervalMinutes * 60)
        wallpaperManager.saveAutoChangeSettings()
        
        // Forzar sincronización inmediata
        UserDefaults.standard.synchronize()
        
        print("✅ Configuraciones guardadas exitosamente")
    }
    
    /// Cancela los cambios y restaura los valores originales
    private func cancelarCambios() {
        // Restaurar valores originales
        self.autoStartWallpaper = originalAutoStartWallpaper
        self.muteVideo = originalMuteVideo
        self.isAutoChangeEnabled = originalIsAutoChangeEnabled
        self.autoChangeIntervalMinutes = originalAutoChangeIntervalMinutes
        
        // Restaurar launch at login si cambió
        if launchManager.isLaunchAtLoginEnabled != originalLaunchAtLogin {
            launchManager.setLaunchAtLogin(originalLaunchAtLogin)
        }
        
        print("↩️ Cambios cancelados - configuraciones restauradas")
    }
    
    /// Limpia todos los videos con confirmación
    private func limpiarTodosLosVideos() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("delete_all_videos_title", comment: "Delete all videos title")
        alert.informativeText = NSLocalizedString("delete_all_videos_message", comment: "Delete all videos message")
        alert.addButton(withTitle: NSLocalizedString("delete_button", comment: "Delete button"))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: "Cancel button"))
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            wallpaperManager.videoFiles.removeAll()
            wallpaperManager.stopWallpaper()
            wallpaperManager.saveVideos()
            print("🗑️ Todos los videos han sido eliminados")
        }
    }
    
    /// Cierra la ventana de configuración
    private func cerrarVentana() {
        DispatchQueue.main.async {
            // Buscar la ventana de configuraciones
            if let window = NSApp.windows.first(where: { window in
                window.contentView?.subviews.contains { view in
                    String(describing: type(of: view)).contains("SettingsView")
                } ?? false
            }) {
                window.close()
                print("✅ Ventana de configuración cerrada")
            } else {
                // Fallback: usar dismiss de SwiftUI
                dismiss()
                print("✅ Vista de configuración cerrada con dismiss")
            }
        }
    }
}

// MARK: - Vista previa
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(WallpaperManager())
            .environmentObject(LaunchManager())
    }
}
