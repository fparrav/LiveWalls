// ScreenSaverManager.swift
// LiveWalls
//
// Gestor centralizado para la lógica de fondos de pantalla animados y modo dinámico tipo Sonoma.
//
// Este gestor permite alternar entre el modo de fondo animado siempre activo y el modo dinámico (animado solo al bloquear o en modo especial).
// Gestiona recursos, permisos y sincronización de estado.

import Foundation
import AppKit
import AVFoundation

/// Enum para los modos de funcionamiento del fondo de pantalla.
public enum ModoFondoPantalla: String, CaseIterable {
    case animadoSiempre = "Animado siempre"
    case dinamicoSonoma = "Dinámico tipo Sonoma"
}

/// Gestor especializado para funcionalidad de protector de pantalla y modos dinámicos.
/// - Maneja eventos de sistema y alternancia entre modos animado/dinámico.
/// - Usa WallpaperManager como dependencia para gestión de archivos y recursos.
final class ScreenSaverManager: ObservableObject {
    /// Modo de funcionamiento seleccionado por el usuario.
    @Published var modoActual: ModoFondoPantalla = .animadoSiempre
    /// Indica si el video está actualmente activo como fondo animado.
    @Published var videoActivo: Bool = false
    /// VideoFile seleccionado como fondo.
    @Published var videoFileActual: VideoFile?
    /// Permisos de accesibilidad concedidos.
    @Published var permisosAccesibilidad: Bool = false
    
    /// Dependencia: WallpaperManager para gestión de archivos y recursos.
    private let wallpaperManager: WallpaperManager
    /// Observador para eventos del sistema.
    private var observadorEventos: Any?
    /// Imagen estática actual (frame del video) para modo dinámico.
    private var imagenEstatica: NSImage?

    // MARK: - Inicialización y configuración

