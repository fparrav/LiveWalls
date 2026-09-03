import Foundation
import AppKit
import Combine
import AVFoundation
import os.log
import ImageIO
import UniformTypeIdentifiers

// Asegurarse de que Logger esté disponible
#if canImport(os)
import os
#endif

// Specific logger for memory debugging
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

/// Main video wallpaper manager for LiveWalls
/// Handles playback, changing and configuration of videos as desktop backgrounds
@MainActor
class WallpaperManager: NSObject, ObservableObject, NSWindowDelegate {
    
    // MARK: - Published Properties (MUST be declared BEFORE init)
    @Published var videoFiles: [VideoFile] = []
    @Published var currentVideo: VideoFile? = nil
    @Published var isPlayingWallpaper = false
    @Published var isAutoChangeEnabled = false
    @Published var autoChangeInterval: TimeInterval = 10 * 60 // 10 minutes default
    @Published var isShuffleMode: Bool = false {
        didSet {
            // Persist shuffle mode to UserDefaults
            userDefaults.set(isShuffleMode, forKey: shuffleModeKey)
        }
    }
    
    // MARK: - Private Properties
    private let appLogger = Logger(subsystem: "com.livewalls.app", category: "WallpaperManager")
    // Task 1.3: dedicated retained-level logger for recovery decision/outcome (complements RecoveryTelemetry file)
    private let recoveryDecisionLogger = Logger(subsystem: "com.livewalls.app", category: "RecoveryDecision")
    // Task 1.5: per-window render-advance probes + aggregate observable
    private var renderAdvanceProbes: [RenderAdvanceProbe] = []
    private var renderAdvancePollTask: Task<Void, Never>?
    @Published private(set) var renderAdvanceState: RenderAdvanceVerdict = .idle
    private var desktopVideoInstances: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)] = []
    private let notificationManager: NotificationManager
    private var currentStaticWallpaperURL: URL?
    private var staticFrameUpdateTimer: Timer?
    
    // MARK: - New Fullscreen and Timer Management
    private let fullscreenDetector = FullscreenDetector()
    private let timerManager = WallpaperTimerManager.shared
    private let transitionManager = TransitionManager()
    private var isWallpaperPausedForFullscreen = false
    
    // MARK: - Transition Settings
    private let isTransitionEnabledKey = "IsTransitionEnabled"
    private let transitionDurationKey = "TransitionDuration"
    private let transitionTypeKey = "TransitionType"
    private var isTransitionEnabled = true
    private var transitionDuration: TimeInterval = 1.0  // Reducido de 2.0s a 1.0s para transiciones más rápidas
    private var transitionType: TransitionManager.TransitionType = .crossfade
    
    // FASE 5.3: Transition concurrency prevention — latching boolean removed (task 2.3).
    // Transitions are now serialized by the exclusive lock in WallpaperOperationActor.

     // FASE 5: Rate limiting for ensurePlaying() only (latching boolean removed in task 2.3)
     private var lastEnsurePlayingTime: Date?
     private let ensurePlayingMinInterval: TimeInterval = 2.0

    // MARK: - Wallpaper change serialization (Task 2.3)

    /// Hard timeout for a guarded wallpaper operation. Set above the lock's
    /// acquire timeout (20s) so lock contention is reported first; this is the
    /// backstop that guarantees the in-flight guard is released even if the
    /// operation itself stalls (design D5).
    static let operationGuardTimeout: Duration = .seconds(25)

    /// A user-initiated wallpaper change (next / previous) that arrived while an
    /// operation was already running. Coalesced (last-one-wins) and applied once
    /// the guard clears — never dropped (design D5). Stored as an intent, not a
    /// resolved video, so the drain re-resolves against fresh state.
    private enum PendingWallpaperChange {
        case next
        case previous
    }
    private var pendingWallpaperChange: PendingWallpaperChange? = nil

    /// True while a guarded wallpaper operation is running. Set on entry to
    /// `applyGuardedWallpaperChange`, cleared in its `defer` on every exit path
    /// (success, throw, or timeout) — it can never latch.
    private var wallpaperOperationInFlight = false

    // MARK: - Bounded Recovery Retry Policy (Task 2.4 / Design D2)

    /// Count of consecutive recovery attempts for the current stall episode.
    /// Reset to 0 on any healthy check (ensurePlaying / didWake success).
    private var recoveryAttempts: Int = 0

    /// Maximum number of recovery attempts before giving up and logging.
    private let maxRecoveryAttempts = 3

    /// Escalating backoff for each attempt (index = attempt number).
    /// Attempt 1: immediate, Attempt 2: 3s, Attempt 3: 10s.
    private let recoveryBackoff: [Duration] = [.seconds(0), .seconds(3), .seconds(10)]

    /// True once max attempts are exhausted and the "exhausted" log/telemetry has
    /// been emitted. Prevents spamming the durable log when triggers keep firing
    /// (e.g., external monitor genuinely off). Reset alongside recoveryAttempts.
    private var recoveryExhausted: Bool = false

    /// Guard to prevent concurrent recovery loops. Two `ensurePlaying` unhealthy
    /// triggers could otherwise start parallel loops during the ~4s+ awaits.
    private var isRecoveryInProgress: Bool = false

    /// Runs `operation` on the main actor with a hard timeout. If `timeout`
    /// elapses first the operation task is cancelled, its wind-down is awaited
    /// (so nothing is abandoned mid-flight), and `WallpaperOperationTimeoutError`
    /// is thrown. If the operation finishes first the timer is cancelled and the
    /// call returns immediately.
    private func withOperationTimeout(
        _ timeout: Duration,
        operation: @escaping @MainActor () async -> Void
    ) async throws {
        let opTask = Task { @MainActor in await operation() }
        let timeoutTask = Task { () -> Bool in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return false // cancelled — the operation finished first
            }
            opTask.cancel()
            return true // timed out
        }
        // Wait for the operation (or its cancelled wind-down) to complete.
        await opTask.value
        timeoutTask.cancel()
        if await timeoutTask.value {
            throw WallpaperOperationTimeoutError(timeout: timeout)
        }
    }

    // MARK: - Background color windows for transitions
    private var backgroundColorWindows: [NSWindow] = []
    
    // MARK: - Variables for window destruction synchronization
    var pendingDestroyCompletion: (() -> Void)? = nil
    var pendingWindowClosures: Set<NSWindow> = []
    var closedWindowsCount: Int = 0
    
    // MARK: - UserDefaults and configuration
    // PHASE 4: Deferred resource cleanup during transitions
    // Changed from 0.1s to 2.5s to prevent cleanup during 2.0s transition
    // TransitionManager.transitionDuration = 2.0s
    // resourceReleaseDelay = 2.5s (transition + 0.5s grace period)
    // This ensures cleanup happens AFTER transition completes, preventing frame drops
    private let resourceReleaseDelay: TimeInterval = 2.5
    
    // PHASE 3: Extended delay for Space changes (includes throttle + operations + safety margin)
    // Space changes: throttle (0.5s) + operations (0.5-1.0s) + cleanup (5.0s) = total delay needed
    private let resourceReleaseDelayForSpaceChange: TimeInterval = 5.0
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Security-Scoped Resource Tracking
    let bookmarkActor = BookmarkActor()
    let persistenceActor = PersistenceActor()
    private let systemReadinessObserver = SystemReadinessObserver()
    private let startupCoordinator = StartupCoordinator()
     private let playbackHealthChecker = PlaybackHealthChecker()
     private let windowCreationCoordinator = WindowCreationCoordinator()
      private let scheduledHealthCheckManager = ScheduledHealthCheckManager()
      private let videoPreloader = VideoPreloader()
      private let throttleManager = ThrottleManager() // FASE 2: Throttling para eventos frecuentes
      // NOTE: PlaybackTelemetry integration pending - add to Xcode project target first
      // private let playbackTelemetry = PlaybackTelemetry() // PHASE 7: Production telemetry
      private let recoveryTelemetry = RecoveryTelemetry() // Task 1.1: Durable recovery-lifecycle telemetry
      // Task 2.6 / D6: BookmarkActor is now the single source of truth for
      // security-scoped access tracking (ref-count). The old local mirror
      // `activeSecurityScopedURLs` has been removed.
      private let resourceTrackingQueue = DispatchQueue(label: "security.resources", attributes: .concurrent)

    // MARK: - Synchronization to prevent crashes
    private let wallpaperOperationQueue = DispatchQueue(label: "com.livewalls.wallpaperQueue", attributes: .concurrent)
    private let wallpaperOperationActor = WallpaperOperationActor()
    private var isApplyingStaticWallpaper = false
    private var pendingStaticApplyWorkItem: DispatchWorkItem?
     private var isCleaningUp = false
     private var autoStartScheduled = false
     
     // MARK: - Shuffle Mode Properties
     private var shuffleHistory: [UUID] = []
     private let shuffleHistoryMaxSize = 5
     private let shuffleModeKey = "ShuffleModeEnabled"
     
     // MARK: - Operation Mutex (Task 2.1 / design D4)

    /// Thrown when the wallpaper-operation mutex cannot be acquired within the
    /// configured timeout. Distinct from the operation's own errors so callers
    /// can log/recover specifically about the lock vs. the work.
    struct WallpaperOperationTimeoutError: Error, CustomStringConvertible {
        let timeout: Duration
        var description: String {
            return "Wallpaper operation timed out waiting for exclusive access after \(timeout)"
        }
    }

    /// Serializes wallpaper operations (start/stop/rebuild). Real async mutex:
    /// if a caller is in flight, subsequent callers wait in FIFO order; the wait
    /// is bounded by `timeout`, and the lock is always released — on success,
    /// on operation `throw`, on timeout, and on caller cancellation.
    private actor WallpaperOperationActor {
        private var isBusy: Bool = false
        // FIFO queue of pending waiters. Each entry stores the waiter's id,
        // its continuation, and the requested timeout (so the timeout error
        // carries the correct duration even when multiple waiters are queued).
        private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>, timeout: Duration)] = []

        /// Default timeout for lock acquisition. Long enough to cover the
        /// slowest legitimate wallpaper rebuild (window teardown + recreate +
        /// static-frame apply) on real hardware; short enough that a wedged
        /// recovery cannot stall the UI indefinitely.
        static let defaultTimeout: Duration = .seconds(20)

        /// Runs `operation` while holding the wallpaper-operation mutex.
        ///
        /// Semantics:
        /// - FIFO: callers are admitted in the order they called `acquire()`.
        /// - Bounded: if the lock is not acquired within `timeout`, throws
        ///   `WallpaperOperationTimeoutError`. The pending caller is removed
        ///   from the queue and resumed so no continuation leaks.
        /// - Bounded-cleanup: if the calling Task is cancelled while waiting,
        ///   the continuation is removed from the queue and resumed with
        ///   `CancellationError`; if cancelled while holding the lock, the
        ///   lock is still released (via `defer`).
        /// - No double-resume: the queued continuation is resumed exactly once
        ///   (by the next release, by timeout, or by cancellation), whichever
        ///   happens first.
        func withExclusiveAccess<T>(
            timeout: Duration = WallpaperOperationActor.defaultTimeout,
            @_implicitSelfCapture operation: () async throws -> T
        ) async throws -> T {
            try await acquire(timeout: timeout)
            // Guaranteed release on every exit path (success, throw, cancel).
            defer { release() }
            return try await operation()
        }

        // MARK: - Internal acquire / release

        private func acquire(timeout: Duration) async throws {
            // Fast path: uncontended. Checking + flipping `isBusy` happens in
            // a single actor hop, so no two callers can both win this branch.
            if !isBusy {
                isBusy = true
                return
            }

            // Slow path: park a CheckedContinuation in `waiters` and wait
            // for one of three things to resume it — the lock becoming free
            // (via `release`), the timeout elapsing, or the calling Task
            // being cancelled. Whichever fires first wins; the others are
            // observed to be no-ops by `timeOutWaiter` / `cancelWaiter`
            // because the entry has already been removed from `waiters`.
            let waiterID = UUID()

            // We need the timeout arm to be cancellable so that if the
            // caller wins (lock released, or cancellation) we don't keep a
            // sleeping Task around until the original timeout fires.
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.timeOutWaiter(id: waiterID)
            }

            do {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        // Appending and observing `isBusy` are both inside
                        // the actor, so no other caller can sneak past us
                        // between the fast-path miss above and this append.
                        // Store timeout per-waiter so each error carries its own duration.
                        self.waiters.append((id: waiterID, continuation: continuation, timeout: timeout))
                    }
                } onCancel: {
                    Task { await self.cancelWaiter(id: waiterID) }
                }
            } catch {
                // Whether we lost by timeout or by cancellation, the spawned
                // timeout arm is no longer needed — cancel it so it does not
                // linger until `timeout` elapses against an empty queue.
                timeoutTask.cancel()
                throw error
            }
            timeoutTask.cancel()

            // After the continuation returns successfully, the lock is ours.
            // From the caller's perspective `acquire()` is "done"; we don't
            // need to touch `isBusy` here because either we just won the
            // fast path (set it true) or `release()` handed it to us (it
            // stays true across the hand-off, by design).
        }

        private func release() {
            // FIFO: hand the lock to the next waiter if any; otherwise free it.
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                // `isBusy` stays true across the hand-off — the next caller's
                // `acquire()` returned via this continuation and observes it
                // already set, so it proceeds straight into its operation.
                next.continuation.resume()
            } else {
                isBusy = false
            }
        }

        /// Resume a queued waiter with `WallpaperOperationTimeoutError` if it
        /// is still parked. Idempotent — if the waiter already resumed (e.g.
        /// the lock was released first, or the caller was cancelled), this
        /// is a no-op so the continuation is never double-resumed.
        private func timeOutWaiter(id: UUID) async {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else {
                return // already resumed (lock released or cancelled)
            }
            let entry = waiters.remove(at: index)
            entry.continuation.resume(throwing: WallpaperOperationTimeoutError(timeout: entry.timeout))
        }

        /// Resume a queued waiter with `CancellationError` if it is still
        /// parked. Idempotent — if the waiter already resumed (e.g. the lock
        /// was released first, or the timeout fired first), this is a no-op
        /// so the continuation is never double-resumed.
        private func cancelWaiter(id: UUID) async {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else {
                return // already resumed (lock released or timed out)
            }
            let entry = waiters.remove(at: index)
            entry.continuation.resume(throwing: CancellationError())
        }
    }

    /// Schedule setting the static wallpaper with debouncing to avoid hammering NSWorkspace
    private func scheduleStaticWallpaperApply(for nextURL: URL) {
        // Cancel any pending apply
        pendingStaticApplyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.isApplyingStaticWallpaper {
                    return
                }
                self.isApplyingStaticWallpaper = true
                
                Task.detached { [weak self] in
                    guard let self else { return }
                    if let staticImageURL = await self.generateStaticWallpaperFrame(for: nextURL) {
                        DispatchQueue.main.async {
                            let success = self.setSystemStaticWallpaper(imageURL: staticImageURL)
                            if success {
                                self.appLogger.info("🖼️ Frame estático generado y aplicado (debounced)")
                            }
                            // No deletion to avoid races; keep cached
                        }
                    }
                    await MainActor.run {
                        self.isApplyingStaticWallpaper = false
                    }
                }
            }
        }
        pendingStaticApplyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
    
    // MARK: - Initialization
     override init() {
         self.notificationManager = NotificationManager.shared
         super.init()
         
         appLogger.info("\(NSLocalizedString("initializing_wallpaper_manager", comment: "Initializing WallpaperManager"), privacy: .public)")
         
         // Load shuffle mode from UserDefaults
         self.isShuffleMode = userDefaults.bool(forKey: shuffleModeKey)
         
         // Cargar configuración en background usando PersistenceActor (NO bloquear init)
         Task.detached { [weak self] in
             guard let self else { return }
             await self.loadDataInBackground()
         }
         
         loadTransitionSettings()
         setupScreenChangeNotifications()
         setupWorkspaceNotifications()
         setupTerminationHandling()
         setupFullscreenDetection()
         setupAppActivationNotifications()

         // Task 1.1: Initialize durable recovery telemetry writer
         Task { [recoveryTelemetry] in
             await recoveryTelemetry.configure()
         }

         // Intentar auto‑inicio cuando el estado esté listo (sin depender de delays fijos)
         attemptAutoStart()
         
         appLogger.info("\(NSLocalizedString("wallpaper_manager_initialized", comment: "WallpaperManager initialized"), privacy: .public)")
     }
    
    deinit {
        MainActor.assumeIsolated { [self] in
            appLogger.info("\(NSLocalizedString("deinitializing_wallpaper_manager", comment: "Deinitializing WallpaperManager"), privacy: .public)")
            timerManager.stopTimer()
            cleanupAllResources()
        }
    }

    // MARK: - Startup Helpers
    
    /// Intenta iniciar la reproducción automáticamente cuando la configuración y el sistema estén listos
    /// Usa StartupCoordinator para evitar bloqueos del main thread con backoff exponencial
    private func attemptAutoStart() {
        guard UserDefaults.standard.bool(forKey: "AutoStartWallpaper") else { return }
        guard !autoStartScheduled else { return }
        
        autoStartScheduled = true
        appLogger.info("🚀 Iniciando coordinación de startup con backoff exponencial")
        
        // Lanzar coordinación de startup sin bloquear
        Task { [weak self] in
            guard let self else { return }
            
            // Coordinar startup con backoff exponencial (máximo 5 reintentos)
            let success = await self.startupCoordinator.coordinateStartup(
                hasVideo: { [weak self] in
                    guard let self else { return false }
                    return self.currentVideo != nil && !self.videoFiles.isEmpty
                },
                hasScreens: { [weak self] in
                    guard let self else { return false }
                    return await self.systemReadinessObserver.waitUntilReady(timeout: 5.0)
                },
                maxRetries: 5,
                startAction: { [weak self] in
                    guard let self else { return }
                    self.startWallpaperSafe()
                }
            )
            
            if success {
                await MainActor.run {
                    self.appLogger.info("✅ AutoStart completado exitosamente")
                }
            } else {
                await MainActor.run {
                    self.appLogger.warning("⚠️ AutoStart: condiciones no cumplidas después de reintentos")
                }
            }
        }
    }
    

    
    // MARK: - Video Management
    
    // MARK: - Duplicate Detection
    
    /// Enum for duplicate handling options
    enum DuplicateHandling: CaseIterable {
        case skip
        case replace
        case keepBoth
        
        var localizedString: String {
            switch self {
            case .skip:
                return NSLocalizedString("duplicate_action_skip", comment: "Skip duplicate video")
            case .replace:
                return NSLocalizedString("duplicate_action_replace", comment: "Replace existing video")
            case .keepBoth:
                return NSLocalizedString("duplicate_action_keep_both", comment: "Keep both videos")
            }
        }
    }
    
    /// Checks if a URL represents a duplicate video based on file path
    /// - Parameter url: URL to check
    /// - Returns: true if a video with the same path already exists
    private func isDuplicateByURL(_ url: URL) -> Bool {
        let normalizedPath = url.standardizedFileURL.path
        return videoFiles.contains { videoFile in
            let existingPath = videoFile.url.standardizedFileURL.path
            return existingPath == normalizedPath
        }
    }
    
    /// Verifica si una URL representa un video duplicado basado en bookmark data
    /// - Parameter url: URL to check
    /// - Returns: true si ya existe un video con bookmark data equivalente
    private func isDuplicateByBookmark(_ bookmarkData: Data) -> Bool {
        return videoFiles.contains { videoFile in
            guard let existingBookmarkData = videoFile.bookmarkData else { return false }
            return existingBookmarkData == bookmarkData
        }
    }
    
    /// Encuentra un video duplicado existente para la URL dada
    /// - Parameter url: URL del nuevo video
    /// - Returns: VideoFile existente que es duplicado, o nil si no hay duplicados
    private func findDuplicateVideo(for url: URL) -> VideoFile? {
        let normalizedPath = url.standardizedFileURL.path
        return videoFiles.first { videoFile in
            let existingPath = videoFile.url.standardizedFileURL.path
            return existingPath == normalizedPath
        }
    }
    
    /// Muestra un diálogo para manejar un video duplicado
    /// - Parameters:
    ///   - originalVideo: VideoFile existente en la biblioteca
    ///   - newURL: URL del nuevo video que es duplicado
    /// - Returns: Acción elegida por el usuario
    private func showDuplicateDialog(originalVideo: VideoFile, newURL: URL) -> DuplicateHandling {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("duplicate_video_title", comment: "Duplicate video detected")
        alert.informativeText = String(format: NSLocalizedString("duplicate_video_message", comment: "Duplicate video message"), newURL.lastPathComponent, originalVideo.name)
        alert.alertStyle = .informational
        alert.icon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        
        // Agregar botones en orden inverso (NSAlert los muestra de derecha a izquierda)
        alert.addButton(withTitle: DuplicateHandling.keepBoth.localizedString)
        alert.addButton(withTitle: DuplicateHandling.replace.localizedString)
        alert.addButton(withTitle: DuplicateHandling.skip.localizedString)
        
        let response = alert.runModal()
        
        // NSAlert.ButtonType.alertFirstButtonReturn corresponde al último botón agregado
        switch response {
        case .alertFirstButtonReturn:
            return .keepBoth
        case .alertSecondButtonReturn:
            return .replace
        case .alertThirdButtonReturn:
            return .skip
        default:
            return .skip // Default fallback
        }
    }
    
    /// Genera un nombre único para un video duplicado
    /// - Parameter originalName: Nombre original del video
    /// - Returns: Nuevo nombre único
    private func generateUniqueName(for originalName: String) -> String {
        let baseName = originalName
        var counter = 2
        var candidateName = "\(baseName) (\(counter))"
        
        while videoFiles.contains(where: { $0.name == candidateName }) {
            counter += 1
            candidateName = "\(baseName) (\(counter))"
        }
        
        return candidateName
    }
    
    /// Agrega archivos de video a la lista de wallpapers disponibles
    /// - Parameter urls: URLs de los archivos de video a agregar
    func addVideoFiles(urls: [URL]) async {
        appLogger.info("\(String(format: NSLocalizedString("adding_video_files", comment: "Adding video files"), urls.count), privacy: .public)")
        
        var addedCount = 0
        var skippedCount = 0
        var replacedCount = 0
        
        for url in urls {
            // Verificar si es un duplicado antes de procesar
            if let existingVideo = findDuplicateVideo(for: url) {
                appLogger.info("🔍 Duplicado detectado: \(url.lastPathComponent) ya existe como '\(existingVideo.name)'")
                
                // Verificar si hay una preferencia guardada
                let duplicateHandlingRawValue = UserDefaults.standard.string(forKey: "DuplicateHandlingPreference") ?? "askAlways"
                let userChoice: DuplicateHandling
                
                if duplicateHandlingRawValue == "askAlways" {
                    // Mostrar diálogo para manejar duplicado
                    userChoice = showDuplicateDialog(originalVideo: existingVideo, newURL: url)
                } else {
                    // Usar preferencia guardada
                    switch duplicateHandlingRawValue {
                    case "skip":
                        userChoice = .skip
                    case "replace":
                        userChoice = .replace
                    case "keepBoth":
                        userChoice = .keepBoth
                    default:
                        userChoice = .skip
                    }
                    appLogger.info("🔧 Usando preferencia guardada: \(duplicateHandlingRawValue)")
                }
                
                switch userChoice {
                case .skip:
                    appLogger.info("⏭️ Saltando duplicado: \(url.lastPathComponent)")
                    skippedCount += 1
                    continue
                    
                case .replace:
                    appLogger.info("🔄 Reemplazando existente: \(existingVideo.name)")
                    // Remover el video existente y continuar con el procesamiento normal
                    self.videoFiles.removeAll { $0.id == existingVideo.id }
                    replacedCount += 1
                    
                case .keepBoth:
                    appLogger.info("📂 Manteniendo ambos: \(url.lastPathComponent)")
                    // Continuar con procesamiento normal pero con nombre único
                    break
                }
            }
            
            // Verificar si ya tenemos acceso al archivo
            var accessGranted = false
            
            // Intentar iniciar acceso security-scoped si no está activo
            if !url.startAccessingSecurityScopedResource() {
                appLogger.warning("\(String(format: NSLocalizedString("could_not_start_security_scoped_access", comment: "Could not start security scoped access"), url.lastPathComponent), privacy: .public)")
            } else {
                accessGranted = true
            }
            
            do {
                // Verificar que el archivo existe y es accesible
                guard try url.checkResourceIsReachable() else {
                    appLogger.error("\(String(format: NSLocalizedString("file_not_accessible", comment: "File not accessible"), url.lastPathComponent), privacy: .public)")
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                    continue
                }
                
                // Crear bookmark security-scoped
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                // Generar miniatura del video
                let thumbnail = await generateThumbnail(for: url)
                
                // Determinar el nombre del video (único si es necesario)
                var videoName = url.deletingPathExtension().lastPathComponent
                if let existingVideo = findDuplicateVideo(for: url),
                   videoFiles.contains(where: { $0.id == existingVideo.id }) {
                    // Solo si el video existente aún está en la lista (no fue reemplazado)
                    videoName = generateUniqueName(for: videoName)
                }
                
                let videoFile = VideoFile(
                    url: url,
                    name: videoName,
                    thumbnailData: thumbnail,
                    bookmarkData: bookmarkData
                )
                
                let countBefore = self.videoFiles.count
                self.videoFiles.append(videoFile)
                let countAfter = self.videoFiles.count
                
                // Si no hay video activo y este es el primer video, establecerlo como activo
                if self.currentVideo == nil && countBefore == 0 {
                    self.currentVideo = videoFile
                    await self.persistenceActor.saveCurrentVideo(videoFile)
                    self.appLogger.info("✨ Primer video agregado, establecido como activo: \(videoFile.name)")
                }
                
                self.saveVideos()
                self.appLogger.info("\(String(format: NSLocalizedString("video_added", comment: "Video added"), videoFile.name), privacy: .public)")
                self.appLogger.info("\(String(format: NSLocalizedString("videos_count_updated", comment: "Videos count updated"), countBefore, countAfter), privacy: .public)")
                
                // Additional debug to verify SwiftUI receives the update
                print(String(format: NSLocalizedString("videofiles_updated_debug", comment: "VideoFiles updated debug"), self.videoFiles.count))
                print(String(format: NSLocalizedString("names_debug", comment: "Names debug"), self.videoFiles.map { $0.name }.joined(separator: ", ")))
                
                addedCount += 1
                
                // Detener acceso temporal ya que tenemos el bookmark
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
                
            } catch {
                appLogger.error("\(String(format: NSLocalizedString("error_processing_file", comment: "Error processing file"), url.lastPathComponent, error.localizedDescription), privacy: .public)")
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        
        // Show import summary
        var summaryMessage = ""
        if addedCount > 0 {
            summaryMessage += String(format: NSLocalizedString("import_summary_added", comment: "Import summary added"), addedCount)
        }
        if skippedCount > 0 {
            if !summaryMessage.isEmpty { summaryMessage += "\n" }
            summaryMessage += String(format: NSLocalizedString("import_summary_skipped", comment: "Import summary skipped"), skippedCount)
        }
        if replacedCount > 0 {
            if !summaryMessage.isEmpty { summaryMessage += "\n" }
            summaryMessage += String(format: NSLocalizedString("import_summary_replaced", comment: "Import summary replaced"), replacedCount)
        }
        
        if !summaryMessage.isEmpty {
            self.notificationManager.showMessage(title: NSLocalizedString("import_completed_title", comment: "Import completed"), message: summaryMessage)
            self.appLogger.info("📊 Import summary: \(summaryMessage)")
        }
    }
    
    /// Generates a thumbnail for the video
    /// - Parameter url: URL of the video file
    /// - Returns: Image data in PNG format or nil if it fails
    private func generateThumbnail(for url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 120, height: 80)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: CMTime.zero, actualTime: nil)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 80))
            return nsImage.tiffRepresentation
        } catch {
            appLogger.warning("\(String(format: NSLocalizedString("could_not_generate_thumbnail", comment: "Could not generate thumbnail"), url.lastPathComponent), privacy: .public)")
            return nil
        }
    }
    
    /// Generates a high resolution frame from the video to use as static wallpaper
    /// - Parameter url: URL of the video file
    /// - Parameter timeOffset: Specific video time (nil for random time)
    /// - Returns: URL of temporary image file or nil if it fails
    private func generateStaticWallpaperFrame(for url: URL, timeOffset: CMTime? = nil) async -> URL? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Use main screen resolution for better quality
        if let mainScreen = NSScreen.main {
            let screenSize = mainScreen.frame.size
            let scale = mainScreen.backingScaleFactor
            imageGenerator.maximumSize = CGSize(
                width: screenSize.width * scale,
                height: screenSize.height * scale
            )
        }
        
        // Generate high quality image
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        
        do {
            // Determine time of frame to extract
            let time: CMTime
            if let specificTime = timeOffset {
                time = specificTime
            } else {
                // Get video duration and generate random time
                let duration = try await asset.load(.duration)
                let durationSeconds = CMTimeGetSeconds(duration)
                if durationSeconds > 0 {
                    let randomSeconds = Double.random(in: 0...(durationSeconds * 0.8)) // Avoid the end
                    time = CMTime(seconds: randomSeconds, preferredTimescale: 600)
                } else {
                    time = CMTime(seconds: 1.0, preferredTimescale: 600)
                }
            }
            
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            
            // Create NSImage and convert to data
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            ))
            
            guard let imageData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: imageData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                appLogger.error("❌ Error converting image to PNG")
                return nil
            }
            
            // Try using Application Support directory first
            guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                appLogger.error("❌ Could not get Application Support directory")
                return nil
            }
            
            let livewallsDir = appSupportURL.appendingPathComponent("LiveWalls")
            var finalImageURL: URL
            
            // Create directory and file with robust error handling
            do {
                // Ensure the directory exists
                if !FileManager.default.fileExists(atPath: livewallsDir.path) {
                    try FileManager.default.createDirectory(at: livewallsDir, withIntermediateDirectories: true, attributes: nil)
                    appLogger.info("📁 LiveWalls directory created: \(livewallsDir.path)")
                }
                
                // Use timestamp to avoid file conflicts
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "wallpaper_frame_\(timestamp).png"
                finalImageURL = livewallsDir.appendingPathComponent(fileName)
                
                // Write file
                try pngData.write(to: finalImageURL)
                appLogger.info("✅ Static frame generated: \(finalImageURL.path)")
                
                // Verify that the file exists and has content
                let attributes = try FileManager.default.attributesOfItem(atPath: finalImageURL.path)
                if let fileSize = attributes[.size] as? NSNumber, fileSize.intValue > 0 {
                    appLogger.info("📄 File verified - Size: \(fileSize) bytes")
                } else {
                    throw NSError(domain: "WallpaperManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Generated file is empty"])
                }
                
            } catch {
                appLogger.error("❌ Error using Application Support (\(error.localizedDescription)). Using temporary directory...")
                
                // Fallback to system temporary directory
                let tempDir = FileManager.default.temporaryDirectory
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "livewalls_frame_\(timestamp).png"
                finalImageURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try pngData.write(to: finalImageURL)
                    appLogger.info("✅ Static frame generated (temporary): \(finalImageURL.path)")
                } catch {
                    appLogger.error("❌ Final error generating frame: \(error.localizedDescription)")
                    return nil
                }
            }
            
            return finalImageURL
            
        } catch {
            appLogger.error("❌ Error generating static frame: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Sets a static image as system wallpaper for all screens
    /// - Parameter imageURL: URL of the image to set as wallpaper
    /// - Returns: true if set correctly on at least one screen
    /// - Note: Fase 1 - Aplicación ÚNICA sin delays redundantes para optimizar rendimiento
    @discardableResult
    private func setSystemStaticWallpaper(imageURL: URL) -> Bool {
        var success = false
        
        // Verify that the file exists before trying to set it
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            appLogger.error("❌ Wallpaper file does not exist: \(imageURL.path)")
            return false
        }
        
        appLogger.info("🖼️ Setting static wallpaper (ONCE): \(imageURL.lastPathComponent)")
        
        // FASE 1: Aplicar UNA SOLA VEZ - eliminar delays redundantes
        // Apply to all screens
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(
                    imageURL,
                    for: screen,
                    options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                        .allowClipping: true
                    ]
                )
                success = true
                appLogger.info("✅ Static wallpaper set on screen: \(screen.localizedName)")
            } catch {
                appLogger.error("❌ Error setting static wallpaper on \(screen.localizedName): \(error.localizedDescription)")
            }
        }
        
        if success {
            currentStaticWallpaperURL = imageURL
            appLogger.info("📋 Current static wallpaper updated: \(imageURL.lastPathComponent)")
        }
        
        return success
    }
    
     /// Gets the next video in the queue (after current video)
     /// - Returns: Next video or nil if no videos available
    
    /// Asynchronously returns the next video in shuffle mode
    /// Selects random videos from those enabled for random play, avoiding recent selections
    /// Falls back to circular playlist when insufficient enabled videos
    func getNextVideoInShuffleMode() async -> VideoFile? {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        
        guard !enabledVideos.isEmpty else {
            appLogger.debug("📋 No videos enabled for shuffle mode")
            return nil
        }
        
        // If only 1 video, return it
        guard enabledVideos.count > 1 else {
            return enabledVideos.first
        }
        
        // If we have at least 6 enabled videos, use history to avoid repeating recent videos
        if enabledVideos.count >= 6 {
            // Filter out videos in shuffle history
            let availableVideos = enabledVideos.filter { video in !self.shuffleHistory.contains(video.id) }
            
            if let randomVideo = availableVideos.randomElement() {
                // Update shuffle history
                shuffleHistory.append(randomVideo.id)
                if shuffleHistory.count > shuffleHistoryMaxSize {
                    shuffleHistory.removeFirst()
                }
                appLogger.debug("🎲 Shuffled to: \(randomVideo.name) (history size: \(self.shuffleHistory.count))")
                return randomVideo
            } else {
                // All available videos are in history, clear history and try again
                appLogger.debug("🔄 Shuffle history full, clearing and retrying")
                shuffleHistory.removeAll()
                if let randomVideo = enabledVideos.randomElement() {
                    shuffleHistory.append(randomVideo.id)
                    appLogger.debug("🎲 Shuffled to: \(randomVideo.name) (history cleared)")
                    return randomVideo
                }
            }
        } else {
            // Fewer than 6 videos: use circular fallback to avoid immediate repeats
            // Get videos not in recent history (if any)
            let availableVideos = enabledVideos.filter { video in !self.shuffleHistory.contains(video.id) }
            if !availableVideos.isEmpty, let randomVideo = availableVideos.randomElement() {
                shuffleHistory.append(randomVideo.id)
                if shuffleHistory.count > shuffleHistoryMaxSize {
                    shuffleHistory.removeFirst()
                }
                appLogger.debug("🎲 Shuffled to: \(randomVideo.name) (small pool, history: \(self.shuffleHistory.count))")
                return randomVideo
            } else {
                // All in history, fall back to random
                if let randomVideo = enabledVideos.randomElement() {
                    shuffleHistory.append(randomVideo.id)
                    if shuffleHistory.count > shuffleHistoryMaxSize {
                        shuffleHistory.removeFirst()
                    }
                    appLogger.debug("🎲 Shuffled to: \(randomVideo.name) (fallback)")
                    return randomVideo
                }
            }
        }
        
        return nil
    }
    
     private func getNextVideoInQueue() -> VideoFile? {
         let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
         
         guard !enabledVideos.isEmpty, let currentVideo = currentVideo else {
             return nil
         }
         
         guard let currentIndex = enabledVideos.firstIndex(where: { $0.id == currentVideo.id }) else {
             return enabledVideos.first
         }
         
         let nextIndex = (currentIndex + 1) % enabledVideos.count
         return enabledVideos[nextIndex]
     }
     

    /// Schedules a file for cleanup after 30 seconds
    /// - Parameter fileURL: URL of the file to clean up
    func scheduleFileForCleanup(fileURL: URL) {
        appLogger.info("📅 Scheduling file for cleanup in 30s: \(fileURL.lastPathComponent)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            guard let self = self else { return }
            self.performBatchCleanup(fileURL: fileURL)
        }
    }
    
    /// Performs the actual cleanup of the scheduled file
    /// - Parameter fileURL: URL of the file to delete
    private func performBatchCleanup(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            appLogger.info("✓ File already deleted: \(fileURL.lastPathComponent)")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            appLogger.info("🧹 File deleted after 30s cleanup: \(fileURL.lastPathComponent)")
        } catch {
            appLogger.warning("⚠️ Could not delete file after cleanup: \(error.localizedDescription)")
        }
    }
    
    /// Establece un video como activo (wallpaper actual)
    /// - Parameter video: VideoFile a establecer como activo
    func setActiveVideo(_ video: VideoFile) async {
        appLogger.info("🎯 Setting active video: \(video.name)")
        
        // Update isActive state of all videos and force UI update
        var updatedVideos = videoFiles
        for i in 0..<updatedVideos.count {
            updatedVideos[i].isActive = (updatedVideos[i].id == video.id)
        }
        videoFiles = updatedVideos // This forces @Published update
        
        currentVideo = video
        saveCurrentVideo()
        
        // FASE 3: Invalidar cache de bookmarks al cambiar video
        Task {
            await bookmarkActor.invalidateCache()
        }
        
        appLogger.info("✅ Active video set: \(video.name)")
    }
    
    /// Removes a video from the wallpaper list
    /// - Parameter video: VideoFile to remove
    func removeVideo(_ video: VideoFile) {
        self.appLogger.info("🗑️ Removing video: \(video.name)")
        
        // If it's the current video, stop the wallpaper and select another
        let wasCurrentVideo = self.currentVideo?.id == video.id
        if wasCurrentVideo {
            self.stopWallpaper()
            self.currentVideo = nil
        }
        
        self.videoFiles.removeAll { $0.id == video.id }
        
        // Si era el video actual y quedan otros videos, seleccionar el primero
        if wasCurrentVideo && !self.videoFiles.isEmpty {
            let newCurrentVideo = self.videoFiles.first!
            self.currentVideo = newCurrentVideo
            Task {
                await self.persistenceActor.saveCurrentVideo(newCurrentVideo)
            }
            self.appLogger.info("🔄 Video actual eliminado, nuevo video seleccionado: \(newCurrentVideo.name)")
        }
        
        self.saveVideos()
    }
    
    // MARK: - Wallpaper Control

    /// Starts wallpaper playback safely
    func startWallpaperSafe() {
        guard let currentVideo = currentVideo else {
            appLogger.warning("⚠️ No video selected to start wallpaper")
            return
        }
        
        Task {
            do {
                try await wallpaperOperationActor.withExclusiveAccess {
                    await MainActor.run {
                        self.appLogger.info("▶️ Iniciando wallpaper: \(currentVideo.name)")
                    }

                    let resolvedURL = await self.resolveBookmark(for: currentVideo)
                    guard let accessibleURL = resolvedURL else {
                        await MainActor.run {
                            self.notificationManager.showError(message: "No se pudo acceder al archivo de video")
                        }
                        return
                    }

                     // Fase 1: Generar frame estático en background sin bloquear inicio del video
                     // HOTFIX: Usar DispatchQueue.main.async en lugar de await MainActor.run
                     // para evitar deadlocks causados por Task.detached anidado
                      Task.detached { [weak self] in
                          guard let self = self else { return }
                          if let staticImageURL = await self.generateStaticWallpaperFrame(for: accessibleURL) {
                              // Ejecutar en main thread sin await para evitar deadlock
                              DispatchQueue.main.async {
                                  _ = self.setSystemStaticWallpaper(imageURL: staticImageURL)
                                  self.appLogger.info("🖼️ Wallpaper estático establecido para Mission Control/Exposé")
                                  // FASE 1: Eliminado scheduleWallpaperApplicationForAllSpaces() que aplicaba 4 veces redundantes
                              }
                          } else {
                              DispatchQueue.main.async {
                                  self.appLogger.warning("⚠️ No se pudo generar wallpaper estático")
                              }
                          }
                      }

                     // Crear ventanas de forma asíncrona sin bloquear en frame estático
                     await self.createDesktopWindows(for: currentVideo, accessibleURL: accessibleURL)

                     await MainActor.run {
                         self.isPlayingWallpaper = true
                         self.startAutoChangeTimerIfNeeded()
                     }

                      // PHASE 6: Programar verificaciones de salud post-arranque con intervalos optimizados
                       // Intervals: 1.0s, 5.0s, 15.0s, 120.0s (120s para estado estable)
                       await self.scheduledHealthCheckManager.scheduleHealthChecks(
                           action: { [weak self] in
                               await MainActor.run { [weak self] in
                                   self?.ensurePlaying(reason: "post-start scheduled check")
                               }
                           },
                           intervals: [1.0, 5.0, 15.0, 120.0]
                       )

                      // Precargar el siguiente video para transiciones instantáneas
                      if let nextVideo = self.getNextVideoInQueue() {
                          if let nextURL = await self.resolveBookmark(for: nextVideo) {
                              await self.videoPreloader.preload(videoURL: nextURL)
                          }
                      }
                }
            } catch {
                // Task 2.1: lock acquisition failed (timeout or cancellation).
                // The lock guarantees bounded, non-latching behavior, but the
                // caller still has to honor that — log loudly so an ignored
                // start isn't silently dropped. Full error routing for every
                // trigger is the responsibility of task 2.2.
                await MainActor.run {
                    self.appLogger.error("⏱️ No se pudo iniciar wallpaper: lock no adquirido (\(error))")
                }
            }
         }
    }

    /// Stops wallpaper playback
    func stopWallpaper() {
        Task {
            do {
                try await wallpaperOperationActor.withExclusiveAccess {
                    await MainActor.run {
                    // Cancel pending static apply tasks
                    pendingStaticApplyWorkItem?.cancel()
                    pendingStaticApplyWorkItem = nil
                    isApplyingStaticWallpaper = false
                    
                    self.appLogger.info("⏹️ Deteniendo wallpaper")
                    self.stopAutoChangeTimer()
                    self.stopStaticFrameUpdateTimer()
                    // Task 1.5: stop the render-advance probes — playback no longer expected.
                    Task { await self.stopRenderAdvanceProbes() }
                    self.destroyAllDesktopWindows {
                        self.isPlayingWallpaper = false
                    }
                }
                }
            } catch {
                // Task 2.1: lock acquisition failed (timeout or cancellation).
                // The lock guarantees bounded, non-latching behavior, but the
                // caller still has to honor that — log loudly so an ignored
                // stop isn't silently dropped. Full error routing for every
                // trigger is the responsibility of task 2.2.
                await MainActor.run {
                    self.appLogger.error("⏱️ No se pudo detener wallpaper: lock no adquirido (\(error))")
                }
            }
        }
    }

    /// Alterna entre iniciar/detener el wallpaper
    func toggleWallpaper() {
        if isPlayingWallpaper {
            stopWallpaper()
        } else {
            startWallpaperSafe()
        }
    }
    
    // MARK: - Bookmark Resolution
    
    /// Resuelve un bookmark security-scoped para obtener acceso al archivo
    /// - Parameter video: VideoFile cuyo bookmark se debe resolver
    /// - Returns: URL accesible o nil si falla
    func resolveBookmark(for video: VideoFile) async -> URL? {
        guard let bookmarkData = video.bookmarkData else {
            appLogger.error("❌ No hay bookmark data para: \(video.name)")
            return nil
        }
        
        do {
            // Resolver bookmark de forma asíncrona usando BookmarkActor
            let url = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
            
            // Iniciar acceso security-scoped usando BookmarkActor (ref-count, single source of truth)
            let started = await bookmarkActor.startAccessingSecurityScopedResource(url: url)
            guard started else {
                appLogger.error("❌ No se pudo iniciar acceso security-scoped para: \(video.name)")
                return nil
            }

            // Task 2.6 / D6: no local mirror — BookmarkActor tracks the ref-count internally.
            appLogger.info("✅ Bookmark resuelto y acceso iniciado: \(video.name)")
            return url
            
        } catch {
            appLogger.error("❌ Error resolviendo bookmark para \(video.name): \(error)")
            return nil
        }
    }
    
    // MARK: - Desktop Windows Management
    
    /// Crea ventanas de video para todas las pantallas de forma asíncrona
    private func createDesktopWindows(for video: VideoFile, accessibleURL: URL) async {
        // Limpiar instancias previas
        if !desktopVideoInstances.isEmpty {
            appLogger.warning("⚠️ Limpiando ventanas previas antes de crear nuevas")
            for (window, _) in desktopVideoInstances {
                window.close()
            }
            desktopVideoInstances.removeAll()
        }
        
        let screens = NSScreen.screens
        
        // FASE 5: Métricas de rendimiento - timestamp inicio
        let startTime = Date()
        
        // Verificar si el filesystem está "caliente" por precarga
        let isWarmedUp = videoPreloader.isWarmedUp(for: accessibleURL)
        if isWarmedUp {
            appLogger.info("🔥 Filesystem precalentado - creación acelerada esperada")
        }
        
        // Usar WindowCreationCoordinator para crear ventanas de forma asíncrona
        let createdWindows = await windowCreationCoordinator.createWindowsAsync(
            screens: screens,
            videoFile: video,
            bookmarkActor: bookmarkActor,
            videoPreloader: videoPreloader
        )
        
        // FASE 5: Métricas de rendimiento - calcular tiempo transcurrido
        let elapsedTime = Date().timeIntervalSince(startTime)
        let warmStatus = isWarmedUp ? "WARM" : "COLD"
        appLogger.info("⏱️ Creación de ventanas completada en \(String(format: "%.2f", elapsedTime * 1000))ms [Cache: \(warmStatus)]")
        
        if createdWindows.isEmpty {
            appLogger.error("❌ No se pudo crear ninguna ventana de escritorio")
            notificationManager.showError(message: "No se pudo crear ventanas de fondo de pantalla")
            safeStopSecurityScopedAccess(for: accessibleURL)
        } else {
            // Convertir NSWindow a DesktopVideoWindowMejorada para mantener compatibilidad
            let desktopWindows = createdWindows.map { window in
                (window: window as! DesktopVideoWindowMejorada, accessibleURL: accessibleURL)
            }
            desktopVideoInstances = desktopWindows
            appLogger.info("✅ Creadas \(createdWindows.count) ventanas de escritorio de forma asíncrona")
        }

        // Task 1.5: (re)start the render-advance probes for the freshly created windows.
        await startRenderAdvanceProbes()
    }
    
    /// Destruye todas las ventanas de escritorio
    private func destroyAllDesktopWindows(completion: @escaping () -> Void) {
        guard !desktopVideoInstances.isEmpty else {
            completion()
            return
        }
        
        appLogger.info("🧹 Destruyendo \(self.desktopVideoInstances.count) ventanas de escritorio")
        
        let instancesToDestroy = desktopVideoInstances
        desktopVideoInstances.removeAll()
        
        // Usar DispatchGroup para esperar que todas las ventanas se cierren completamente
        let group = DispatchGroup()
        
        for (window, accessibleURL) in instancesToDestroy {
             group.enter()
             
              // Usar el nuevo método close con completion
              window.close { [weak self] in
                  // PHASE 3: Use context-aware delay (extended for Space changes)
                  // Liberar acceso security-scoped después de que la ventana esté completamente cerrada
                  let delay = self?.getResourceReleaseDelay(forSpaceChange: true) ?? 0.1
                 DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                     if let self {
                         Task { @MainActor in
                             self.safeStopSecurityScopedAccess(for: accessibleURL)
                         }
                     }
                     group.leave()
                 }
             }
        }
        
        // Ejecutar completion cuando todas las ventanas estén cerradas
        group.notify(queue: .main) {
            completion()
        }
    }
    
    // MARK: - Security-Scoped Resource Management

    /// Detiene el acceso security-scoped delegando al BookmarkActor (única fuente de verdad).
    /// - Task 2.6 / D6: eliminado el espejo local; BookmarkActor hace ref-count y double-stop safe.
    @MainActor
    private func safeStopSecurityScopedAccess(for url: URL) {
        // Delegamos al actor. Double-stop es no-op silencioso por contrato.
        Task {
            await self.bookmarkActor.stopAccessingSecurityScopedResource(url: url)
        }
        appLogger.debug("🔓 Stop security-scoped solicitado al BookmarkActor: \(url.path)")
    }
    
    // MARK: - New Robust Auto Change Timer
    
    private func startAutoChangeTimerIfNeeded() {
        guard self.isAutoChangeEnabled, self.autoChangeInterval > 0, self.videoFiles.count > 1 else { 
            appLogger.debug("💡 No se inicia timer: enabled=\(self.isAutoChangeEnabled), interval=\(self.autoChangeInterval), videos=\(self.videoFiles.count)")
            return 
        }
        
        // Validate that there are videos enabled for random playback
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        guard enabledVideos.count > 1 else {
            appLogger.warning("⚠️ No hay suficientes videos habilitados para rotación automática")
            return
        }
        
        // Validar estado del timer manager
        if !timerManager.validateState() {
            appLogger.warning("⚠️ Estado de timer inconsistente, recuperando...")
            timerManager.recoverFromInconsistentState()
        }
        
        // Iniciar timer con el nuevo sistema robusto
        timerManager.startTimer(interval: autoChangeInterval) { [weak self] in
            await self?.changeToNextVideo()
        }
        
        appLogger.info("⏰ Timer robusto de cambio automático iniciado: \(Int(self.autoChangeInterval))s")
    }
    
    private func stopAutoChangeTimer() {
        timerManager.stopTimer()
        appLogger.info("⏹️ Timer de cambio automático detenido")
    }
    
    /// Reinicia el timer de cambio automático (útil después de cambios manuales)
    private func restartAutoChangeTimerIfNeeded() {
        guard timerManager.isTimerActive else {
            appLogger.debug("💡 No se reinicia timer: no está activo")
            return
        }

        appLogger.info("🔄 Reiniciando timer después de cambio manual")
        startAutoChangeTimerIfNeeded()
    }

    // MARK: - Task 2.5: Full Fresh Rebuild (Design D3)

    /// Performs a full fresh rebuild (design D3): destroys old windows, resolves
    /// the bookmark, creates new windows with brand-new AVQueuePlayer + AVPlayerLooper
    /// + AVPlayerLayer per display, runs an orderFront→orderBack cycle for proper
    /// z-order/space settling, then probes for first-frame advance to confirm the
    /// pipeline is actually rendering.
    ///
    /// Differs from `startWallpaperSafe`/`changeToNextVideo` in that it does NOT
    /// reuse any existing playback state. Every AVQueuePlayer is allocated fresh,
    /// so a wedged AVPlayerLooper / stale AVPlayerItem cannot survive the rebuild.
    ///
    /// Caller responsibilities (must hold the wallpaper operation lock):
    /// - Caller has verified `currentVideo != nil`.
    /// - Caller will record `recoverOutcome` / `verifyResult` based on the return.
    ///
    /// - Parameter reason: Short identifier used for telemetry + logs.
    /// - Returns: `true` if first-frame probe confirmed advancing render, `false` otherwise.
    func performFreshRebuild(reason: String) async -> Bool {
        self.recoveryDecisionLogger.error("🛠️ performFreshRebuild start — reason: \(reason)")

        guard let video = self.currentVideo else {
            self.recoveryDecisionLogger.fault("❌ performFreshRebuild aborted — no current video.")
            return false
        }

        // 1) Teardown — destroy every old window and wait for close completion
        //    (the close callback chain releases security-scoped access).
        if !self.desktopVideoInstances.isEmpty {
            self.appLogger.info("🧹 Teardown de \(self.desktopVideoInstances.count) ventana(s) previa(s)")
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.destroyAllDesktopWindows { cont.resume() }
            }
            // give AVFoundation a moment to fully release the previous item/looper
            try? await Task.sleep(for: .milliseconds(300))
        }

        // 1.5) Task 2.6 / D6: drain security-scoped state to zero before the new
        //     resolveBookmark/start cycle. Idempotent; rebuild will re-acquire
        //     cleanly without depending on whatever state the previous rebuild left behind.
        await self.bookmarkActor.reconcile()

        // 2) Resolve bookmark — abort if it can't be resolved (file gone / perms revoked).
        guard let accessibleURL = await self.resolveBookmark(for: video) else {
            self.recoveryDecisionLogger.fault("❌ performFreshRebuild aborted — bookmark could not be resolved.")
            self.isPlayingWallpaper = false
            return false
        }

        // 3) Create brand-new windows. createDesktopWindows already invokes
        //    startRenderAdvanceProbes() at the end, which allocates one
        //    RenderAdvanceProbe per window — fresh AVQueuePlayer / looper / layer
        //    on the window side, fresh probe on the manager side.
        await self.createDesktopWindows(for: video, accessibleURL: accessibleURL)

        // 4) orderOut → orderFront → orderBack per window (design D3): the orderOut
        //    fully detaches the window from the window server's Space association
        //    before re-adding it, which is the part that unsticks a compositor that
        //    stayed wedged across a wake / display reconfiguration; orderFront then
        //    orderBack restores the desktop-level z-order behind the icon layer.
        for (window, _) in self.desktopVideoInstances {
            window.orderOut(nil)
            window.orderFront(nil)
            window.orderBack(nil)
        }

        // 5) Settle — 400ms gives AVFoundation time to begin the first frame
        //    render and stabilize the new layer ordering.
        try? await Task.sleep(for: .milliseconds(400))

        // 6) First-frame probe — sample currentTime twice with ~300ms apart and
        //    confirm forward advance OR a wrap (which is the AVPlayerLooper
        //    restart signature).
        let advancing = await self.verifyFirstFrameProbe()

        if advancing {
            self.recoveryDecisionLogger.error("✅ performFreshRebuild OK — first-frame probe confirmed advancing.")
        } else {
            self.recoveryDecisionLogger.fault("❌ performFreshRebuild failed — first-frame probe saw no advance across \(self.desktopVideoInstances.count) window(s).")
        }
        await self.recoveryTelemetry.recordVerifyResult(advancing: advancing, detail: "fresh-rebuild first-frame probe (\(reason))")
        return advancing
    }

    /// Samples each active window twice (≈300ms apart) and returns true if ANY
    /// window shows forward advance or wrap between the two samples. A single
    /// sample is not enough because playback may legitimately start from 0
    /// and the first sample may be a valid pre-advance baseline.
    private func verifyFirstFrameProbe() async -> Bool {
        let windows = self.desktopVideoInstances.map { $0.window }
        guard !windows.isEmpty else { return false }

        let sample1: [CMTime?] = await self.sampleCurrentTimes(on: windows)
        try? await Task.sleep(for: .milliseconds(300))
        let sample2: [CMTime?] = await self.sampleCurrentTimes(on: windows)

        for (t1, t2) in zip(sample1, sample2) {
            guard let s1 = t1, s1.isValid, s1.seconds > 0,
                  let s2 = t2, s2.isValid, s2.seconds > 0 else {
                continue
            }
            // Forward advance > 0.05s, or wrap (decrease > 0.05s).
            let delta = s2.seconds - s1.seconds
            if delta > 0.05 { return true }
            if delta < -0.05 { return true }
        }
        return false
    }

    /// Snapshot of each window's currentTime, hopped to main actor.
    /// Returns an array the same length as `windows` (nil where unavailable).
    private func sampleCurrentTimes(on windows: [DesktopVideoWindowMejorada]) async -> [CMTime?] {
        await MainActor.run {
            windows.map { $0.getCurrentTime() }
        }
    }

    /// Attempts a bounded, escalating recovery when health check reports unhealthy.
    /// Uses the render-advance probe as primary signal (design D2).
    /// - Parameter reason: Reason for the recovery attempt (for logging/telemetry).
    private func attemptBoundedRecovery(reason: String) async {
        // Guard against concurrent recovery loops (e.g., multiple ensurePlaying unhealthy triggers)
        guard !self.isRecoveryInProgress else {
            self.appLogger.debug("⏭️ Recovery ya en progreso — ignorando disparo concurrente")
            return
        }
        self.isRecoveryInProgress = true
        defer { self.isRecoveryInProgress = false }

        // Loop through attempts (replaces recursion)
        while self.recoveryAttempts < self.maxRecoveryAttempts {
            let backoff = self.recoveryBackoff[min(self.recoveryAttempts, self.recoveryBackoff.count - 1)]
            if backoff > .seconds(0) {
                self.appLogger.info("⏳ Recovery attempt \(self.recoveryAttempts + 1)/\(self.maxRecoveryAttempts): waiting \(backoff) before rebuild...")
                do {
                    try await Task.sleep(for: backoff)
                } catch {
                    self.appLogger.debug("⏭️ Recovery backoff cancelled")
                    return
                }
            }

            self.recoveryAttempts += 1
            self.appLogger.info("🛠️ Recovery attempt \(self.recoveryAttempts)/\(self.maxRecoveryAttempts) started. Reason: \(reason)")
            await self.recoveryTelemetry.recordRecoverAttempted(reason: reason)

            // Task 2.5: full fresh rebuild under the wallpaper operation lock
            // (avoids racing against user-driven next/previous, which is exactly
            // what the stale-AVPlayerLooper case needs).
            let freshOK: Bool
            do {
                freshOK = try await self.wallpaperOperationActor.withExclusiveAccess {
                    await self.performFreshRebuild(reason: reason)
                }
            } catch {
                self.appLogger.error("⏱️ Recovery attempt \(self.recoveryAttempts) no pudo adquirir lock: \(error)")
                freshOK = false
            }

            if freshOK {
                self.appLogger.info("✅ Recovery attempt \(self.recoveryAttempts) succeeded — first-frame probe OK")
                self.recoveryAttempts = 0
                self.recoveryExhausted = false
                await self.recoveryTelemetry.recordRecoverOutcome(success: true, reason: reason)
                return
            }

            self.appLogger.warning("⚠️ Recovery attempt \(self.recoveryAttempts) failed first-frame probe — next attempt")
            await self.recoveryTelemetry.recordRecoverOutcome(success: false, reason: "rebuild-unhealthy")
            // Loop continues for next attempt
        }

        // All attempts exhausted — log once (no spam on subsequent triggers)
        if !self.recoveryExhausted {
            self.recoveryExhausted = true
            self.recoveryDecisionLogger.fault("🛑 Recovery exhausted after \(self.maxRecoveryAttempts) attempts — stopping. Reason: \(reason)")
            await self.recoveryTelemetry.recordRecoverOutcome(success: false, reason: "max-attempts-exhausted")
        }
    }

    // MARK: - Static Frame Update Timer
    

    
    private func updateStaticFrameOnSpaceChange() async {
        guard let currentVideo = currentVideo, isPlayingWallpaper else { return }
        
        guard let accessibleURL = await resolveBookmark(for: currentVideo) else { return }
        
        // CRÍTICO: Reactivar reproducción de video en todas las ventanas
        // Al cambiar de Space, macOS puede pausar o congelar el video
        await MainActor.run {
            appLogger.info("🔄 Reactivando reproducción de video después de cambio de Space")
            for (window, _) in desktopVideoInstances {
                // Forzar reproducción
                window.forcePlay()
            }
        }
        
        // Obtener tiempo actual del video para el nuevo Space
        var currentVideoTime: CMTime? = nil
        if let firstInstance = desktopVideoInstances.first {
            currentVideoTime = firstInstance.window.getCurrentTime()
        }
        
         // Generar nuevo frame para el Space actual en background (no bloquear)
         // HOTFIX: Usar DispatchQueue.main.async en lugar de await MainActor.run
         // para evitar deadlocks
         Task.detached { [weak self] in
             guard let self = self else { return }
             
             if let staticImageURL = await self.generateStaticWallpaperFrame(for: accessibleURL, timeOffset: currentVideoTime) {
                 DispatchQueue.main.async {
                     _ = self.setSystemStaticWallpaper(imageURL: staticImageURL)
                     self.appLogger.info("🔄 Frame estático actualizado por cambio de Space - tiempo: \(currentVideoTime.map { "\(CMTimeGetSeconds($0))s" } ?? "inicial")")
                 }
                 
                 // Limpiar archivo temporal
                 try? FileManager.default.removeItem(at: staticImageURL)
             }
         }
        
        // Liberar acceso
        safeStopSecurityScopedAccess(for: accessibleURL)
    }
    
    // Eliminamos el timer periódico innecesario
    private func stopStaticFrameUpdateTimer() {
        staticFrameUpdateTimer?.invalidate()
        staticFrameUpdateTimer = nil
    }
    
    
    
     private func changeToNextVideo() async {
         let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
         
         guard enabledVideos.count > 1 else {
             appLogger.warning("⚠️ No hay suficientes wallpapers habilitados para cambio automático")
             return
         }
         
         // Use shuffle mode if enabled, otherwise use circular queue
         let nextVideo: VideoFile?
         if isShuffleMode {
             nextVideo = await getNextVideoInShuffleMode()
         } else {
             nextVideo = getNextVideoInQueue()
         }
         
         guard let nextVideo = nextVideo else {
             appLogger.warning("⚠️ No se pudo obtener el siguiente video")
             return
         }
         
         appLogger.info("🔄 Cambiando automáticamente a: \(nextVideo.name)")

         // Task 2.3: auto-change tick — if a guarded operation is already
         // running (e.g. a wake / health-check rebuild), skip this tick; the
         // timer fires again shortly. Only user-initiated changes get queued
         // (see nextWallpaper / previousWallpaper).
         guard !wallpaperOperationInFlight else {
             appLogger.debug("⏭️ Cambio automático omitido — operación en progreso")
             return
         }
         await applyGuardedWallpaperChange(to: nextVideo, restartTimerAfter: false)
     }

     /// Runs a wallpaper change under the exclusive lock (design D4) with a hard
     /// timeout and a guaranteed guard release on every exit path (design D5).
     /// When the guard clears, any user change queued while this one ran is
     /// drained.
     /// - Parameter restartTimerAfter: `true` for manual next/previous changes
     ///   (they reset the auto-change cadence); `false` for the auto-change tick.
     private func applyGuardedWallpaperChange(to video: VideoFile, restartTimerAfter: Bool) async {
         guard !wallpaperOperationInFlight else {
             appLogger.warning("⚠️ applyGuardedWallpaperChange invocado con operación en curso — ignorando")
             return
         }

         wallpaperOperationInFlight = true
         defer {
             wallpaperOperationInFlight = false
             // Drain at most one queued change per release; further requests
             // re-enqueue and drain on the next release (bounded).
             if let pending = pendingWallpaperChange {
                 pendingWallpaperChange = nil
                 appLogger.debug("📤 Drenando cambio de wallpaper encolado: \(String(describing: pending))")
                 Task { await self.drainPendingWallpaperChange(pending) }
             }
         }

         do {
             try await wallpaperOperationActor.withExclusiveAccess {
                 // Task 2.3: hard timeout inside the lock so a stalled operation
                 // cannot hold the mutex forever (design D5).
                 try await self.withOperationTimeout(Self.operationGuardTimeout) { @MainActor in
                     if self.isPlayingWallpaper {
                         await self.changeToNextVideoWithTransition(to: video)
                     } else {
                         await self.setActiveVideo(video)
                     }
                 }
             }
             if restartTimerAfter {
                 restartAutoChangeTimerIfNeeded()
             }
         } catch {
             appLogger.error("⏱️ Cambio de wallpaper falló (\(video.name)): \(error)")
         }
     }

     /// Re-runs a queued user change with fresh state. Delegating back to the
     /// public entry points keeps the shuffle/playlist resolution in one place.
     private func drainPendingWallpaperChange(_ pending: PendingWallpaperChange) async {
         switch pending {
         case .next:
             await nextWallpaper()
         case .previous:
             await previousWallpaper()
         }
     }

    /// Changes to the next video without crossfade (instant switch)
    private func changeToNextVideoWithTransition(to nextVideo: VideoFile) async {
        appLogger.info("🔄 Cambiando sin transición a: \(nextVideo.name)")
        
        // Ensure we have a current video selected
        guard currentVideo != nil else {
            appLogger.error("❌ No hay video actual")
            await setActiveVideo(nextVideo)
            return
        }
        
        // Get the next video URL
        guard let nextURL = await resolveBookmark(for: nextVideo) else {
            appLogger.error("❌ No se pudo obtener el URL del siguiente video")
            await setActiveVideo(nextVideo)
            return
        }

        let oldInstances = desktopVideoInstances
        
        appLogger.info("⏱️ Iniciando cambio directo de \(self.currentVideo?.name ?? "?") → \(nextVideo.name)")
        
        // Crear ventanas para el siguiente video (sin placeholders ni crossfade)
        let screens = NSScreen.screens
        let newWindows = await windowCreationCoordinator.createWindowsAsync(
            screens: screens,
            videoFile: nextVideo,
            bookmarkActor: bookmarkActor,
            startPaused: true,
            staticImageURL: nil  // Sin placeholder
        )
        let newVideoWindows = newWindows.compactMap { $0 as? DesktopVideoWindowMejorada }
        
        // Validate creation
        guard !newVideoWindows.isEmpty else {
            appLogger.error("❌ No se pudieron crear ventanas para transición - manteniendo wallpaper actual")
            await MainActor.run {
                self.safeStopSecurityScopedAccess(for: nextURL)
            }
            return
        }
        
        // Prepare new windows visible immediately
        await MainActor.run {
            newVideoWindows.forEach { window in
                window.delegate = self
                window.orderFront(nil)
                window.orderBack(nil)
                window.setOpacity(1.0)
            }
        }

        // Activate playback in new windows
        let successCount = await windowCreationCoordinator.activatePlaybackInWindows(newVideoWindows.map { $0 as NSWindow })

        // If nothing played, keep the previous wallpaper and clean up
        guard successCount > 0 else {
            appLogger.error("❌ Ninguna ventana pudo activar reproducción - conservando wallpaper previo")
            await MainActor.run {
                oldInstances.forEach {
                    $0.window.setOpacity(1.0)
                    $0.window.forcePlay()
                }
            }
            await teardownWindows(newVideoWindows.map { ($0, nextURL) }, reason: "fallo al activar nuevas ventanas")
            await MainActor.run {
                self.safeStopSecurityScopedAccess(for: nextURL)
            }
            return
        }
        
        appLogger.info("✅ Reproducción activada (\(successCount)/\(newVideoWindows.count) ventanas)")
        
        // Update active instances and selected video
        desktopVideoInstances = newVideoWindows.map { (window: $0, accessibleURL: nextURL) }
        await setActiveVideo(nextVideo)
        
        // Preload the next video in the queue for fast transitions
        Task {
            if let nextVideo = self.getNextVideoInQueue() {
                if let nextURL = await self.resolveBookmark(for: nextVideo) {
                    await self.videoPreloader.preload(videoURL: nextURL)
                }
            }
        }
        
        // Close previous windows once the new ones are playing
        await teardownWindows(oldInstances, reason: "transición completada")
        
        appLogger.info("✅ Cambio de video con transición completado: \(nextVideo.name)")
         
        // OPTIMIZATION: Generate static frame after playback confirmed, throttled
        scheduleStaticWallpaperApply(for: nextURL)
    }
    
    /// Closes windows and releases security-scoped access with a safety timeout
    private func teardownWindows(_ instances: [(DesktopVideoWindowMejorada, URL)], reason: String) async {
        guard !instances.isEmpty else { return }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            var hasResumed = false
            let resumeLock = NSLock()
            
            let resumeOnce = { (why: String) in
                resumeLock.lock()
                defer { resumeLock.unlock() }
                if !hasResumed {
                    hasResumed = true
                    self.appLogger.info("📍 Ventanas cerradas (\(reason)): \(why)")
                    continuation.resume()
                }
            }
            
            for (window, url) in instances {
                group.enter()
                window.close { [weak self] in
                    Task { [weak self] in
                        guard let self else {
                            group.leave()
                            return
                        }
                        // Release bookmark off-main to avoid stalling UI (ref-count decrement en BookmarkActor)
                        await self.bookmarkActor.stopAccessingSecurityScopedResource(url: url)
                        // Task 2.6 / D6: removed local mirror removal; BookmarkActor owns the state.
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                resumeOnce("Todas las ventanas notificaron cierre")
            }
            
            // Timeout de seguridad
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resumeOnce("Timeout de 3s cerrando ventanas")
            }
        }
    }
    
    // MARK: - Manual Next Wallpaper & Random Play Control
    
     /// Manually changes to the next wallpaper available for random playback
     /// Respects shuffle mode: uses random selection if shuffle is enabled, circular queue otherwise
     func nextWallpaper() async {
         let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
         
         // DEBUG: Log detallado de videos disponibles
         appLogger.info("🔍 DEBUG nextWallpaper() - Videos habilitados: \(enabledVideos.count), Shuffle: \(self.isShuffleMode)")
         appLogger.info("🔍 DEBUG - Current video: \(self.currentVideo?.name ?? "nil")")
         for (idx, video) in enabledVideos.enumerated() {
             appLogger.info("🔍 DEBUG - [\(idx)]: \(video.name) (id: \(video.id.uuidString.prefix(8))...)")
         }
         
         guard enabledVideos.count > 1 else {
             appLogger.warning("⚠️ No hay suficientes wallpapers habilitados para cambio manual (count: \(enabledVideos.count))")
             return
         }

         // Task 2.3: if a guarded operation is running, queue the intent and
         // return BEFORE touching shuffle history — the drain re-resolves the
         // target with fresh state once the guard clears (design D5).
         if wallpaperOperationInFlight {
             pendingWallpaperChange = .next
             appLogger.debug("📥 Siguiente wallpaper encolado — operación en progreso")
             return
         }

         // Determine next video based on shuffle mode
         var nextVideo: VideoFile?
         if self.isShuffleMode {
             // Use shuffle mode logic
             nextVideo = await getNextVideoInShuffleMode()
         } else {
             // Use circular queue logic
             if let currentVideo = self.currentVideo,
                let currentIndex = enabledVideos.firstIndex(where: { $0.id == currentVideo.id }) {
                 let nextIndex = (currentIndex + 1) % enabledVideos.count
                 nextVideo = enabledVideos[nextIndex]
             } else {
                 // Si el video actual no está en la lista habilitada, ir al primer habilitado
                 nextVideo = enabledVideos.first
                 appLogger.info("🔄 Cambiando manualmente al primer wallpaper habilitado: \(nextVideo?.name ?? "nil")")
             }
         }
         
         guard let nextVideo = nextVideo else {
             appLogger.warning("⚠️ No se pudo obtener el siguiente video para cambio manual")
             return
         }
         
         // Don't change to the same video
         if let currentVideo = self.currentVideo, nextVideo.id == currentVideo.id {
             appLogger.warning("⚠️ Siguiente video es el mismo que el actual - ignorando")
             return
         }

         appLogger.info("🔄 Cambiando manualmente (modo \(self.isShuffleMode ? "shuffle" : "playlist")) a: \(nextVideo.name)")

         await applyGuardedWallpaperChange(to: nextVideo, restartTimerAfter: true)
     }

    /// Manually changes to the previous wallpaper.
    /// - In playlist (non-shuffle) mode: mirrors `nextWallpaper()`'s circular queue, moving one index backward.
    /// - In shuffle mode: there is no fixed order to invert, so this walks backward through `shuffleHistory`
    ///   (the real, chronological record of the last `shuffleHistoryMaxSize` videos played), rather than
    ///   picking another random video. Once fewer than 2 entries remain in that history, there is no real
    ///   "previous" left to go back to and this becomes a no-op (see `canGoToPreviousWallpaper`).
    func previousWallpaper() async {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }

        appLogger.info("🔍 DEBUG previousWallpaper() - Videos habilitados: \(enabledVideos.count), Shuffle: \(self.isShuffleMode)")

        guard enabledVideos.count > 1 else {
            appLogger.warning("⚠️ No hay suficientes wallpapers habilitados para retroceder")
            return
        }

        // Task 2.3: queue the intent and return BEFORE mutating shuffleHistory —
        // the drain re-resolves with fresh state once the guard clears (design D5).
        if wallpaperOperationInFlight {
            pendingWallpaperChange = .previous
            appLogger.debug("📥 Wallpaper anterior encolado — operación en progreso")
            return
        }

        var previousVideo: VideoFile?
        if self.isShuffleMode {
            // shuffleHistory's last entry tracks the currently-playing video (see getNextVideoInShuffleMode).
            // Drop it and use the new last entry as the real previous video, instead of sampling a fresh
            // random pick — that would not be a "previous" in any meaningful sense.
            guard shuffleHistory.count >= 2 else {
                appLogger.warning("⚠️ No hay historial suficiente para retroceder en modo aleatorio")
                return
            }
            shuffleHistory.removeLast()
            if let previousID = shuffleHistory.last {
                previousVideo = enabledVideos.first(where: { $0.id == previousID })
            }
        } else {
            if let currentVideo = self.currentVideo,
               let currentIndex = enabledVideos.firstIndex(where: { $0.id == currentVideo.id }) {
                let previousIndex = (currentIndex - 1 + enabledVideos.count) % enabledVideos.count
                previousVideo = enabledVideos[previousIndex]
            } else {
                previousVideo = enabledVideos.last
            }
        }

        guard let previousVideo = previousVideo else {
            appLogger.warning("⚠️ No se pudo obtener el video anterior")
            return
        }

        if let currentVideo = self.currentVideo, previousVideo.id == currentVideo.id {
            appLogger.warning("⚠️ Video anterior es el mismo que el actual - ignorando")
            return
        }

        appLogger.info("🔄 Retrocediendo manualmente (modo \(self.isShuffleMode ? "shuffle" : "playlist")) a: \(previousVideo.name)")

        await applyGuardedWallpaperChange(to: previousVideo, restartTimerAfter: true)
    }

    /// Comprueba si el botón "Siguiente Wallpaper" debe estar habilitado
    var canGoToNextWallpaper: Bool {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        return isAutoChangeEnabled && enabledVideos.count > 1
    }

    /// Comprueba si el botón "Wallpaper Anterior" debe estar habilitado.
    /// En modo shuffle, además requiere al menos 2 entradas en `shuffleHistory` (un video anterior real
    /// al que volver); en modo lista, cualquier lista con más de un video habilitado permite retroceder.
    var canGoToPreviousWallpaper: Bool {
        let enabledVideos = videoFiles.filter { $0.isEnabledForRandomPlay }
        guard isAutoChangeEnabled && enabledVideos.count > 1 else { return false }
        if isShuffleMode {
            return shuffleHistory.count >= 2
        }
        return true
    }
    
    /// Toggles the enabled state for random playback of a specific video
    func toggleVideoRandomPlayEnabled(_ video: VideoFile) {
        guard let index = videoFiles.firstIndex(where: { $0.id == video.id }) else { return }
        
        videoFiles[index].isEnabledForRandomPlay.toggle()
        let newState = videoFiles[index].isEnabledForRandomPlay
        
        appLogger.info("🎯 Video '\(video.name)' \(newState ? "enabled" : "disabled") for random playback")
        
        // Guardar cambios
        saveVideos()
        
        // Si se deshabilitó el video actual y está en modo auto-change, cambiar al siguiente habilitado
        if !newState && video.id == currentVideo?.id && isAutoChangeEnabled && isPlayingWallpaper {
            Task {
                await self.nextWallpaper()
            }
        }
    }
    
    /// Reorders videos in the playlist by moving a video from source index to destination index
    /// Only works in playlist mode (not shuffle mode)
    /// PHASE 4: Drag & Drop reordering
    func reorderVideos(from source: Int, to destination: Int) {
        print("🔄 reorderVideos called: from \(source) to \(destination)")
        print("📋 Before reorder: \(videoFiles.map { $0.name })")
        
        // Validate indices
        guard source != destination,
              source >= 0, source < videoFiles.count,
              destination >= 0, destination < videoFiles.count else {
            print("❌ Reorder validation failed: source=\(source), dest=\(destination), count=\(videoFiles.count)")
            return
        }
        
        // Move the video from source to destination
        let movedVideo = videoFiles[source]
        videoFiles.remove(at: source)
        videoFiles.insert(movedVideo, at: destination)
        
        print("📋 After reorder: \(videoFiles.map { $0.name })")
        
        // Force objectWillChange to trigger UI update
        objectWillChange.send()
        
        // Update currentVideo reference if affected by reordering
        if currentVideo?.id == movedVideo.id {
            // Current video was moved, it's now at the destination index
            currentVideo = videoFiles[destination]
        }
        
        appLogger.info("🔄 Reordered video '\(movedVideo.name)' from index \(source) to \(destination)")
        
        // Persist the new order
        saveVideos()
    }
    
    // MARK: - Persistence
    
    /// Guarda la lista de videos de forma asíncrona usando PersistenceActor
    func saveVideos() {
         let videos = videoFiles
         Task.detached { [weak self] in
             guard let self else { return }
             do {
                 try await self.persistenceActor.saveVideos(videos)
             } catch {
                 // HOTFIX: Usar DispatchQueue.main.async en lugar de await MainActor.run
                 // para evitar deadlocks en Task.detached
                 DispatchQueue.main.async {
                     self.appLogger.error("❌ Error al guardar videos: \(error.localizedDescription)")
                 }
             }
         }
    }
    
    /// Carga todos los datos de persistencia en background durante init
    private func loadDataInBackground() async {
        do {
            // Cargar videos de forma asíncrona
            let videos = try await persistenceActor.loadVideos()
            
            // Cargar video actual de forma asíncrona
            let currentVid = await persistenceActor.loadCurrentVideo()
            
            // Cargar configuración de auto-change de forma asíncrona
            let autoChangeSettings = await persistenceActor.loadAutoChangeSettings()
            
            // Actualizar estado en main thread
            await MainActor.run {
                self.videoFiles = videos
                self.currentVideo = currentVid
                self.isAutoChangeEnabled = autoChangeSettings.isEnabled
                self.autoChangeInterval = autoChangeSettings.interval
                
                self.appLogger.info("📂 Datos cargados en background: \(videos.count) videos, autoChange=\(autoChangeSettings.isEnabled)")
                self.syncActiveVideoState()
            }
        } catch {
            await MainActor.run {
                self.appLogger.error("❌ Error al cargar datos en background: \(error.localizedDescription)")
            }
        }
    }
    
    private func saveCurrentVideo() {
        let video = currentVideo
        Task.detached { [weak self] in
            guard let self else { return }
            await self.persistenceActor.saveCurrentVideo(video)
        }
    }
    

    
    /// Sincroniza el estado isActive de todos los videos con el currentVideo
    private func syncActiveVideoState() {
        var updatedVideos = videoFiles
        
        guard let currentVideo = currentVideo else {
            // Si no hay video actual, desmarcar todos como activos
            for i in 0..<updatedVideos.count {
                updatedVideos[i].isActive = false
            }
            self.videoFiles = updatedVideos
            return
        }
        
        // Marcar solo el video actual como activo
        for i in 0..<updatedVideos.count {
            updatedVideos[i].isActive = (updatedVideos[i].id == currentVideo.id)
        }
        self.videoFiles = updatedVideos
        
        appLogger.info("🔄 Estado sincronizado - Video activo: \(currentVideo.name)")
    }
    

    /// Loads transition settings from UserDefaults
    private func loadTransitionSettings() {
        // Transitions disabled: enforce instant switch
        isTransitionEnabled = false
        transitionDuration = 0.0
        transitionType = .crossfade
    }
    
    /// Guarda configuración de cambio automático usando PersistenceActor
    func saveAutoChangeSettings() {
        let isEnabled = isAutoChangeEnabled
        let interval = autoChangeInterval
        
        Task.detached { [weak self] in
            guard let self else { return }
            await self.persistenceActor.saveAutoChangeSettings(isEnabled: isEnabled, interval: interval)
        }
        
        appLogger.info("💾 Saving configuration: enabled=\(self.isAutoChangeEnabled), interval=\(Int(self.autoChangeInterval))s")
        
        if isAutoChangeEnabled && isPlayingWallpaper {
            // Solo iniciar timer si el wallpaper está reproduciéndose
            startAutoChangeTimerIfNeeded()
        } else {
            // Detener timer si se deshabilitó o no hay wallpaper activo
            stopAutoChangeTimer()
        }
        
        // Realizar health check después de cambios
        Task {
            await performTimerHealthCheck()
        }
    }
    
    /// Saves transition configuration (transitions disabled)
    func saveTransitionSettings() {
        isTransitionEnabled = false
        transitionDuration = 0.0
    }
    
    /// Sets whether transitions are enabled (no-op; transitions disabled)
    func setTransitionEnabled(_ enabled: Bool) {
        saveTransitionSettings()
    }
    
    /// Sets the transition duration (no-op; transitions disabled)
    func setTransitionDuration(_ duration: TimeInterval) {
        saveTransitionSettings()
    }
    
    /// Sets the transition type (no-op; transitions disabled)
    func setTransitionType(_ type: TransitionManager.TransitionType) {
        saveTransitionSettings()
    }
    
    /// Gets the current transition settings (transitions disabled)
    func getTransitionSettings() -> (isEnabled: Bool, duration: TimeInterval, type: TransitionManager.TransitionType) {
        return (false, 0.0, .crossfade)
    }
    
    /// Función para compatibilidad con ContentView - llama a stopWallpaper()
    func stopWallpaperSafe() {
        stopWallpaper()
    }

    /// Re-applies the "MuteVideo" preference to every currently active
    /// desktop wallpaper window, so toggling mute from the main window's
    /// transport pill takes effect immediately on whatever is already
    /// playing, instead of only on the next video/window setup.
    func applyMuteSettingToActiveWindows() {
        for instance in desktopVideoInstances {
            instance.window.updateMuteSetting()
        }
    }
    
    /// Función para pruebas: establecer wallpaper estático manualmente
    func testStaticWallpaper() async {
        guard let currentVideo = currentVideo else {
            appLogger.warning("⚠️ No hay video seleccionado para prueba estática")
            return
        }
        
        guard let accessibleURL = await resolveBookmark(for: currentVideo) else {
            appLogger.error("❌ No se pudo acceder al video para prueba estática")
            return
        }
        
        appLogger.info("🧪 INICIANDO PRUEBA DE WALLPAPER ESTÁTICO")
        
        if let staticImageURL = await generateStaticWallpaperFrame(for: accessibleURL) {
            appLogger.info("✅ Frame estático generado: \(staticImageURL.path)")
            
            let success = setSystemStaticWallpaper(imageURL: staticImageURL)
            if success {
                appLogger.info("✅ PRUEBA EXITOSA: Wallpaper estático establecido")
                // FASE 1: Eliminado scheduleWallpaperApplicationForAllSpaces() que aplicaba 4 veces redundantes
            } else {
                appLogger.error("❌ PRUEBA FALLIDA: No se pudo establecer wallpaper estático")
            }
        } else {
            appLogger.error("❌ PRUEBA FALLIDA: No se pudo generar frame estático")
        }
        
        // Liberar acceso al video
        safeStopSecurityScopedAccess(for: accessibleURL)
    }
    
    /// FASE 1: Eliminado scheduleWallpaperApplicationForAllSpaces() que aplicaba 4 veces redundantes
    /// NSWorkspace.shared.setDesktopImageURL ya aplica a todos los Spaces disponibles
    
    /// Establece un video como wallpaper actual y lo inicia inmediatamente
    /// - Parameter video: VideoFile a establecer como wallpaper fijo
    func setAsCurrentWallpaper(video: VideoFile) {
        appLogger.info("🌟 Fijando video como wallpaper: \(video.name)")
        
        // Detener cambio automático si está activo
        if isAutoChangeEnabled {
            isAutoChangeEnabled = false
            saveAutoChangeSettings()
            appLogger.info("⏱️ Cambio automático desactivado por fijación manual")
        }
        
        // Establecer como video actual de forma síncrona para uso inmediato
        DispatchQueue.main.async {
            // Actualizar el estado isActive de todos los videos y forzar actualización de UI
            var updatedVideos = self.videoFiles
            for i in 0..<updatedVideos.count {
                updatedVideos[i].isActive = (updatedVideos[i].id == video.id)
            }
            self.videoFiles = updatedVideos // Esto fuerza la actualización de @Published
            
            self.currentVideo = video
            self.saveCurrentVideo()
            
            self.appLogger.info("✅ Video activo establecido: \(video.name)")
            
            // Iniciar wallpaper DESPUÉS de que currentVideo se haya actualizado
            self.startWallpaperSafe()
        }
    }
    
    // MARK: - System Notifications
    
    private func setupScreenChangeNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.appLogger.info("🖥️ Configuración de pantalla cambió")
                if self.isPlayingWallpaper {
                    self.startWallpaperSafe() // Recreate windows for new configuration
                }
            }
        }
    }

    private func setupWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Detectar cambios de Space para reaplicar wallpaper estático
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    /// Observa la activación de la app para asegurar reproducción tras el login
    private func setupAppActivationNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appLogger.info("🟢 App didBecomeActive - verificando reproducción")
                self.ensurePlaying(reason: "didBecomeActive")
            }
        }
    }
    
    /// Configura la detección de aplicaciones fullscreen
    private func setupFullscreenDetection() {
        appLogger.info("🔍 Configurando detección de fullscreen")
        
        // Configurar callbacks del detector
        fullscreenDetector.onFullscreenEntered = { [weak self] appName in
            Task { @MainActor [weak self] in
                await self?.handleFullscreenEntered(appName: appName)
            }
        }
        
        fullscreenDetector.onFullscreenExited = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleFullscreenExited()
            }
        }
        
        appLogger.info("✅ Detección de fullscreen configurada")
    }
    
    /// Maneja cuando una aplicación entra en fullscreen
    private func handleFullscreenEntered(appName: String) async {
        appLogger.info("🎮 Aplicación en fullscreen detectada: \(appName)")
        
        guard isAutoChangeEnabled && isPlayingWallpaper else {
            appLogger.debug("💡 No active timer, no need to pause")
            return
        }
        
        // Pausar el timer de cambio automático
        if timerManager.isTimerActive && !timerManager.isPaused {
            appLogger.info("⏸️ Pausando timer de wallpaper por fullscreen")
            timerManager.pauseTimer()
            isWallpaperPausedForFullscreen = true
            
            // Optional: Also pause video players to save resources
            await pauseVideoPlayersForFullscreen()
        }
    }
    
    /// Maneja cuando se sale de fullscreen
    private func handleFullscreenExited() async {
        appLogger.info("🏠 Salida de fullscreen detectada")
        
        guard isWallpaperPausedForFullscreen else {
            appLogger.debug("💡 Wallpaper no estaba pausado por fullscreen")
            return
        }
        
        // Resumir el timer de cambio automático
        if timerManager.isTimerActive && timerManager.isPaused {
            appLogger.info("▶️ Resumiendo timer de wallpaper después de fullscreen")
            timerManager.resumeTimer()
            isWallpaperPausedForFullscreen = false
            
            // Resumir reproductores de video
            await resumeVideoPlayersFromFullscreen()
        }
    }
    
    /// Pauses video players during fullscreen to save resources
    private func pauseVideoPlayersForFullscreen() async {
        appLogger.info("⏸️ Pausing video players for fullscreen")

        // Task 1.5: playback paused for fullscreen — stop the probes so a paused
        // (legitimately non-advancing) player is not misread as a stall.
        await stopRenderAdvanceProbes()

        for (window, _) in desktopVideoInstances {
            if let playerLayer = window.currentPlayerLayer {
                playerLayer.player?.pause()
            }
        }
    }
    
    /// Resumes video players after fullscreen
    private func resumeVideoPlayersFromFullscreen() async {
        appLogger.info("▶️ Resuming video players after fullscreen")

        for (window, _) in desktopVideoInstances {
            if let playerLayer = window.currentPlayerLayer {
                playerLayer.player?.play()
            }
        }

        // Task 1.5: playback resumed — restart the probes.
        await startRenderAdvanceProbes()
    }

    // MARK: - Task 1.5: Render-advance probe lifecycle + observable signal

    /// Starts one `RenderAdvanceProbe` per active desktop window plus a poll loop that
    /// publishes the aggregate verdict to `renderAdvanceState` and feeds each transition
    /// to the durable telemetry store. Idempotent: a running probe set is torn down first.
    /// Only runs while playback is expected (called on window creation / fullscreen exit).
    func startRenderAdvanceProbes() async {
        await stopRenderAdvanceProbes()

        let windows = desktopVideoInstances.map { $0.window }
        guard !windows.isEmpty else { return }

        renderAdvanceProbes = await RenderAdvanceProbe.startProbes(for: windows)
        appLogger.debug("🔬 RenderAdvanceProbes iniciados para \(windows.count) ventana(s)")

        renderAdvancePollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2.5))
                } catch {
                    break
                }
                guard let self else { break }
                let probes = self.renderAdvanceProbes
                guard !probes.isEmpty else { break }

                let aggregate: RenderAdvanceVerdict
                if await RenderAdvanceProbe.anyStalled(probes) {
                    aggregate = .stalled
                } else if await RenderAdvanceProbe.allAdvancing(probes) {
                    aggregate = .advancing
                } else {
                    aggregate = .unknown
                }

                guard self.renderAdvanceState != aggregate else { continue }
                self.renderAdvanceState = aggregate

                let verdictString: String
                switch aggregate {
                case .idle: verdictString = "idle"
                case .advancing: verdictString = "advancing"
                case .stalled: verdictString = "stalled"
                case .unknown: verdictString = "unknown"
                }
                self.recoveryDecisionLogger.error("🔬 Render-advance aggregate → \(verdictString)")
                await self.recoveryTelemetry.recordProbeState(verdictString)
            }
        }
    }

    /// Stops and clears all render-advance probes and the poll loop; resets the
    /// observable signal to `.idle`. Safe to call when nothing is running.
    func stopRenderAdvanceProbes() async {
        renderAdvancePollTask?.cancel()
        renderAdvancePollTask = nil
        if !renderAdvanceProbes.isEmpty {
            await RenderAdvanceProbe.stopProbes(renderAdvanceProbes)
            renderAdvanceProbes = []
        }
        if renderAdvanceState != .idle {
            renderAdvanceState = .idle
        }
    }

    @objc private func willSleep(notification: NSNotification) {
        // Task 1.2: record suspend-observed marker at the top so it fires even if later logic bails
        Task { [recoveryTelemetry] in await recoveryTelemetry.recordSuspend() }
        appLogger.info("💤 El sistema va a suspenderse. Deteniendo temporalmente el wallpaper.")
        // No es necesario detenerlo explícitamente, el sistema lo pausa.
        // Si se detiene aquí, isPlayingWallpaper sería falso al despertar.
    }

    @objc private func didWake(notification: NSNotification) {
        // Task 1.2: record wake-observed marker at the top so it fires even if later logic bails
        Task { [recoveryTelemetry] in await recoveryTelemetry.recordWake() }
        appLogger.info("🌅 El sistema se ha despertado.")
        // Si el wallpaper estaba activo antes de suspender, lo reiniciamos.
        if isPlayingWallpaper {
            appLogger.info("🚀 Reiniciando wallpaper después de despertar.")
            // Task 1.3: retained-level (eviction-resistant) recovery-decision log
            recoveryDecisionLogger.error("🛠️ Recovery decision: wake-triggered rebuild (wallpaper was active before suspend).")
            // Restart wallpaper with clean state via exclusive lock
            Task {
                do {
                    try await wallpaperOperationActor.withExclusiveAccess {
                        // Wait for system to stabilize
                        try? await Task.sleep(for: .milliseconds(500))

                        // Task 2.5: full fresh rebuild with first-frame probe
                        let firstOK = await self.performFreshRebuild(reason: "wake")

                        if !firstOK {
                            // Single retry if the first-frame probe did not confirm
                            // advance — the wake event may have arrived before the
                            // display subsystem finished waking up.
                            self.appLogger.warning("⚠️ Wake rebuild first-frame probe failed — single retry")
                            try? await Task.sleep(for: .milliseconds(800))
                            let secondOK = await self.performFreshRebuild(reason: "wake-retry")
                            guard secondOK else {
                                await MainActor.run {
                                    self.appLogger.error("❌ Wake rebuild no logró reproducir tras reintento")
                                    self.recoveryDecisionLogger.fault("❌ Recovery outcome: wake-triggered rebuild failed (first-frame probe failed twice).")
                                    self.isPlayingWallpaper = false
                                }
                                return
                            }
                        }

                        await MainActor.run {
                            self.isPlayingWallpaper = true
                            self.startAutoChangeTimerIfNeeded()
                            self.recoveryAttempts = 0  // Reset recovery counter on successful wake rebuild
                            self.recoveryExhausted = false  // Reset exhausted flag on successful wake rebuild
                            self.appLogger.info("✅ Wallpaper reiniciado exitosamente después de despertar")
                            // Task 1.3: retained-level recovery-outcome log (success path)
                            self.recoveryDecisionLogger.error("✅ Recovery outcome: wake-triggered rebuild succeeded (first-frame probe OK).")
                        }
                    }
                } catch {
                    // Task 2.1/2.2: lock acquisition failed (timeout or cancellation).
                    await MainActor.run {
                        self.appLogger.error("⏱️ No se pudo reiniciar wallpaper tras wake: lock no adquirido (\(error))")
                        self.recoveryDecisionLogger.fault("❌ Recovery outcome: wake-triggered rebuild failed (lock acquisition failed: \(error)).")
                    }
                }
            }
        }
    }
    
    @objc private func activeSpaceDidChange(notification: NSNotification) {
        appLogger.info("🔄 Space activo cambió - usando throttle")
        
        // FASE 2: Throttle para consolidar notificaciones rápidas
        // Reducir de 12 reactivaciones (4 llamadas × 3 notificaciones) a 1-2 máximo
        Task {
            await throttleManager.throttle(key: "spaceChange", interval: 0.5) { @MainActor in
                self.appLogger.info("🔄 Ejecutando reactivación tras throttle")
                
                // PHASE 3: Validate bookmark freshness before Space operations
                if let videoFile = self.currentVideo, let bookmarkData = videoFile.bookmarkData {
                    let isStale = await self.bookmarkActor.isBookmarkStale(for: bookmarkData)
                    if isStale {
                        self.appLogger.warning("⚠️ Bookmark stale before Space change, refreshing...")
                        do {
                            let freshURL = try await self.bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
                            self.appLogger.info("✅ Bookmark refreshed: \(freshURL.lastPathComponent)")
                            // Cache is now fresh with new timestamp
                        } catch {
                            self.appLogger.error("❌ Failed to refresh stale bookmark: \(error.localizedDescription)")
                        }
                    }
                }
                
                // PHASE 3: Try window reuse first, fallback to recreation
                if self.areCurrentWindowsHealthy() {
                    self.appLogger.info("✅ Windows healthy - updating for Space without recreation")
                    await self.updateWindowVisibilityForSpaces()
                } else {
                    self.appLogger.info("⚠️ Windows unhealthy - triggering recreation")
                    // Primera reactivación inmediata (ensurePlaying internally routes rebuild through lock)
                    self.ensurePlaying(reason: "Space change - throttled")

                    // Un único retry tras 200ms para garantizar reproducción
                    try? await Task.sleep(for: .milliseconds(200))
                    self.ensurePlaying(reason: "Space change - retry")

                    // Actualizar frame estático en background (no bloquear)
                    await self.updateStaticFrameOnSpaceChange()
                }
            }
        }
    }
    
    // MARK: - Phase 3: Window Reuse and Visibility Management
    
    /// Updates window visibility for space changes without recreating windows
    /// This method improves Space change performance by only updating visibility
    /// instead of doing a full window recreation
    @MainActor
    func updateWindowVisibilityForSpaces() async {
        appLogger.info("🔄 Updating window visibility for Space change (no recreation)")
        
        // Collect current window instances safely
        var windowsToUpdate: [(window: DesktopVideoWindowMejorada, accessibleURL: URL)] = []
        wallpaperOperationQueue.sync {
            windowsToUpdate = desktopVideoInstances
        }
        
        // Update each window's visibility without recreation
        for (window, _) in windowsToUpdate {
            // Update window for Space on main thread
            await MainActor.run {
                window.updateForSpace()
            }
        }
        
        appLogger.info("✅ Window visibility updated for all \(windowsToUpdate.count) window(s)")
    }
    
    // PHASE 3: Check if all current windows are healthy
    /// Validates that all currently running windows are in a healthy state
    /// This method checks if windows can be reused for Space changes without recreation
    /// - Returns: true if all windows are healthy and ready for reuse, false if recreation is needed
    @MainActor
    private func areCurrentWindowsHealthy() -> Bool {
        var windows: [DesktopVideoWindowMejorada] = []
        wallpaperOperationQueue.sync {
            windows = desktopVideoInstances.map { $0.window }
        }
        
        if windows.isEmpty {
            appLogger.info("⚠️ No windows exist")
            return false
        }
        
        let allHealthy = windows.allSatisfy { $0.isHealthy() }
        if allHealthy {
            appLogger.info("✅ All windows healthy")
        } else {
            appLogger.info("⚠️ Some windows unhealthy")
        }
        return allHealthy
    }
    
    // PHASE 3: Helper method to get appropriate resource release delay
    /// Returns the appropriate resource release delay based on context
    /// - Parameter isSpaceChange: true if delay is for Space change operation
    /// - Returns: The delay interval (5.0s for Space changes, 2.5s for transitions)
    @MainActor
    private func getResourceReleaseDelay(forSpaceChange isSpaceChange: Bool) -> TimeInterval {
        // Space changes need longer delay to allow:
        // - Throttle settling (0.5s)
        // - Window operations completion (0.5-1.0s)
        // - AVFoundation resource cleanup (1.0-2.0s)
        // - FigFilePlayer error prevention (1.0-2.0s grace period)
        return isSpaceChange ? resourceReleaseDelayForSpaceChange : resourceReleaseDelay
    }
    
    private func setupTerminationHandling() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cleanupAllResources()
            }
        }
    }
    
    // MARK: - Background Color Window Management
    
    /// Create background color windows for all screens
    @MainActor
    private func createBackgroundColorWindows() {
        self.appLogger.info("🎨 Creating background color windows for transition")
        
        // Clean up any existing background windows first
        self.cleanupBackgroundColorWindows()
        
        let screens = NSScreen.screens
        for screen in screens {
            let colorWindow = BackgroundColorWindow(screen: screen)
            // Ordenar al frente primero para asegurar visibilidad
            colorWindow.makeKeyAndOrderFront(nil)
            // Luego ordenar atrás pero manteniendo visible
            colorWindow.orderBack(nil)
            // Forzar renderizado inmediato
            colorWindow.display()
            colorWindow.displayIfNeeded()
            self.backgroundColorWindows.append(colorWindow)
        }
        
        self.appLogger.info("✅ Created \(self.backgroundColorWindows.count) background color windows with forced display")
    }
    
    /// Clean up background color windows
    @MainActor
    private func cleanupBackgroundColorWindows() {
        guard !self.backgroundColorWindows.isEmpty else { return }
        
        self.appLogger.info("🧹 Cleaning up \(self.backgroundColorWindows.count) background color windows")
        
        for window in self.backgroundColorWindows {
            if let colorWindow = window as? BackgroundColorWindow {
                colorWindow.cleanup()
            } else {
                window.orderOut(self)
                window.close()
            }
        }
        self.backgroundColorWindows.removeAll()
    }
    
    @MainActor
    private func cleanupAllResources() {
        appLogger.info("🧹 Cleaning up all resources")
        stopAutoChangeTimer()
        cleanupBackgroundColorWindows()

        // Close all windows and release resources
        for (window, accessibleURL) in desktopVideoInstances {
            window.close()
            safeStopSecurityScopedAccess(for: accessibleURL)
        }
        desktopVideoInstances.removeAll()
        // Task 2.6 / D6: drain remaining security-scoped accesses via the actor.
        Task { [bookmarkActor] in await bookmarkActor.stopAllSecurityScopedAccess() }
    }
}

