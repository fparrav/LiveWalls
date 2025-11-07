import Foundation
import os.log

/// Actor dedicado para manejar operaciones de persistencia de manera asíncrona
/// Mueve operaciones de UserDefaults y serialización JSON fuera del main thread
/// para evitar bloqueos durante el arranque de la aplicación
actor PersistenceActor {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "PersistenceActor")
    private let userDefaults: UserDefaults
    
    // UserDefaults keys
    private let videosKey = "SavedVideos"
    private let currentVideoKey = "CurrentVideo"
    private let autoChangeEnabledKey = "AutoChangeEnabled"
    private let autoChangeIntervalKey = "AutoChangeInterval"
    
    // Valores por defecto
    private let defaultAutoChangeInterval: TimeInterval = 10 * 60 // 10 minutos
    
    // MARK: - Initialization
    
    /// Inicializa el actor con UserDefaults personalizado (útil para testing)
    /// - Parameter userDefaults: Instancia de UserDefaults a usar (por defecto .standard)
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        logger.info("🔧 PersistenceActor inicializado")
    }
    
    // MARK: - Video Files Persistence
    
    /// Carga la lista de videos guardados de forma asíncrona
    /// - Returns: Array de VideoFile decodificados desde UserDefaults
    /// - Throws: Error si falla la decodificación JSON
    func loadVideos() async throws -> [VideoFile] {
        logger.debug("📂 Iniciando carga asíncrona de videos")
        
        guard let videoDataArray = userDefaults.array(forKey: videosKey) as? [Data] else {
            logger.info("📂 No se encontraron videos guardados")
            return []
        }
        
        let decoder = JSONDecoder()
        var videos: [VideoFile] = []
        var failedCount = 0
        
        for data in videoDataArray {
            do {
                let video = try decoder.decode(VideoFile.self, from: data)
                videos.append(video)
            } catch {
                failedCount += 1
                logger.warning("⚠️ Error al decodificar video: \(error.localizedDescription)")
            }
        }
        
        logger.info("📂 Cargados \(videos.count) videos (\(failedCount) fallidos)")
        return videos
    }
    
    /// Guarda la lista de videos de forma asíncrona
    /// - Parameter videos: Array de VideoFile a guardar
    /// - Throws: Error si falla la codificación JSON
    func saveVideos(_ videos: [VideoFile]) async throws {
        logger.debug("💾 Iniciando guardado asíncrono de \(videos.count) videos")
        
        let encoder = JSONEncoder()
        var videoData: [Data] = []
        var failedCount = 0
        
        for video in videos {
            do {
                let data = try encoder.encode(video)
                videoData.append(data)
            } catch {
                failedCount += 1
                logger.warning("⚠️ Error al codificar video '\(video.name)': \(error.localizedDescription)")
            }
        }
        
        userDefaults.set(videoData, forKey: videosKey)
        
        logger.info("💾 Guardados \(videoData.count) videos (\(failedCount) fallidos)")
    }
    
    // MARK: - Current Video Persistence
    
    /// Carga el video actual de forma asíncrona
    /// - Returns: VideoFile actual o nil si no existe
    func loadCurrentVideo() async -> VideoFile? {
        logger.debug("📂 Cargando video actual")
        
        guard let data = userDefaults.data(forKey: currentVideoKey) else {
            logger.info("📂 No hay video actual guardado")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let video = try decoder.decode(VideoFile.self, from: data)
            logger.info("📂 Video actual cargado: \(video.name)")
            return video
        } catch {
            logger.error("❌ Error al decodificar video actual: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Guarda el video actual de forma asíncrona
    /// - Parameter video: VideoFile a guardar como actual, o nil para limpiar
    func saveCurrentVideo(_ video: VideoFile?) async {
        guard let video = video else {
            logger.debug("💾 Limpiando video actual")
            userDefaults.removeObject(forKey: currentVideoKey)
            return
        }
        
        logger.debug("💾 Guardando video actual: \(video.name)")
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(video)
            userDefaults.set(data, forKey: currentVideoKey)
            logger.info("💾 Video actual guardado: \(video.name)")
        } catch {
            logger.error("❌ Error al codificar video actual: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Auto-Change Settings Persistence
    
    /// Carga la configuración de auto-change de forma asíncrona
    /// - Returns: Tupla con (isEnabled, interval) - interval por defecto es 10 minutos
    func loadAutoChangeSettings() async -> (isEnabled: Bool, interval: TimeInterval) {
        logger.debug("📂 Cargando configuración de auto-change")
        
        let isEnabled = userDefaults.bool(forKey: autoChangeEnabledKey)
        var interval = userDefaults.double(forKey: autoChangeIntervalKey)
        
        // Aplicar valor por defecto si el intervalo no es válido
        if interval <= 0 {
            interval = defaultAutoChangeInterval
        }
        
        logger.info("📂 Auto-change cargado: enabled=\(isEnabled), interval=\(Int(interval))s")
        return (isEnabled: isEnabled, interval: interval)
    }
    
    /// Guarda la configuración de auto-change de forma asíncrona
    /// - Parameters:
    ///   - isEnabled: Si el auto-change está habilitado
    ///   - interval: Intervalo en segundos entre cambios
    func saveAutoChangeSettings(isEnabled: Bool, interval: TimeInterval) async {
        logger.debug("💾 Guardando configuración de auto-change: enabled=\(isEnabled), interval=\(Int(interval))s")
        
        userDefaults.set(isEnabled, forKey: autoChangeEnabledKey)
        userDefaults.set(interval, forKey: autoChangeIntervalKey)
        
        logger.info("💾 Auto-change guardado: enabled=\(isEnabled), interval=\(Int(interval))s")
    }
}