    /// Inicializa el ScreenSaverManager con una dependencia de WallpaperManager.
    /// - Parameter wallpaperManager: WallpaperManager para gestión de archivos y recursos.
    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager
        // Configura observadores de eventos del sistema
        configurarObservadoresSistema()
        // Verifica permisos de accesibilidad
        permisosAccesibilidad = verificarPermisosAccesibilidad()
    }

    deinit {
        // Elimina observadores al destruir el gestor
        if let obs = observadorEventos {
            NotificationCenter.default.removeObserver(obs)
        }
        // No necesitamos limpiar recursos de video aquí - WallpaperManager se encarga
    }

    /// Configura los observadores para eventos de bloqueo/desbloqueo de pantalla.
    private func configurarObservadoresSistema() {
        observadorEventos = NotificationCenter.default.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.manejarEventoBloqueoPantalla()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.manejarEventoDesbloqueoPantalla()
        }
    }

    /// Verifica si la app tiene permisos de accesibilidad.
    /// - Returns: true si los permisos están concedidos.
    private func verificarPermisosAccesibilidad() -> Bool {
        let opciones = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opciones)
    }

    /// Solicita permisos de accesibilidad al usuario si no están concedidos.
    public func solicitarPermisosAccesibilidad() {
        if !permisosAccesibilidad {
            _ = verificarPermisosAccesibilidad()
        }
    }

    // MARK: - Lógica de modos

    /// Cambia el modo de funcionamiento del fondo de pantalla.
    /// - Parameter modo: Modo seleccionado por el usuario.
    public func cambiarModo(_ modo: ModoFondoPantalla) {
        modoActual = modo
        if modo == .animadoSiempre {
            activarFondoAnimado()
        } else {
            activarModoDinamico()
        }
    }

    /// Activa el fondo de pantalla animado siempre.
    private func activarFondoAnimado() {
        videoActivo = true
        iniciarWallpaperAnimado()
    }

    /// Activa el modo dinámico tipo Sonoma.
    private func activarModoDinamico() {
        videoActivo = false
        capturarFrameYEstablecerWallpaperEstatico()
    }

    /// Inicia el wallpaper animado usando WallpaperManager.
    private func iniciarWallpaperAnimado() {
        guard let videoFile = videoFileActual else {
            print("⚠️ No hay video seleccionado para iniciar modo animado")
            return
        }
        
        // Establecer el video actual en WallpaperManager y iniciarlo
        wallpaperManager.setActiveVideo(videoFile)
        wallpaperManager.startWallpaperSafe()
    }

    /// Captura un frame del video actual y lo establece como fondo de pantalla estático.
    private func capturarFrameYEstablecerWallpaperEstatico() {
        guard let videoFile = videoFileActual else {
            print("⚠️ No hay video seleccionado para capturar frame")
            return
        }
        
        // Detener wallpaper animado si está activo
        wallpaperManager.stopWallpaper()
        
        // Resolver bookmark para acceder al archivo
        guard let accessibleURL = wallpaperManager.resolveBookmark(for: videoFile) else {
            print("❌ No se pudo resolver bookmark para: \(videoFile.name)")
            return
        }
        
        // Capturar frame del video
        let asset = AVAsset(url: accessibleURL)
        let generador = AVAssetImageGenerator(asset: asset)
        generador.appliesPreferredTrackTransform = true
        
        do {
            // Capturar frame en tiempo actual (0 si no hay tiempo específico)
            let cgImage = try generador.copyCGImage(at: CMTime.zero, actualTime: nil)
            let imagen = NSImage(cgImage: cgImage, size: .zero)
            imagenEstatica = imagen
            establecerImagenComoWallpaper(imagen)
        } catch {
            print("❌ Error al capturar frame: \(error)")
        }
        
        // Liberar acceso security-scoped (WallpaperManager se encarga internamente)
    }

    /// Establece una imagen como fondo de pantalla del escritorio.
    private func establecerImagenComoWallpaper(_ imagen: NSImage) {
        guard let pantalla = NSScreen.main else { return }
        let directorioTemp = FileManager.default.temporaryDirectory
        let urlTemp = directorioTemp.appendingPathComponent("livewalls_wallpaper_temp.png")
        guard let datos = imagen.tiffRepresentation,
              let rep = NSBitmapImageRep(data: datos),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: urlTemp)
            try NSWorkspace.shared.setDesktopImageURL(urlTemp, for: pantalla, options: [:])
        } catch {
            print("Error al establecer wallpaper: \(error)")
        }
    }

    /// Detiene el wallpaper usando WallpaperManager.
    private func detenerWallpaper() {
        wallpaperManager.stopWallpaper()
    }

    /// Establece el VideoFile seleccionado como fondo de pantalla.
    /// - Parameter videoFile: VideoFile a usar.
    public func seleccionarVideoFile(_ videoFile: VideoFile) {
        videoFileActual = videoFile
        // Aplicar el modo actual al nuevo video
        aplicarModoActual()
    }
    
    /// Establece el video seleccionado como fondo de pantalla (compatibilidad con URL).
    /// - Parameter url: URL del video a usar.
    public func seleccionarVideo(_ url: URL) {
        // Buscar el VideoFile correspondiente en WallpaperManager
        if let videoFile = wallpaperManager.videoFiles.first(where: { $0.url == url }) {
            seleccionarVideoFile(videoFile)
        } else {
            print("⚠️ No se encontró VideoFile para URL: \(url)")
        }
    }
    
    /// Aplica el modo actual al video seleccionado.
    private func aplicarModoActual() {
        switch modoActual {
        case .animadoSiempre:
            activarFondoAnimado()
        case .dinamicoSonoma:
            activarModoDinamico()
        }
    }

    /// Permite probar el modo animado manualmente.
    public func probarModoAnimado() {
        let modoAnterior = modoActual
        modoActual = .animadoSiempre
        activarFondoAnimado()
        modoActual = modoAnterior
    }

    /// Permite probar el modo dinámico manualmente.
    public func probarModoDinamico() {
        let modoAnterior = modoActual
        modoActual = .dinamicoSonoma
        activarModoDinamico()
        modoActual = modoAnterior
    }
    
    // MARK: - Manejo de eventos de sistema
    
    /// Maneja el evento de bloqueo de pantalla.
    private func manejarEventoBloqueoPantalla() {
        if modoActual == .dinamicoSonoma {
            // Inicia reproducción de video en modo dinámico cuando se bloquea
            videoActivo = true
            iniciarWallpaperAnimado()
        }
    }

    /// Maneja el evento de desbloqueo de pantalla.
    private func manejarEventoDesbloqueoPantalla() {
        if modoActual == .dinamicoSonoma {
            // Captura el frame actual y lo establece como fondo estático al desbloquear
            videoActivo = false
            capturarFrameYEstablecerWallpaperEstatico()
        }
    }
}
