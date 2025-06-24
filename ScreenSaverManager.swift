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
enum ModoFondoPantalla: String, CaseIterable {
    case animadoSiempre = "Animado siempre"
    case dinamicoSonoma = "Dinámico tipo Sonoma"
}

/// Gestor principal para la lógica de fondos de pantalla animados y modo dinámico.
/// - Permite alternar entre modos y gestiona recursos de video y permisos.
final class ScreenSaverManager: ObservableObject {
    /// Modo de funcionamiento seleccionado por el usuario.
    @Published var modoActual: ModoFondoPantalla = .animadoSiempre
    /// Indica si el video está actualmente activo como fondo animado.
    @Published var videoActivo: Bool = false
    /// URL del video seleccionado como fondo.
    @Published var urlVideo: URL?
    /// Permisos de accesibilidad concedidos.
    @Published var permisosAccesibilidad: Bool = false
    /// Observador para eventos del sistema.
    private var observadorEventos: Any?
    /// Reproductor de video para el fondo animado.
    private var reproductor: AVPlayer?
    /// Imagen estática actual (frame del video).
    private var imagenEstatica: NSImage?
    /// Ventana para mostrar el video como fondo de escritorio.
    private var ventanaVideo: NSWindow?
    /// Capa de reproducción de video.
    private var capaVideo: AVPlayerLayer?

    // MARK: - Inicialización y configuración

    init() {
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
        mostrarVideoComoFondo()
    }

    /// Activa el modo dinámico tipo Sonoma.
    private func activarModoDinamico() {
        videoActivo = false
        pausarYCapturarFrameComoFondo()
    }

    /// Muestra el video seleccionado como fondo de escritorio usando una ventana en el nivel desktop.
    private func mostrarVideoComoFondo() {
        // Libera recursos previos
        cerrarVentanaVideo()
        guard let url = urlVideo else { return }
        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        reproductor = player
        // Crea la ventana en el nivel desktop
        let pantalla = NSScreen.main ?? NSScreen.screens.first
        let frame = pantalla?.frame ?? .zero
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .desktop
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Crea la capa de video
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = frame
        playerLayer.videoGravity = .resizeAspectFill
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.addSublayer(playerLayer)
        window.makeKeyAndOrderFront(nil)
        ventanaVideo = window
        capaVideo = playerLayer
        player.play()
    }

    /// Pausa el video, captura el frame actual y lo establece como fondo de pantalla estático.
    private func pausarYCapturarFrameComoFondo() {
        reproductor?.pause()
        guard let url = urlVideo, let player = reproductor else { cerrarVentanaVideo(); return }
        let tiempo = player.currentTime()
        let asset = AVAsset(url: url)
        let generador = AVAssetImageGenerator(asset: asset)
        generador.appliesPreferredTrackTransform = true
        do {
            let cgImage = try generador.copyCGImage(at: tiempo, actualTime: nil)
            let imagen = NSImage(cgImage: cgImage, size: .zero)
            imagenEstatica = imagen
            establecerImagenComoWallpaper(imagen)
        } catch {
            print("Error al capturar frame: \(error)")
        }
        cerrarVentanaVideo()
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

    /// Cierra y libera la ventana de video si existe.
    private func cerrarVentanaVideo() {
        capaVideo?.removeFromSuperlayer()
        capaVideo = nil
        ventanaVideo?.orderOut(nil)
        ventanaVideo = nil
        reproductor = nil
    }

    /// Establece el video seleccionado como fondo de pantalla.
    /// - Parameter url: URL del video a usar.
    public func seleccionarVideo(_ url: URL) {
        urlVideo = url
        if modoActual == .animadoSiempre {
            mostrarVideoComoFondo()
        } else {
            pausarYCapturarFrameComoFondo()
        }
    }

    /// Permite probar el modo animado manualmente.
    public func probarModoAnimado() {
        activarFondoAnimado()
    }

    /// Permite probar el modo dinámico manualmente.
    public func probarModoDinamico() {
        activarModoDinamico()
    }
}
