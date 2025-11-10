import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics

struct SettingsView: View {
    @EnvironmentObject var wallpaperManager: WallpaperManager
    @EnvironmentObject var launchManager: LaunchManager
    @Environment(\.dismiss) private var dismiss
    // Current version for display
    private let currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    
    // Local states for configurations
    @State private var autoStartWallpaper: Bool
    @State private var muteVideo: Bool
    @State private var isAutoChangeEnabled: Bool
    @State private var autoChangeIntervalMinutes: Int
    @State private var duplicateHandlingPreference: WallpaperManager.DuplicateHandling
    
    // Original states to be able to cancel changes
    @State private var originalAutoStartWallpaper: Bool
    @State private var originalMuteVideo: Bool
    @State private var originalIsAutoChangeEnabled: Bool
    @State private var originalAutoChangeIntervalMinutes: Int
    @State private var originalLaunchAtLogin: Bool
    @State private var originalDuplicateHandlingPreference: WallpaperManager.DuplicateHandling
    
    // Original states for transitions
    @State private var originalIsTransitionEnabled: Bool
    @State private var originalTransitionDuration: Double
    @State private var originalTransitionType: TransitionManager.TransitionType
    
    // States for HEVC optimization progress
    @State private var isOptimizing = false
    @State private var currentVideoIndex = 0
    @State private var totalVideos = 0
    @State private var currentVideoName = ""
    @State private var optimizationProgress: Double = 0.0
    
    // Additional states for optimization with black frames
    @State private var videosProcessed = 0
    @State private var totalVideosToProcess = 0
    @State private var currentVideoBeingProcessed = ""
    @State private var optimizationErrors: [String] = []
    @StateObject private var videoOptimizer = VideoOptimizer()
    
    // States for transition settings
    @State private var isTransitionEnabled: Bool
    @State private var transitionDuration: Double
    @State private var transitionType: TransitionManager.TransitionType

    private let minIntervalMinutes = 1
    private let maxIntervalMinutes = 120

    init() {
        // Cargar valores actuales de UserDefaults
        let autoStart = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        let mute = UserDefaults.standard.bool(forKey: "MuteVideo")
        let autoChangeEnabled = UserDefaults.standard.bool(forKey: "AutoChangeEnabled")
        let savedInterval = UserDefaults.standard.double(forKey: "AutoChangeInterval")
        
        // Cargar preferencia de manejo de duplicados
        let duplicateHandlingRawValue = UserDefaults.standard.string(forKey: "DuplicateHandlingPreference") ?? "askAlways"
        let duplicateHandling: WallpaperManager.DuplicateHandling
        switch duplicateHandlingRawValue {
        case "skip":
            duplicateHandling = .skip
        case "replace":
            duplicateHandling = .replace
        case "keepBoth":
            duplicateHandling = .keepBoth
        default:
            duplicateHandling = .skip // Default to skip for "askAlways" or unknown values
        }
        
        // Cargar configuración de transiciones
        let isTransitionEnabled = UserDefaults.standard.bool(forKey: "IsTransitionEnabled")
        let transitionDuration = UserDefaults.standard.double(forKey: "TransitionDuration")
        let transitionTypeRawValue = UserDefaults.standard.string(forKey: "TransitionType") ?? "crossfade"
        let transitionType: TransitionManager.TransitionType
        switch transitionTypeRawValue {
        case "fadeOutFadeIn":
            transitionType = .fadeOutFadeIn
        default:
            transitionType = .crossfade
        }
        
        // Estados actuales
        _autoStartWallpaper = State(initialValue: autoStart)
        _muteVideo = State(initialValue: mute)
        _isAutoChangeEnabled = State(initialValue: autoChangeEnabled)
        _autoChangeIntervalMinutes = State(initialValue: savedInterval > 0 ? Int(savedInterval / 60) : 10)
        _duplicateHandlingPreference = State(initialValue: duplicateHandling)
        
        // Estados para transiciones
        _isTransitionEnabled = State(initialValue: isTransitionEnabled)
        _transitionDuration = State(initialValue: transitionDuration > 0 ? transitionDuration : 2.0)
        _transitionType = State(initialValue: transitionType)
        
        // Original states to be able to cancel
        _originalAutoStartWallpaper = State(initialValue: autoStart)
        _originalMuteVideo = State(initialValue: mute)
        _originalIsAutoChangeEnabled = State(initialValue: autoChangeEnabled)
        _originalAutoChangeIntervalMinutes = State(initialValue: savedInterval > 0 ? Int(savedInterval / 60) : 10)
        _originalLaunchAtLogin = State(initialValue: false) // Se actualizará en onAppear
        _originalDuplicateHandlingPreference = State(initialValue: duplicateHandling)
        
        // Original states for transitions
        _originalIsTransitionEnabled = State(initialValue: isTransitionEnabled)
        _originalTransitionDuration = State(initialValue: transitionDuration > 0 ? transitionDuration : 2.0)
        _originalTransitionType = State(initialValue: transitionType)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainContentView
            bottomButtonsView
        }
        .frame(width: 480, height: 600)
        .onAppear {
            loadCurrentSettings()
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
                transitionSection
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
                
                // Sección de actualizaciones
                updateSection
                
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
    
    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Versión actual: \(currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                Button(action: {
                    InAppUpdater.shared.checkForUpdates()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(NSLocalizedString("check_for_updates", comment: "Check for updates"))
                    }
                }
                .buttonStyle(.bordered)
            }
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
    
    private var transitionSection: some View {
        GroupBox(NSLocalizedString("transition_section", comment: "Transition section")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(NSLocalizedString("enable_transitions", comment: "Enable transitions"), isOn: $isTransitionEnabled)
                    .toggleStyle(SwitchToggleStyle())
                
                if isTransitionEnabled {
                    transitionDurationPickerView
                    transitionTypePickerView
                }
            }
            .padding(12)
        }
    }
    