// MARK: - NSWindowDelegate

extension WallpaperManager {
    func windowWillClose(_ notification: Notification) {
        // Manejar cierre de ventanas si es necesario
        if let window = notification.object as? NSWindow {
            appLogger.debug("🪟 Ventana cerrándose: \(window)")
        }
    }
}

// MARK: - Debug Functions

extension WallpaperManager {
    
    /// Realiza un health check completo del timer
    func performTimerHealthCheck() async {
        appLogger.info("🏥 Realizando health check del timer")
        
        let isHealthy = timerManager.performHealthCheck()
        let fullscreenState = fullscreenDetector.getCurrentState()
        
        if !isHealthy {
            appLogger.error("❌ Timer health check falló")
            logSystemState()
        }
        
        appLogger.info("📊 Estado actual: Timer saludable=\(isHealthy), Fullscreen=\(fullscreenState.isFullscreen)")
    }

    /// Verifica y re‑inicia reproducción si no se aplicó correctamente
    /// FASE 5: Optimizado con concurrency gate y rate limiting
    func ensurePlaying(reason: String) {
        appLogger.info("🩺 ensurePlaying() invocado: \(reason)")

        // Rate limiting - prevenir ejecuciones demasiado frecuentes
        // Task 2.3: removed latching boolean; lock now serializes rebuilds.
        if let lastTime = lastEnsurePlayingTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < self.ensurePlayingMinInterval {
                appLogger.debug("🚦 ensurePlaying: rate limit - última ejecución hace \(String(format: "%.0fms", elapsed * 1000)), mínimo \(String(format: "%.0fms", self.ensurePlayingMinInterval * 1000))")
                return
            }
        }
        lastEnsurePlayingTime = Date()

