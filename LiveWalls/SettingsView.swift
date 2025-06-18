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
    @State private var shouldAutoPlayOnSelection: Bool
    
    // Estados originales para poder cancelar cambios
    @State private var originalAutoStartWallpaper: Bool
    @State private var originalMuteVideo: Bool
    @State private var originalIsAutoChangeEnabled: Bool
    @State private var originalAutoChangeIntervalMinutes: Int
    @State private var originalShouldAutoPlayOnSelection: Bool
    @State private var originalLaunchAtLogin: Bool

    private let minIntervalMinutes = 1
    private let maxIntervalMinutes = 120

    init() {
        // Cargar valores actuales de UserDefaults
        let autoStart = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        let mute = UserDefaults.standard.bool(forKey: "MuteVideo")
        let autoChangeEnabled = UserDefaults.standard.bool(forKey: "AutoChangeEnabled")
        let savedInterval = UserDefaults.standard.double(forKey: "AutoChangeInterval")
        let autoPlay = UserDefaults.standard.bool(forKey: "ShouldAutoPlayOnSelection")
        
        // Estados actuales
        _autoStartWallpaper = State(initialValue: autoStart)
        _muteVideo = State(initialValue: mute)
        _isAutoChangeEnabled = State(initialValue: autoChangeEnabled)
        _autoChangeIntervalMinutes = State(initialValue: savedInterval > 0 ? Int(savedInterval / 60) : 10)
        _shouldAutoPlayOnSelection = State(initialValue: autoPlay)
        
        // Estados originales para poder cancelar
        _originalAutoStartWallpaper = State(initialValue: autoStart)
        _originalMuteVideo = State(initialValue: mute)
        _originalIsAutoChangeEnabled = State(initialValue: autoChangeEnabled)
        _originalAutoChangeIntervalMinutes = State(initialValue: savedInterval > 0 ? Int(savedInterval / 60) : 10)
        _originalShouldAutoPlayOnSelection = State(initialValue: autoPlay)
        _originalLaunchAtLogin = State(initialValue: false) // Se actualizará en onAppear
    }

    var body: some View {
        VStack(spacing: 0) {
            // Contenido principal con scroll
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Título
                    Text("Configuración de Live Walls")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 10)
                    
                    // Sección de Reproducción General
                    GroupBox("Reproducción General") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Iniciar wallpaper automáticamente al abrir la app", isOn: $autoStartWallpaper)
                                .toggleStyle(SwitchToggleStyle())
                            
                            Toggle("Silenciar videos", isOn: $muteVideo)
                                .toggleStyle(SwitchToggleStyle())
                            
                            Toggle("Reproducir video al seleccionarlo", isOn: $shouldAutoPlayOnSelection)
                                .toggleStyle(SwitchToggleStyle())
                        }
                        .padding(12)
                    }
                    
                    // Sección de Sistema
                    GroupBox("Sistema") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Iniciar Live Walls con el sistema", isOn: Binding(
                                get: { launchManager.isLaunchAtLoginEnabled },
                                set: { newValue in
                                    // Solo actualizar visualmente, guardar en aceptar
                                    launchManager.setLaunchAtLogin(newValue)
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())
                            .help("Inicia automáticamente Live Walls cuando inicies sesión en macOS")
                            
                            if #unavailable(macOS 13.0) {
                                Text("⚠️ Para macOS < 13.0, configura manualmente en Preferencias del Sistema")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                    }

                    // Sección de Cambio Automático
                    GroupBox("Cambio Automático de Wallpaper") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Activar cambio automático de wallpaper", isOn: $isAutoChangeEnabled)
                                .toggleStyle(SwitchToggleStyle())
                            
                            if isAutoChangeEnabled {
                                HStack {
                                    Text("Intervalo:")
                                    Spacer()
                                    Picker("", selection: $autoChangeIntervalMinutes) {
                                        ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { minutes in
                                            Text("\(minutes) min").tag(minutes)
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
                    GroupBox("Gestión de Videos") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Videos guardados: \(wallpaperManager.videoFiles.count)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button("Limpiar todos los videos") {
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
                Text("Live Walls v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Cancelar") {
                        cancelarCambios()
                        cerrarVentana()
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    
                    Button("Aceptar") {
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
        self.shouldAutoPlayOnSelection = wallpaperManager.shouldAutoPlayOnSelection
        
        // Cargar desde UserDefaults
        self.autoStartWallpaper = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        self.muteVideo = UserDefaults.standard.bool(forKey: "MuteVideo")
        
        // Guardar estados originales para poder cancelar
        self.originalAutoStartWallpaper = autoStartWallpaper
        self.originalMuteVideo = muteVideo
        self.originalIsAutoChangeEnabled = isAutoChangeEnabled
        self.originalAutoChangeIntervalMinutes = autoChangeIntervalMinutes
        self.originalShouldAutoPlayOnSelection = shouldAutoPlayOnSelection
        self.originalLaunchAtLogin = launchManager.isLaunchAtLoginEnabled
    }
    
    /// Guarda todas las configuraciones en UserDefaults y sincroniza con los managers
    private func guardarTodasLasConfiguraciones() {
        // Guardar configuraciones en UserDefaults
        UserDefaults.standard.set(autoStartWallpaper, forKey: "AutoStartWallpaper")
        UserDefaults.standard.set(muteVideo, forKey: "MuteVideo")
        UserDefaults.standard.set(shouldAutoPlayOnSelection, forKey: "ShouldAutoPlayOnSelection")
        UserDefaults.standard.set(isAutoChangeEnabled, forKey: "AutoChangeEnabled")
        UserDefaults.standard.set(TimeInterval(autoChangeIntervalMinutes * 60), forKey: "AutoChangeInterval")
        
        // Sincronizar con WallpaperManager
        wallpaperManager.shouldAutoPlayOnSelection = shouldAutoPlayOnSelection
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
        self.shouldAutoPlayOnSelection = originalShouldAutoPlayOnSelection
        
        // Restaurar launch at login si cambió
        if launchManager.isLaunchAtLoginEnabled != originalLaunchAtLogin {
            launchManager.setLaunchAtLogin(originalLaunchAtLogin)
        }
        
        print("↩️ Cambios cancelados - configuraciones restauradas")
    }
    
    /// Limpia todos los videos con confirmación
    private func limpiarTodosLosVideos() {
        let alert = NSAlert()
        alert.messageText = "¿Eliminar todos los videos?"
        alert.informativeText = "Esta acción eliminará todos los videos guardados. ¿Deseas continuar?"
        alert.addButton(withTitle: "Eliminar")
        alert.addButton(withTitle: "Cancelar")
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