    private var transitionDurationPickerView: some View {
        HStack {
            Text(NSLocalizedString("transition_duration_label", comment: "Transition duration label"))
            Spacer()
            Picker("", selection: $transitionDuration) {
                ForEach([0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0], id: \.self) { duration in
                    Text(String(format: NSLocalizedString("seconds_format", comment: "Seconds format"), duration)).tag(duration)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 100)
        }
    }
    
    private var transitionTypePickerView: some View {
        HStack {
            Text(NSLocalizedString("transition_type_label", comment: "Transition type label"))
            Spacer()
            Picker("", selection: $transitionType) {
                Text(NSLocalizedString("crossfade_transition", comment: "Crossfade transition")).tag(TransitionManager.TransitionType.crossfade)
                Text(NSLocalizedString("fade_out_fade_in_transition", comment: "Fade out fade in transition")).tag(TransitionManager.TransitionType.fadeOutFadeIn)
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 150)
        }
    }
    
    private var videoManagementSection: some View {
        GroupBox(NSLocalizedString("video_management_section", comment: "Video management section")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(format: NSLocalizedString("videos_saved", comment: "Videos saved"), wallpaperManager.videoFiles.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                duplicateHandlingSection
                
                Button(NSLocalizedString("optimize_videos_hevc", comment: "Optimize videos to HEVC")) {
                    optimizeVideosToHEVC()
                }
                .buttonStyle(.bordered)
                .disabled(wallpaperManager.videoFiles.isEmpty || isOptimizing)
                .accessibilityIdentifier("optimize_hevc_button")
                
                Button(NSLocalizedString("remove_black_frames", comment: "Remove black frames")) {
                    removeBlackFrames()
                }
                .buttonStyle(.bordered)
                .disabled(wallpaperManager.videoFiles.isEmpty || isOptimizing)
                .accessibilityIdentifier("remove_black_frames_button")
                
                Button(NSLocalizedString("clear_all_videos", comment: "Clear all videos")) {
                    clearAllVideos()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("clear_videos_button")
            }
            .padding(12)
        }
        .sheet(isPresented: $isOptimizing) {
            optimizationProgressSheet
        }
    }
    
    private var duplicateHandlingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("duplicate_handling_title", comment: "Duplicate handling title"))
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Text(NSLocalizedString("duplicate_handling_description", comment: "Duplicate handling description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $duplicateHandlingPreference) {
                    Text(NSLocalizedString("duplicate_preference_skip", comment: "Skip duplicates")).tag(WallpaperManager.DuplicateHandling.skip)
                    Text(NSLocalizedString("duplicate_preference_replace", comment: "Replace existing")).tag(WallpaperManager.DuplicateHandling.replace)
                    Text(NSLocalizedString("duplicate_preference_keep_both", comment: "Keep both")).tag(WallpaperManager.DuplicateHandling.keepBoth)
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
            }
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
                cancelChanges()
                closeWindow()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("settings_cancel_button")
            
            Button(NSLocalizedString("accept_button", comment: "Accept button")) {
                saveAllSettings()
                closeWindow()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("settings_accept_button")
        }
    }
    
    // MARK: - Settings management functions
    
    /// Loads current settings from UserDefaults and managers
    private func loadCurrentSettings() {
        // Synchronize with current states
        self.isAutoChangeEnabled = wallpaperManager.isAutoChangeEnabled
        self.autoChangeIntervalMinutes = Int(wallpaperManager.autoChangeInterval / 60)
        
        // Load from UserDefaults
        self.autoStartWallpaper = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        self.muteVideo = UserDefaults.standard.bool(forKey: "MuteVideo")
        
        // Load duplicate handling preference
        let duplicateHandlingRawValue = UserDefaults.standard.string(forKey: "DuplicateHandlingPreference") ?? "askAlways"
        switch duplicateHandlingRawValue {
        case "skip":
            self.duplicateHandlingPreference = .skip
        case "replace":
            self.duplicateHandlingPreference = .replace
        case "keepBoth":
            self.duplicateHandlingPreference = .keepBoth
        default:
            self.duplicateHandlingPreference = .skip // Default to skip for "askAlways" or unknown values
        }
        
        // Load transition settings
        self.isTransitionEnabled = UserDefaults.standard.bool(forKey: "IsTransitionEnabled")
        self.transitionDuration = UserDefaults.standard.double(forKey: "TransitionDuration")
        let transitionTypeRawValue = UserDefaults.standard.string(forKey: "TransitionType") ?? "crossfade"
        switch transitionTypeRawValue {
        case "fadeOutFadeIn":
            self.transitionType = .fadeOutFadeIn
        default:
            self.transitionType = .crossfade
        }
        
        // Save original states to be able to cancel
        self.originalAutoStartWallpaper = autoStartWallpaper
        self.originalMuteVideo = muteVideo
        self.originalIsAutoChangeEnabled = isAutoChangeEnabled
        self.originalAutoChangeIntervalMinutes = autoChangeIntervalMinutes
        self.originalLaunchAtLogin = launchManager.isLaunchAtLoginEnabled
        self.originalDuplicateHandlingPreference = duplicateHandlingPreference
        
        // Save original states for transitions
        self.originalIsTransitionEnabled = isTransitionEnabled
        self.originalTransitionDuration = transitionDuration
        self.originalTransitionType = transitionType
    }
    
    /// Saves all settings to UserDefaults and synchronizes with managers
    private func saveAllSettings() {
        // Save settings to UserDefaults
        UserDefaults.standard.set(autoStartWallpaper, forKey: "AutoStartWallpaper")
        UserDefaults.standard.set(muteVideo, forKey: "MuteVideo")
        UserDefaults.standard.set(isAutoChangeEnabled, forKey: "AutoChangeEnabled")
        UserDefaults.standard.set(TimeInterval(autoChangeIntervalMinutes * 60), forKey: "AutoChangeInterval")
        
        // Save duplicate handling preference
        let duplicateHandlingRawValue: String
        switch duplicateHandlingPreference {
        case .skip:
            duplicateHandlingRawValue = "skip"
        case .replace:
            duplicateHandlingRawValue = "replace"
        case .keepBoth:
            duplicateHandlingRawValue = "keepBoth"
        }
        UserDefaults.standard.set(duplicateHandlingRawValue, forKey: "DuplicateHandlingPreference")
        
        // Save transition settings
        UserDefaults.standard.set(isTransitionEnabled, forKey: "IsTransitionEnabled")
        UserDefaults.standard.set(transitionDuration, forKey: "TransitionDuration")
        let transitionTypeRawValue: String
        switch transitionType {
        case .fadeOutFadeIn:
            transitionTypeRawValue = "fadeOutFadeIn"
        default:
            transitionTypeRawValue = "crossfade"
        }
        UserDefaults.standard.set(transitionTypeRawValue, forKey: "TransitionType")
        
        // Synchronize with WallpaperManager
        wallpaperManager.isAutoChangeEnabled = isAutoChangeEnabled
        wallpaperManager.autoChangeInterval = TimeInterval(autoChangeIntervalMinutes * 60)
        wallpaperManager.saveAutoChangeSettings()
        
        // Save transition settings to WallpaperManager
        wallpaperManager.setTransitionEnabled(isTransitionEnabled)
        wallpaperManager.setTransitionDuration(transitionDuration)
        wallpaperManager.setTransitionType(transitionType)
        
        // Force immediate synchronization
        UserDefaults.standard.synchronize()
        
        print("✅ Settings saved successfully")
    }
    
    /// Cancels changes and restores original values
    private func cancelChanges() {
        // Restore original values
        self.autoStartWallpaper = originalAutoStartWallpaper
        self.muteVideo = originalMuteVideo
        self.isAutoChangeEnabled = originalIsAutoChangeEnabled
        self.autoChangeIntervalMinutes = originalAutoChangeIntervalMinutes
        self.duplicateHandlingPreference = originalDuplicateHandlingPreference
        
        // Restore transition settings
        self.isTransitionEnabled = originalIsTransitionEnabled
        self.transitionDuration = originalTransitionDuration
        self.transitionType = originalTransitionType
        
        // Restore launch at login if it changed
        if launchManager.isLaunchAtLoginEnabled != originalLaunchAtLogin {
            launchManager.setLaunchAtLogin(originalLaunchAtLogin)
        }
        
        print("↩️ Changes cancelled - settings restored")
    }
    
    /// Clears all videos with confirmation
    private func clearAllVideos() {
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
            print("🗑️ All videos have been deleted")
        }
    }
    
