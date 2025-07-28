import Foundation
import AppKit
import os.log

/// Detector de aplicaciones en pantalla completa
/// Monitorea el estado de las aplicaciones y detecta cuando una aplicación entra o sale de modo fullscreen
@MainActor
class FullscreenDetector: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Indica si actualmente hay una aplicación en pantalla completa
    @Published var isAnyAppFullscreen: Bool = false
    
    /// Nombre de la aplicación actualmente en fullscreen (si hay alguna)
    @Published var currentFullscreenApp: String? = nil
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "FullscreenDetector")
    private var applicationObserver: NSObjectProtocol?
    private var presentationOptionsObserver: NSObjectProtocol?
    
    // MARK: - Callbacks
    
    /// Callback que se ejecuta cuando una aplicación entra en fullscreen
    var onFullscreenEntered: ((String) -> Void)?
    
    /// Callback que se ejecuta cuando se sale de fullscreen
    var onFullscreenExited: (() -> Void)?
    
    // MARK: - Initialization
    
    init() {
        logger.info("🔍 Inicializando FullscreenDetector")
        setupObservers()
        
        // Verificar estado inicial
        Task {
            await checkInitialFullscreenState()
        }
    }
    
    deinit {
        logger.info("🔍 Deinicializando FullscreenDetector")
        Task { @MainActor in
            removeObservers()
        }
    }
    
    // MARK: - Observer Setup
    
    private func setupObservers() {
        setupApplicationObservers()
        setupPresentationOptionsObserver()
    }
    
    private func setupApplicationObservers() {
        // Observar cuando aplicaciones se activan
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                await self?.handleApplicationActivated(notification)
            }
        }
        
        logger.info("📡 Configurados observers de NSWorkspace")
    }
    
    private func setupPresentationOptionsObserver() {
        // Observar cambios en las opciones de presentación del sistema
        presentationOptionsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.checkPresentationOptions()
            }
        }
        
        logger.info("📡 Configurado observer de presentación")
    }
    
    private func removeObservers() {
        if let observer = applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            applicationObserver = nil
        }
        
        if let observer = presentationOptionsObserver {
            NotificationCenter.default.removeObserver(observer)
            presentationOptionsObserver = nil
        }
        
        logger.info("📡 Observers removidos")
    }
    
    // MARK: - State Detection
    
    private func checkInitialFullscreenState() async {
        await checkPresentationOptions()
        await checkActiveApplication()
    }
    
    private func handleApplicationActivated(_ notification: Notification) async {
        await checkActiveApplication()
    }
    
    private func checkActiveApplication() async {
        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            logger.debug("🔍 No hay aplicación activa")
            await updateFullscreenState(false, appName: nil)
            return
        }
        
        let appName = activeApp.localizedName ?? "Unknown"
        logger.debug("🔍 Aplicación activa: \(appName)")
        
        // Verificar si la aplicación está en fullscreen
        let isFullscreen = await isApplicationFullscreen(activeApp)
        await updateFullscreenState(isFullscreen, appName: isFullscreen ? appName : nil)
    }
    
    private func checkPresentationOptions() async {
        let options = NSApp.presentationOptions
        let isFullscreen = options.contains(.fullScreen) || 
                          options.contains(.hideMenuBar) && options.contains(.hideDock)
        
        if isFullscreen {
            if let activeApp = NSWorkspace.shared.frontmostApplication {
                let appName = activeApp.localizedName ?? "Unknown"
                logger.info("🎮 Detectado fullscreen via presentation options: \(appName)")
                await updateFullscreenState(true, appName: appName)
            }
        } else {
            // Verificar si realmente salimos de fullscreen o solo cambió algo más
            await checkActiveApplication()
        }
    }
    
    private func isApplicationFullscreen(_ application: NSRunningApplication) async -> Bool {
        // Método 1: Verificar ventanas de la aplicación
        let pid = application.processIdentifier
        
        // Obtener lista de ventanas de la aplicación
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            logger.warning("⚠️ No se pudo obtener lista de ventanas")
            return false
        }
        
        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid else { continue }
            
            // Verificar si la ventana ocupa toda la pantalla
            if let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? CGFloat,
               let y = bounds["Y"] as? CGFloat,
               let width = bounds["Width"] as? CGFloat,
               let height = bounds["Height"] as? CGFloat {
                
                let windowRect = CGRect(x: x, y: y, width: width, height: height)
                
                // Verificar contra cada pantalla
                for screen in NSScreen.screens {
                    let screenFrame = screen.frame
                    
                    // Tolerancia para diferencias menores
                    let tolerance: CGFloat = 10
                    
                    if abs(windowRect.origin.x - screenFrame.origin.x) < tolerance &&
                       abs(windowRect.origin.y - screenFrame.origin.y) < tolerance &&
                       abs(windowRect.width - screenFrame.width) < tolerance &&
                       abs(windowRect.height - screenFrame.height) < tolerance {
                        
                        logger.info("🎮 Ventana fullscreen detectada: \(String(describing: windowRect)) en pantalla \(String(describing: screenFrame))")
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    private func updateFullscreenState(_ isFullscreen: Bool, appName: String?) async {
        let previousState = isAnyAppFullscreen
        
        isAnyAppFullscreen = isFullscreen
        currentFullscreenApp = appName
        
        // Logging detallado
        if isFullscreen && !previousState {
            logger.info("🎮 ENTRADA A FULLSCREEN: \(appName ?? "Unknown")")
            onFullscreenEntered?(appName ?? "Unknown")
        } else if !isFullscreen && previousState {
            logger.info("🏠 SALIDA DE FULLSCREEN")
            onFullscreenExited?()
        }
        
        // Log de estado actual
        if isFullscreen {
            logger.debug("📱 Estado actual: Fullscreen (\(appName ?? "Unknown"))")
        } else {
            logger.debug("🪟 Estado actual: Windowed mode")
        }
    }
    
    // MARK: - Public Interface
    
    /// Fuerza una verificación manual del estado fullscreen
    func forceCheck() async {
        logger.info("🔄 Forzando verificación de estado fullscreen")
        await checkInitialFullscreenState()
    }
    
    /// Obtiene información detallada del estado actual
    func getCurrentState() -> (isFullscreen: Bool, appName: String?) {
        return (isAnyAppFullscreen, currentFullscreenApp)
    }
}

// MARK: - Debug Extensions

extension FullscreenDetector {
    
    /// Información de debugging sobre el estado actual
    func getDebugInfo() -> String {
        var info = "=== FullscreenDetector Debug Info ===\n"
        info += "Is Any App Fullscreen: \(isAnyAppFullscreen)\n"
        info += "Current Fullscreen App: \(currentFullscreenApp ?? "None")\n"
        
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            info += "Active Application: \(activeApp.localizedName ?? "Unknown")\n"
            info += "Active App PID: \(activeApp.processIdentifier)\n"
        }
        
        let options = NSApp.presentationOptions
        info += "Presentation Options: \(options.rawValue)\n"
        info += "Contains .fullScreen: \(options.contains(.fullScreen))\n"
        info += "Contains .hideMenuBar: \(options.contains(.hideMenuBar))\n"
        info += "Contains .hideDock: \(options.contains(.hideDock))\n"
        
        return info
    }
}