        // Necesitamos datos mínimos
        guard currentVideo != nil else {
            appLogger.debug("ℹ️ No currentVideo disponible")
            return
        }

        // Si no se reporta reproducción pero el auto‑inicio está activo, intentar iniciar
        let shouldAutoStart = UserDefaults.standard.bool(forKey: "AutoStartWallpaper")
        if !isPlayingWallpaper && shouldAutoStart {
            appLogger.info("▶️ ensurePlaying: no isPlaying, auto‑inicio activo → startWallpaperSafe()")
            startWallpaperSafe()
            return
        }

        // Si se supone que está reproduciendo, validar de forma asíncrona
        if isPlayingWallpaper {
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Usar PlaybackHealthChecker para verificación asíncrona (probe-based, design D2)
                let isHealthy = await self.playbackHealthChecker.checkPlaybackHealth(
                    windows: self.desktopVideoInstances,
                    currentVideo: self.currentVideo,
                    bookmarkActor: self.bookmarkActor,
                    renderAdvanceVerdict: self.renderAdvanceState
                )

                if !isHealthy {
                    self.appLogger.warning("⚠️ ensurePlaying: verificación de salud falló, reiniciando...")
                    // Task 1.3: retained-level recovery decision + telemetry
                    self.recoveryDecisionLogger.error("🛠️ Recovery decision: health-check detected stall/unhealthy, triggering rebuild.")
                    // Task 2.4: bounded, escalating retry policy instead of single rebuild
                    Task { [self] in await self.attemptBoundedRecovery(reason: "health-check-unhealthy") }
                } else {
                    self.appLogger.debug("✅ ensurePlaying: reproducción verificada como saludable")
                    // Reset recovery state on healthy check
                    self.recoveryAttempts = 0
                    self.recoveryExhausted = false
                }
            }
        } else {
            appLogger.debug("ℹ️ ensurePlaying: isPlayingWallpaper=false y auto‑inicio desactivado")
        }
    }
    
    /// Registra el estado completo del sistema para debugging
    func logSystemState() {
        let timerDebugInfo = timerManager.getDebugInfo()
        let fullscreenDebugInfo = fullscreenDetector.getDebugInfo()
        
        var systemState = "=== SISTEMA LIVEWALLS DEBUG ===\n"
        systemState += "WallpaperManager State:\n"
        systemState += "- isPlayingWallpaper: \(isPlayingWallpaper)\n"
        systemState += "- isAutoChangeEnabled: \(isAutoChangeEnabled)\n"
        systemState += "- autoChangeInterval: \(Int(autoChangeInterval))s\n"
        systemState += "- currentVideo: \(currentVideo?.name ?? "None")\n"
        systemState += "- videoFiles.count: \(videoFiles.count)\n"
        systemState += "- enabledVideos.count: \(videoFiles.filter { $0.isEnabledForRandomPlay }.count)\n"
        systemState += "- desktopVideoInstances.count: \(desktopVideoInstances.count)\n"
        systemState += "- isWallpaperPausedForFullscreen: \(isWallpaperPausedForFullscreen)\n\n"
        
        systemState += timerDebugInfo + "\n"
        systemState += fullscreenDebugInfo
        
        appLogger.info("🐛 \(systemState)")
    }
    
    /// Función de debug para forzar verificación de estados
    func debugForceStateCheck() {
        Task {
            appLogger.info("🔧 Forzando verificación de estados...")
            
            // Verificar estado de fullscreen
            await fullscreenDetector.forceCheck()
            
            // Verificar salud del timer
            await performTimerHealthCheck()
            
            // Log estado completo
            logSystemState()
            
            appLogger.info("✅ Verificación de estados completada")
        }
    }
    
    /// Función de debug para testing de timer
    func debugTestTimer() {
        appLogger.info("🧪 Iniciando prueba de timer...")
        
        // Save current configuration
        let originalEnabled = isAutoChangeEnabled
        let originalInterval = autoChangeInterval
        
        // Configurar para prueba rápida
        isAutoChangeEnabled = true
        autoChangeInterval = 5.0 // 5 segundos para prueba
        
        // Iniciar timer de prueba
        startAutoChangeTimerIfNeeded()
        
        // Programar restauración después de 20 segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
            self.appLogger.info("🧪 Ending timer test, restoring configuration")
            self.isAutoChangeEnabled = originalEnabled
            self.autoChangeInterval = originalInterval
            self.saveAutoChangeSettings()
        }
    }
}

// MARK: - Final del archivo