    /// Optimizes all non-HEVC videos to HEVC format
    private func optimizeVideosToHEVC() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("optimize_videos_title", comment: "Optimize videos title")
        alert.informativeText = NSLocalizedString("optimize_videos_message", comment: "Optimize videos message")
        alert.addButton(withTitle: NSLocalizedString("optimize_button", comment: "Optimize button"))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: "Cancel button"))
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await requestPermissionsAndConvert()
            }
        }
    }
    
    /// Removes black frames from videos without HEVC optimization
    private func removeBlackFrames() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("remove_black_frames_title", comment: "Remove black frames title")
        alert.informativeText = NSLocalizedString("remove_black_frames_message", comment: "Remove black frames message")
        alert.addButton(withTitle: NSLocalizedString("optimize_button", comment: "Optimize button"))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: "Cancel button"))
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await requestPermissionsAndRemoveBlackFrames()
            }
        }
    }
    
    /// Optimizes videos with black frame detection and removal
    private func optimizeVideosWithBlackFrameDetection() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("optimize_remove_black_frames_title", comment: "Optimize and remove black frames title")
        alert.informativeText = NSLocalizedString("optimize_remove_black_frames_message", comment: "Optimize and remove black frames message")
        alert.addButton(withTitle: NSLocalizedString("optimize_button", comment: "Optimize button"))
        alert.addButton(withTitle: NSLocalizedString("cancel_button", comment: "Cancel button"))
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            Task {
                await requestPermissionsAndConvert()
            }
        }
    }
    
    /// Requests permissions for directories where videos are located and then converts with black frame detection
    private func solicitarPermisosYConvertirConFramesNegros() async {
        // Para esta función, procesamos todos los videos (no solo los no-HEVC)
        let allVideos = wallpaperManager.videoFiles
        
        guard !allVideos.isEmpty else {
            await showAlert(
                title: NSLocalizedString("no_videos_available_title", comment: "No videos available title"),
                message: NSLocalizedString("no_videos_available_message", comment: "No videos available message")
            )
            return
        }
        
        // Obtener directorios únicos donde están los videos
        var uniqueDirectories = Set<URL>()
        for videoFile in allVideos {
            if let url = await wallpaperManager.resolveBookmark(for: videoFile) {
                let directory = url.deletingLastPathComponent()
                uniqueDirectories.insert(directory)
                await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: url)
            }
        }
        
        // Request permissions for each unique directory
        var allowedDirectories = Set<URL>()
        
        await MainActor.run {
            for directory in uniqueDirectories {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.allowsMultipleSelection = false
                openPanel.directoryURL = directory
                openPanel.message = String(format: NSLocalizedString("select_directory_black_frames_permission", comment: "Select directory for black frames permission"), directory.lastPathComponent)
                
                if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                    allowedDirectories.insert(selectedURL)
                }
            }
        }
        
        // If permissions were not granted for all directories, show alert and cancel
        guard allowedDirectories.count == uniqueDirectories.count else {
            await showAlert(
                title: NSLocalizedString("insufficient_permissions_title", comment: "Insufficient permissions title"),
                message: NSLocalizedString("insufficient_permissions_message", comment: "Insufficient permissions message")
            )
            return
        }
        
        // Iniciar la conversión con detección de frames negros
        await startBlackFrameConversion(videos: allVideos, allowedDirectories: allowedDirectories)
    }
    
    /// Inicia la conversión de videos con detección de frames negros
    private func startBlackFrameConversion(videos: [VideoFile], allowedDirectories: Set<URL>) async {
        await MainActor.run {
            isOptimizing = true
            videosProcessed = 0
            totalVideosToProcess = videos.count
            currentVideoBeingProcessed = ""
            optimizationErrors.removeAll()
        }
        
        for videoFile in videos {
            await MainActor.run {
                currentVideoBeingProcessed = videoFile.name
            }
            
            await convertVideoWithBlackFrames(videoFile: videoFile, allowedDirectories: allowedDirectories)
            
            await MainActor.run {
                videosProcessed += 1
            }
        }
        
        await MainActor.run {
            isOptimizing = false
            
            if optimizationErrors.isEmpty {
                // Mostrar alerta de éxito
                Task {
                    await showAlert(
                        title: NSLocalizedString("optimization_complete_title", comment: "Optimization complete title"),
                        message: String(format: NSLocalizedString("optimization_complete_message", comment: "Optimization complete message"), videos.count)
                    )
                }
            } else {
                // Mostrar alerta con errores
                let errorMessage = optimizationErrors.joined(separator: "\n")
                Task {
                    await showAlert(
                        title: NSLocalizedString("optimization_errors_title", comment: "Optimization errors title"),
                        message: String(format: NSLocalizedString("optimization_errors_message", comment: "Optimization errors message"), errorMessage)
                    )
                }
            }
        }
    }
    
    /// Convierte un video específico con detección de frames negros
    private func convertVideoWithBlackFrames(videoFile: VideoFile, allowedDirectories: Set<URL>) async {
        guard let originalURL = await wallpaperManager.resolveBookmark(for: videoFile) else {
            await MainActor.run {
                optimizationErrors.append("❌ \(videoFile.name): Could not access file")
            }
            return
        }
        
        defer {
            Task {
                await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: originalURL)
            }
        }
        
        let directory = originalURL.deletingLastPathComponent()
        guard allowedDirectories.contains(directory) else {
            await MainActor.run {
                optimizationErrors.append("❌ \(videoFile.name): No permissions for directory")
            }
            return
        }
        
        do {
            let outputURL = videoOptimizer.generateOptimizedURL(for: originalURL)
            _ = try await videoOptimizer.optimizeVideoWithBlackFrameDetection(videoFile, to: outputURL)
            
            // Validar que el archivo se creó correctamente
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                await MainActor.run {
                    optimizationErrors.append("❌ \(videoFile.name): Optimized file was not created")
                }
                return
            }
            
            // Reemplazar el archivo original con el optimizado
            do {
                let tempURL = originalURL.appendingPathExtension("backup")
                try FileManager.default.moveItem(at: originalURL, to: tempURL)
                try FileManager.default.moveItem(at: outputURL, to: originalURL)
                try FileManager.default.removeItem(at: tempURL)
                
                print("✅ Video optimized with black frame detection: \(videoFile.name)")
            } catch {
                await MainActor.run {
                    optimizationErrors.append("❌ \(videoFile.name): Error replacing file - \(error.localizedDescription)")
                }
            }
            
        } catch {
            await MainActor.run {
                optimizationErrors.append("❌ \(videoFile.name): \(error.localizedDescription)")
            }
        }
    }
    
    /// Requests permissions for directories where videos are located and then removes black frames
    private func requestPermissionsAndRemoveBlackFrames() async {
        let allVideos = wallpaperManager.videoFiles
        
        guard !allVideos.isEmpty else {
            await showAlert(
                title: NSLocalizedString("no_videos_available_title", comment: "No videos available title"),
                message: NSLocalizedString("no_videos_available_message", comment: "No videos available message")
            )
            return
        }
        
        // Obtener directorios únicos donde están los videos
        var uniqueDirectories = Set<URL>()
        for videoFile in allVideos {
            if let url = await wallpaperManager.resolveBookmark(for: videoFile) {
                let directory = url.deletingLastPathComponent()
                uniqueDirectories.insert(directory)
                await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: url)
            }
        }
        
        // Request permissions for each unique directory
        var allowedDirectories = Set<URL>()
        
        await MainActor.run {
            for directory in uniqueDirectories {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.allowsMultipleSelection = false
                openPanel.directoryURL = directory
                openPanel.message = String(format: NSLocalizedString("select_directory_black_frames_permission", comment: "Select directory for black frames permission"), directory.lastPathComponent)
                
                if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                    allowedDirectories.insert(selectedURL)
                }
            }
        }
        
        // Solo proceder si se otorgaron permisos para todos los directorios
        if allowedDirectories.count == uniqueDirectories.count {
            await startBlackFrameRemoval(videos: allVideos, allowedDirectories: allowedDirectories)
        } else {
            await showAlert(
                title: NSLocalizedString("permissions_required_title", comment: "Permissions required title"),
                message: NSLocalizedString("permissions_required_message", comment: "Permissions required message")
            )
        }
    }
    
    /// Inicia la eliminación de frames negros sin optimización HEVC
    private func startBlackFrameRemoval(videos: [VideoFile], allowedDirectories: Set<URL>) async {
        await MainActor.run {
            isOptimizing = true
            videosProcessed = 0
            totalVideosToProcess = videos.count
            currentVideoBeingProcessed = ""
            optimizationErrors.removeAll()
        }
        
        var videosConFramesEliminados = 0
        var videosOmitidos = 0
        
        for videoFile in videos {
            await MainActor.run {
                currentVideoBeingProcessed = String(format: NSLocalizedString("processing_video_black_frames", comment: "Processing video"), videoFile.name)
            }
            
            let hadBlackFrames = await removeBlackFramesFromVideo(videoFile: videoFile, allowedDirectories: allowedDirectories)
            
            if hadBlackFrames {
                videosConFramesEliminados += 1
            } else {
                videosOmitidos += 1
                await MainActor.run {
                    currentVideoBeingProcessed = String(format: NSLocalizedString("video_skipped_no_black_frames", comment: "Video skipped"), videoFile.name)
                }
            }
            
            await MainActor.run {
                videosProcessed += 1
            }
        }
        
        await MainActor.run {
            isOptimizing = false
            
            if optimizationErrors.isEmpty {
                // Mostrar alerta de éxito
                Task {
                    await showAlert(
                        title: NSLocalizedString("black_frames_complete_title", comment: "Black frames complete title"),
                        message: String(format: NSLocalizedString("black_frames_complete_message", comment: "Black frames complete message"), videos.count, videosConFramesEliminados, videosOmitidos)
                    )
                }
            } else {
                // Mostrar alerta con errores
                let errorMessage = optimizationErrors.joined(separator: "\n")
                Task {
                    await showAlert(
                        title: NSLocalizedString("optimization_errors_title", comment: "Optimization errors title"),
                        message: String(format: NSLocalizedString("optimization_errors_message", comment: "Optimization errors message"), errorMessage)
                    )
                }
            }
        }
    }
    
    /// Elimina frames negros de un video específico
    private func removeBlackFramesFromVideo(videoFile: VideoFile, allowedDirectories: Set<URL>) async -> Bool {
        guard let originalURL = await wallpaperManager.resolveBookmark(for: videoFile) else {
            await MainActor.run {
                optimizationErrors.append("❌ \(videoFile.name): Could not access file")
            }
            return false
        }
        
        defer {
            Task {
                await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: originalURL)
            }
        }
        
        let directory = originalURL.deletingLastPathComponent()
        guard allowedDirectories.contains(directory) else {
            await MainActor.run {
                optimizationErrors.append("❌ \(videoFile.name): Permissions denied for directory")
            }
            return false
        }
        
        do {
            let outputURL = originalURL.appendingPathExtension("tmp")
            let result = try await videoOptimizer.trimVideoBlackFrames(videoFile, to: outputURL)
            
            if result.hadBlackFrames {
                // Replace original file with version without black frames
                _ = try FileManager.default.replaceItem(at: originalURL, withItemAt: outputURL, backupItemName: nil, options: [], resultingItemURL: nil)
            } else {
                // Delete temporary file if there were no black frames
                try? FileManager.default.removeItem(at: outputURL)
            }
            
            return result.hadBlackFrames
            
        } catch {
            await MainActor.run {
                optimizationErrors.append("❌ \(videoFile.name): \(error.localizedDescription)")
            }
            return false
        }
    }
    
    /// Solicita permisos para los directorios donde están los videos y luego convierte
    private func requestPermissionsAndConvert() async {
        let videosNoHEVC = await detectNonHEVCVideos()
        
        guard !videosNoHEVC.isEmpty else {
            await showAlert(
                title: NSLocalizedString("no_videos_to_optimize_title", comment: "No videos to optimize title"),
                message: NSLocalizedString("no_videos_to_optimize_message", comment: "No videos to optimize message")
            )
            return
        }
        
        // Obtener directorios únicos donde están los videos
        var uniqueDirectories = Set<URL>()
        for videoFile in videosNoHEVC {
            if let url = await wallpaperManager.resolveBookmark(for: videoFile) {
                let directory = url.deletingLastPathComponent()
                uniqueDirectories.insert(directory)
                await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: url)
            }
        }
        
        // Request permissions for each unique directory
        var allowedDirectories = Set<URL>()
        
        await MainActor.run {
            for directory in uniqueDirectories {
                let openPanel = NSOpenPanel()
                openPanel.canChooseFiles = false
                openPanel.canChooseDirectories = true
                openPanel.allowsMultipleSelection = false
                openPanel.directoryURL = directory
                openPanel.message = "Select directory '\(directory.lastPathComponent)' to grant write permissions for HEVC optimization:"
                
                if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
                    allowedDirectories.insert(selectedURL)
                }
            }
        }
        
        // Solo proceder si se otorgaron permisos para todos los directorios
        if allowedDirectories.count == uniqueDirectories.count {
            await convertVideosToHEVC(allowedDirectories: allowedDirectories)
        } else {
            await showAlert(
                title: NSLocalizedString("permissions_required_title", comment: "Permissions required title"),
                message: NSLocalizedString("permissions_required_message", comment: "Permissions required message")
            )
        }
    }
    
    /// Convierte videos no-HEVC a HEVC de forma asíncrona
    private func convertVideosToHEVC(allowedDirectories: Set<URL> = []) async {
        let videosNoHEVC = await detectNonHEVCVideos()
        
        guard !videosNoHEVC.isEmpty else {
            await showAlert(
                title: NSLocalizedString("no_videos_to_optimize_title", comment: "No videos to optimize title"),
                message: NSLocalizedString("no_videos_to_optimize_message", comment: "No videos to optimize message")
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
                let optimizedURL = try await convertVideoToHEVC(videoFile)
                await updateVideoInList(originalVideoFile: videoFile, optimized: optimizedURL, allowedDirectories: allowedDirectories)
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
        
        await showAlert(
            title: NSLocalizedString("optimization_completed_title", comment: "Optimization completed title"),
            message: String(format: NSLocalizedString("optimization_completed_message", comment: "Optimization completed message"), videosNoHEVC.count)
        )
    }
    
    /// Detecta videos que no están en formato HEVC
    private func detectNonHEVCVideos() async -> [VideoFile] {
        var videosNoHEVC: [VideoFile] = []
        
        for videoFile in wallpaperManager.videoFiles {
            // Resolver bookmark para acceso security-scoped
            guard let url = await wallpaperManager.resolveBookmark(for: videoFile) else {
                print("⚠️ No se pudo resolver bookmark para: \(videoFile.name)")
                continue
            }
            
            defer {
                // Liberar acceso security-scoped
                Task {
                    await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: url)
                }
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
    private func convertVideoToHEVC(_ videoFile: VideoFile) async throws -> URL {
        // Validar disponibilidad del preset HEVC
        guard AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality) else {
            throw NSError(domain: "OptimizationError", code: 4, userInfo: [NSLocalizedDescriptionKey: "HEVC no está disponible en este sistema"])
        }
        
        print("🔍 HEVC preset disponible, iniciando conversión para: \(videoFile.name)")
        
        // Resolver bookmark para acceso security-scoped
        guard let inputURL = await wallpaperManager.resolveBookmark(for: videoFile) else {
            throw NSError(domain: "OptimizationError", code: 3, userInfo: [NSLocalizedDescriptionKey: "No se pudo acceder al archivo: \(videoFile.name)"])
        }
        
        defer {
            // Liberar acceso security-scoped
            Task {
                await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: inputURL)
            }
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
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }
        
        guard exportSession.status == .completed else {
            // Limpiar archivo temporal en caso de error
            try? FileManager.default.removeItem(at: tempURL)
            
            let errorMessage = exportSession.error?.localizedDescription ?? "Error desconocido en la exportación"
            print("❌ Error en exportación: \(errorMessage)")
            throw NSError(domain: "OptimizationError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error en la exportación: \(errorMessage)"])
        }
        
        // Validar que el archivo resultante es realmente HEVC
        try await validateHEVCCodec(url: tempURL)
        
        print("✅ Conversión HEVC exitosa para: \(videoFile.name)")
        return tempURL
    }
    
    /// Valida que un archivo de video use codec HEVC
    private func validateHEVCCodec(url: URL) async throws {
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
    private func updateVideoInList(originalVideoFile: VideoFile, optimized: URL, allowedDirectories: Set<URL> = []) async {
        guard let index = wallpaperManager.videoFiles.firstIndex(where: { $0.id == originalVideoFile.id }) else {
            print("⚠️ VideoFile no encontrado en la lista")
            // Clean up temporary file
            try? FileManager.default.removeItem(at: optimized)
            return
        }
        
        var directoryToCleanup: URL?
        
        do {
            // Resolve original file bookmark
            guard let originalURL = await wallpaperManager.resolveBookmark(for: originalVideoFile) else {
                print("⚠️ No se pudo resolver bookmark del archivo original: \(originalVideoFile.name)")
                // Clean up temporary file
                try? FileManager.default.removeItem(at: optimized)
                return
            }
            
            defer {
                Task {
                    await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: originalURL)
                }
            }
        
            print("🔄 Reemplazando archivo original: \(originalURL.lastPathComponent)")
            
            let originalDirectory = originalURL.deletingLastPathComponent()
            
            // If allowed directories were provided, use them for sandbox access
            if !allowedDirectories.isEmpty {
                // Find the corresponding allowed directory
                guard let found = allowedDirectories.first(where: { $0.path == originalDirectory.path }) else {
                    throw NSError(domain: "OptimizationError", code: 9, userInfo: [NSLocalizedDescriptionKey: "No permissions found for directory: \(originalDirectory.path)"])
                }
                
                // Access directory with sandbox permissions
                guard found.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "OptimizationError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Could not access directory with sandbox permissions"])
                }
                
                directoryToCleanup = found
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
            try FileManager.default.moveItem(at: optimized, to: finalURL)
            
            print("✅ Archivo convertido movido exitosamente: \(finalURL.lastPathComponent)")
            
            // Crear bookmark para el archivo convertido
            var bookmarkData: Data?
            
            // Intentar crear bookmark para el archivo específico
            do {
                // First verify that the file exists and is accessible
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
                let _ = try URL(resolvingBookmarkData: bookmarkData!, 
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
                
                // Verify that the bookmark works before deleting the original
                do {
                    if let testURL = await wallpaperManager.resolveBookmark(for: updatedVideoFile) {
                        await wallpaperManager.bookmarkActor.stopAccessingSecurityScopedResource(url: testURL)
                        
                        // If we get here, the bookmark works, delete original file
                        try FileManager.default.removeItem(at: originalURL)
                        print("🗑️ Original file deleted after verifying bookmark")
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
            
            // Reemplazar por el optimizado en el MainActor
            await MainActor.run {
                wallpaperManager.videoFiles[index] = updatedVideoFile
                wallpaperManager.saveVideos()
            }
            
        } catch {
            print("❌ Error reemplazando archivo: \(error.localizedDescription)")
            // Clean up temporary file in case of error
            try? FileManager.default.removeItem(at: optimized)
        }
        
        // Limpiar acceso security-scoped si se usó
        directoryToCleanup?.stopAccessingSecurityScopedResource()
    }
    
    /// Muestra una alerta de forma asíncrona
    private func showAlert(title: String, message: String) async {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    /// Cierra la ventana de configuración
    private func closeWindow() {
        DispatchQueue.main.async {
            // Look for the settings window
            if let window = NSApp.windows.first(where: { window in
                window.contentView?.subviews.contains { view in
                    String(describing: type(of: view)).contains("SettingsView")
                } ?? false
            }) {
                window.close()
                print("✅ Settings window closed")
            } else {
                // Fallback: use SwiftUI dismiss
                dismiss()
                print("✅ Settings view closed with dismiss")
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
        let wallpaperManager = WallpaperManager()
        SettingsView()
            .environmentObject(wallpaperManager)
            .environmentObject(LaunchManager())
    }
}
