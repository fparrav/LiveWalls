import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics

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
    
    // Estados para el progreso de optimización HEVC
    @State private var isOptimizing = false
    @State private var currentVideoIndex = 0
    @State private var totalVideos = 0
    @State private var currentVideoName = ""
    @State private var optimizationProgress: Double = 0.0

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
            mainContentView
            bottomButtonsView
        }
        .frame(width: 480, height: 500)
        .onAppear {
            cargarConfiguracionesActuales()
        }
    }
    
    // MARK: - View Components
    
    private var mainContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleView
                generalPlaybackSection
                systemSection
                autoChangeSection
                videoManagementSection
                Spacer(minLength: 20)
            }
            .padding(20)
        }
    }
    
    private var titleView: some View {
        Text(NSLocalizedString("settings_title", comment: "Settings title"))
            .font(.title2)
            .fontWeight(.semibold)
            .padding(.top, 10)
    }
    
    private var generalPlaybackSection: some View {
        GroupBox(NSLocalizedString("general_playback_section", comment: "General playback section")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(NSLocalizedString("auto_start_wallpaper", comment: "Auto start wallpaper"), isOn: $autoStartWallpaper)
                    .toggleStyle(SwitchToggleStyle())
                
                Toggle(NSLocalizedString("mute_videos", comment: "Mute videos"), isOn: $muteVideo)
                    .toggleStyle(SwitchToggleStyle())
            }
            .padding(12)
        }
    }
    
    private var systemSection: some View {
        GroupBox(NSLocalizedString("system_section", comment: "System section")) {
            VStack(alignment: .leading, spacing: 12) {
                launchAtLoginToggle
                
                if #unavailable(macOS 13.0) {
                    Text(NSLocalizedString("macos_compatibility_warning", comment: "macOS compatibility warning"))
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
    }
    
    private var launchAtLoginToggle: some View {
        Toggle(NSLocalizedString("launch_at_login", comment: "Launch at login"), isOn: launchAtLoginBinding)
            .toggleStyle(SwitchToggleStyle())
            .help(NSLocalizedString("launch_at_login_help", comment: "Launch at login help"))
    }
    
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchManager.isLaunchAtLoginEnabled },
            set: { newValue in
                launchManager.setLaunchAtLogin(newValue)
            }
        )
    }
    
    private var autoChangeSection: some View {
        GroupBox(NSLocalizedString("auto_change_section", comment: "Auto change section")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(NSLocalizedString("enable_auto_change", comment: "Enable auto change"), isOn: $isAutoChangeEnabled)
                    .toggleStyle(SwitchToggleStyle())
                
                if isAutoChangeEnabled {
                    intervalPickerView
                }
            }
            .padding(12)
        }
    }
    
    private var intervalPickerView: some View {
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
    
    private var videoManagementSection: some View {
        GroupBox(NSLocalizedString("video_management_section", comment: "Video management section")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(format: NSLocalizedString("videos_saved", comment: "Videos saved"), wallpaperManager.videoFiles.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(NSLocalizedString("optimize_videos_hevc", comment: "Optimize videos to HEVC")) {
                    optimizarVideosAHEVC()
                }
                .buttonStyle(.bordered)
                .disabled(wallpaperManager.videoFiles.isEmpty || isOptimizing)
                
                Button(NSLocalizedString("clear_all_videos", comment: "Clear all videos")) {
                    limpiarTodosLosVideos()
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .sheet(isPresented: $isOptimizing) {
            optimizationProgressSheet
        }
    }
    
    private var bottomButtonsView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                appVersionText
                Spacer()
                actionButtonsView
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private var appVersionText: some View {
        Group {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Live Walls v\(version)")
            } else {
                Text(NSLocalizedString("app_version", comment: "App version"))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    private var actionButtonsView: some View {
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
    
    /// Optimiza todos los videos no-HEVC a formato HEVC
    private func optimizarVideosAHEVC() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("optimize_videos_title", comment: "Optimize videos title")
        alert.informativeText = NSLocalizedString("optimize_videos_message", comment: "Optimize videos message")
        alert.addButton(withTitle: NSLocalizedString("optimize_button", comment: "Optimize button"))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: "Cancel button"))
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await solicitarPermisosYConvertir()
            }
        }
    }
    
    /// Solicita permisos para los directorios donde están los videos y luego convierte
    private func solicitarPermisosYConvertir() async {
        let videosNoHEVC = await detectarVideosNoHEVC()
        
        guard !videosNoHEVC.isEmpty else {
            await mostrarAlerta(
                titulo: NSLocalizedString("no_videos_to_optimize_title", comment: "No videos to optimize title"),
                mensaje: NSLocalizedString("no_videos_to_optimize_message", comment: "No videos to optimize message")
            )
            return
        }
        
        // Obtener directorios únicos donde están los videos
        var directoriosUnicos = Set<URL>()
        for videoFile in videosNoHEVC {
            if let url = wallpaperManager.resolveBookmark(for: videoFile) {
                let directorio = url.deletingLastPathComponent()
                directoriosUnicos.insert(directorio)
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Solicitar permisos para cada directorio único
        var directoriosPermitidos = Set<URL>()
        
        await MainActor.run {
            for directorio in directoriosUnicos {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.allowsMultipleSelection = false
                openPanel.directoryURL = directorio
                openPanel.message = "Selecciona el directorio '\(directorio.lastPathComponent)' para otorgar permisos de escritura para la optimización HEVC:"
                
                if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                    directoriosPermitidos.insert(selectedURL)
                }
            }
        }
        
        // Solo proceder si se otorgaron permisos para todos los directorios
        if directoriosPermitidos.count == directoriosUnicos.count {
            await convertirVideosAHEVC(directoriosPermitidos: directoriosPermitidos)
        } else {
            await mostrarAlerta(
                titulo: NSLocalizedString("permissions_required_title", comment: "Permissions required title"),
                mensaje: NSLocalizedString("permissions_required_message", comment: "Permissions required message")
            )
        }
    }
    
    /// Convierte videos no-HEVC a HEVC de forma asíncrona
    private func convertirVideosAHEVC(directoriosPermitidos: Set<URL> = []) async {
        let videosNoHEVC = await detectarVideosNoHEVC()
        
        guard !videosNoHEVC.isEmpty else {
            await mostrarAlerta(
                titulo: NSLocalizedString("no_videos_to_optimize_title", comment: "No videos to optimize title"),
                mensaje: NSLocalizedString("no_videos_to_optimize_message", comment: "No videos to optimize message")
            )
            return
        }
        
        // Inicializar estado de progreso
        await MainActor.run {
            isOptimizing = true
            totalVideos = videosNoHEVC.count
            currentVideoIndex = 0
            optimizationProgress = 0.0
        }
        
        print("🎬 Iniciando conversión de \(videosNoHEVC.count) videos a HEVC...")
        
        for (index, videoFile) in videosNoHEVC.enumerated() {
            // Actualizar progreso antes de procesar cada video
            await MainActor.run {
                currentVideoIndex = index + 1
                currentVideoName = videoFile.name
                optimizationProgress = Double(index) / Double(videosNoHEVC.count)
            }
            
            do {
                let optimizedURL = try await convertirVideoAHEVC(videoFile)
                await actualizarVideoEnLista(originalVideoFile: videoFile, optimizado: optimizedURL, directoriosPermitidos: directoriosPermitidos)
                print("✅ Video \(index + 1)/\(videosNoHEVC.count) optimizado: \(videoFile.name)")
            } catch {
                print("❌ Error optimizando \(videoFile.name): \(error)")
            }
        }
        
        // Finalizar progreso
        await MainActor.run {
            optimizationProgress = 1.0
            currentVideoName = NSLocalizedString("hevc_conversion_completed", comment: "HEVC conversion completed")
        }
        
        // Pequeña pausa para mostrar progreso completo
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 segundos
        
        await MainActor.run {
            isOptimizing = false
        }
        
        await mostrarAlerta(
            titulo: NSLocalizedString("optimization_completed_title", comment: "Optimization completed title"),
            mensaje: String(format: NSLocalizedString("optimization_completed_message", comment: "Optimization completed message"), videosNoHEVC.count)
        )
    }
    
    /// Detecta videos que no están en formato HEVC
    private func detectarVideosNoHEVC() async -> [VideoFile] {
        var videosNoHEVC: [VideoFile] = []
        
        for videoFile in wallpaperManager.videoFiles {
            // Resolver bookmark para acceso security-scoped
            guard let url = wallpaperManager.resolveBookmark(for: videoFile) else {
                print("⚠️ No se pudo resolver bookmark para: \(videoFile.name)")
                continue
            }
            
            defer {
                // Liberar acceso security-scoped
                url.stopAccessingSecurityScopedResource()
            }
            
            let asset = AVAsset(url: url)
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                if let formatDescriptions = try? await videoTrack.load(.formatDescriptions) {
                    let codecType = CMFormatDescriptionGetMediaSubType(formatDescriptions.first!)
                    if codecType != kCMVideoCodecType_HEVC {
                        videosNoHEVC.append(videoFile)
                    }
                }
            }
        }
        
        return videosNoHEVC
    }
    
    /// Convierte un video específico a HEVC
    private func convertirVideoAHEVC(_ videoFile: VideoFile) async throws -> URL {
        // Validar disponibilidad del preset HEVC
        guard AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality) else {
            throw NSError(domain: "OptimizationError", code: 4, userInfo: [NSLocalizedDescriptionKey: "HEVC no está disponible en este sistema"])
        }
        
        print("🔍 HEVC preset disponible, iniciando conversión para: \(videoFile.name)")
        
        // Resolver bookmark para acceso security-scoped
        guard let inputURL = wallpaperManager.resolveBookmark(for: videoFile) else {
            throw NSError(domain: "OptimizationError", code: 3, userInfo: [NSLocalizedDescriptionKey: "No se pudo acceder al archivo: \(videoFile.name)"])
        }
        
        defer {
            // Liberar acceso security-scoped
            inputURL.stopAccessingSecurityScopedResource()
        }
        
        let asset = AVAsset(url: inputURL)
        
        // Verificar que el video tiene pistas de video
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw NSError(domain: "OptimizationError", code: 5, userInfo: [NSLocalizedDescriptionKey: "El archivo no contiene pistas de video"])
        }
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw NSError(domain: "OptimizationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear la sesión de exportación"])
        }
        
        // Crear archivo temporal en directorio apropiado
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        
        print("📂 Archivo temporal: \(tempURL.lastPathComponent)")
        
        exportSession.outputURL = tempURL
        exportSession.outputFileType = .mp4
        
        // Configurar metadata antes de la exportación (compatible con macOS 13.0+)
        do {
            let metadata = try await asset.load(.metadata)
            exportSession.metadata = metadata
            print("📝 Metadata configurado correctamente")
        } catch {
            print("⚠️ No se pudo cargar metadata del asset: \(error)")
        }
        
        print("▶️ Iniciando exportación HEVC...")
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            // Limpiar archivo temporal en caso de error
            try? FileManager.default.removeItem(at: tempURL)
            
            let errorMessage = exportSession.error?.localizedDescription ?? "Error desconocido en la exportación"
            print("❌ Error en exportación: \(errorMessage)")
            throw NSError(domain: "OptimizationError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error en la exportación: \(errorMessage)"])
        }
        
        // Validar que el archivo resultante es realmente HEVC
        try await validarCodecHEVC(url: tempURL)
        
        print("✅ Conversión HEVC exitosa para: \(videoFile.name)")
        return tempURL
    }
    
    /// Valida que un archivo de video use codec HEVC
    private func validarCodecHEVC(url: URL) async throws {
        let asset = AVAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        
        guard let videoTrack = videoTracks.first else {
            throw NSError(domain: "OptimizationError", code: 6, userInfo: [NSLocalizedDescriptionKey: "No se encontraron pistas de video en el archivo convertido"])
        }
        
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            throw NSError(domain: "OptimizationError", code: 7, userInfo: [NSLocalizedDescriptionKey: "No se pudo obtener información del formato"])
        }
        
        let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
        
        guard codecType == kCMVideoCodecType_HEVC else {
            let codecString = String(describing: codecType)
            print("⚠️ Codec resultante: \(codecString) (esperado: HEVC)")
            throw NSError(domain: "OptimizationError", code: 8, userInfo: [NSLocalizedDescriptionKey: "La conversión no produjo codec HEVC. Codec resultante: \(codecString)"])
        }
        
        print("✅ Validación exitosa: Archivo convertido usa codec HEVC")
    }
    
    /// Actualiza la lista de videos reemplazando el original por el optimizado
    private func actualizarVideoEnLista(originalVideoFile: VideoFile, optimizado: URL, directoriosPermitidos: Set<URL> = []) async {
        await MainActor.run {
            if let index = wallpaperManager.videoFiles.firstIndex(where: { $0.id == originalVideoFile.id }) {
                do {
                    // Resolver bookmark del archivo original
                    guard let originalURL = wallpaperManager.resolveBookmark(for: originalVideoFile) else {
                        print("⚠️ No se pudo resolver bookmark del archivo original: \(originalVideoFile.name)")
                        // Limpiar archivo temporal
                        try? FileManager.default.removeItem(at: optimizado)
                        return
                    }
                    
                    defer {
                        originalURL.stopAccessingSecurityScopedResource()
                    }
                    
                    print("🔄 Reemplazando archivo original: \(originalURL.lastPathComponent)")
                    
                    let originalDirectory = originalURL.deletingLastPathComponent()
                    
                    // Si se proporcionaron directorios permitidos, usarlos para acceso sandbox
                    if !directoriosPermitidos.isEmpty {
                        // Buscar el directorio permitido que corresponde
                        guard let directorioPermitido = directoriosPermitidos.first(where: { $0.path == originalDirectory.path }) else {
                            throw NSError(domain: "OptimizationError", code: 9, userInfo: [NSLocalizedDescriptionKey: "No se encontraron permisos para el directorio: \(originalDirectory.path)"])
                        }
                        
                        // Acceder al directorio con permisos sandbox
                        guard directorioPermitido.startAccessingSecurityScopedResource() else {
                            throw NSError(domain: "OptimizationError", code: 10, userInfo: [NSLocalizedDescriptionKey: "No se pudo acceder al directorio con permisos sandbox"])
                        }
                        
                        defer {
                            directorioPermitido.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    // Crear directorio destino si no existe
                    try FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
                    
                    // Generar nombre del archivo optimizado (mantener nombre original pero con indicador)
                    let originalName = originalURL.deletingPathExtension().lastPathComponent
                    let finalURL = originalDirectory.appendingPathComponent("\(originalName)_hevc").appendingPathExtension("mp4")
                    
                    // Mover archivo temporal a ubicación final
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: optimizado, to: finalURL)
                    
                    print("✅ Archivo convertido movido exitosamente: \(finalURL.lastPathComponent)")
                    
                    // Crear bookmark para el archivo convertido
                    var bookmarkData: Data?
                    
                    // Intentar crear bookmark para el archivo específico
                    do {
                        // Primero verificar que el archivo existe y es accesible
                        guard FileManager.default.fileExists(atPath: finalURL.path) else {
                            throw NSError(domain: "BookmarkError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Archivo convertido no existe"])
                        }
                        
                        // Intentar crear bookmark con las mismas opciones que los archivos originales
                        bookmarkData = try finalURL.bookmarkData(
                            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        
                        // Validar que el bookmark se puede resolver inmediatamente
                        var isStale = false
                        let resolvedURL = try URL(resolvingBookmarkData: bookmarkData!, 
                                                 options: [.withSecurityScope], 
                                                 relativeTo: nil, 
                                                 bookmarkDataIsStale: &isStale)
                        
                        if isStale {
                            print("⚠️ Bookmark creado pero está obsoleto, regenerando...")
                            bookmarkData = try finalURL.bookmarkData(
                                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil
                            )
                        }
                        
                        print("🔖 Bookmark validado para archivo convertido: \(finalURL.lastPathComponent)")
                        
                    } catch {
                        print("❌ Error creando bookmark para archivo convertido: \(error)")
                        print("💡 Manteniendo archivo sin bookmark actualizado")
                        bookmarkData = nil
                    }
                    
                    // Actualizar VideoFile con nueva información
                    var updatedVideoFile = wallpaperManager.videoFiles[index]
                    updatedVideoFile.url = finalURL
                    updatedVideoFile.name = finalURL.deletingPathExtension().lastPathComponent
                    
                    // Solo actualizar bookmarkData si se creó exitosamente
                    if let newBookmarkData = bookmarkData {
                        updatedVideoFile.bookmarkData = newBookmarkData
                        print("📱 VideoFile actualizado con nuevo bookmark")
                        
                        // Verificar que el bookmark funciona antes de eliminar el original
                        do {
                            if let testURL = wallpaperManager.resolveBookmark(for: updatedVideoFile) {
                                testURL.stopAccessingSecurityScopedResource()
                                
                                // Si llegamos aquí, el bookmark funciona, eliminar archivo original
                                try FileManager.default.removeItem(at: originalURL)
                                print("🗑️ Archivo original eliminado después de verificar bookmark")
                            } else {
                                throw NSError(domain: "BookmarkError", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo resolver el bookmark recién creado"])
                            }
                        } catch {
                            print("❌ Error verificando bookmark: \(error)")
                            print("🔄 Manteniendo archivo original como respaldo")
                        }
                    } else {
                        print("⚠️ VideoFile actualizado sin cambio de bookmark, manteniendo archivo original")
                    }
                    
                    // Reemplazar por el optimizado
                    wallpaperManager.videoFiles[index] = updatedVideoFile
                    wallpaperManager.saveVideos()
                    
                } catch {
                    print("❌ Error reemplazando archivo: \(error.localizedDescription)")
                    // Limpiar archivo temporal en caso de error
                    try? FileManager.default.removeItem(at: optimizado)
                }
            } else {
                print("⚠️ VideoFile no encontrado en la lista")
                // Limpiar archivo temporal
                try? FileManager.default.removeItem(at: optimizado)
            }
        }
    }
    
    /// Muestra una alerta de forma asíncrona
    private func mostrarAlerta(titulo: String, mensaje: String) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = titulo
            alert.informativeText = mensaje
            alert.addButton(withTitle: "OK")
            alert.runModal()
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
    
    // MARK: - Progress Sheet
    private var optimizationProgressSheet: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("optimizing_videos_progress", comment: "Optimizing videos progress"))
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                HStack {
                    Text(NSLocalizedString("progress_label", comment: "Progress label"))
                    Spacer()
                    Text("\(currentVideoIndex)/\(totalVideos)")
                        .fontWeight(.medium)
                }
                
                ProgressView(value: optimizationProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .scaleEffect(y: 2)
                
                if !currentVideoName.isEmpty {
                    HStack {
                        Text(NSLocalizedString("processing_video", comment: "Processing video"))
                        Spacer()
                        Text(currentVideoName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(30)
        .frame(width: 400, height: 200)
        .interactiveDismissDisabled(true)
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
