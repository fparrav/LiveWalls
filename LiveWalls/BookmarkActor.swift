import Foundation
import os.log

/// Actor dedicado para manejar operaciones de resolución de bookmarks y acceso a archivos
/// Ejecuta operaciones I/O fuera del main thread para evitar bloqueos durante el arranque
actor BookmarkActor {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "BookmarkActor")
    
    /// Set thread-safe de URLs con acceso security-scoped activo
    private var activeSecurityScopedURLs: Set<String> = []
    
    /// FASE 3: Cache de bookmarks resueltos para evitar resoluciones redundantes
    /// Key: bookmark data hash, Value: resolved URL
    private var resolvedBookmarkCache: [String: URL] = [:]
    
    // MARK: - Initialization
    
    init() {
        logger.info("📚 BookmarkActor inicializado")
    }
    
    deinit {
        logger.info("🧹 BookmarkActor deinicializando")
    }
    
    // MARK: - Bookmark Resolution
    
    /// Resuelve un bookmark security-scoped de forma asíncrona
    /// - Parameter bookmarkData: Data del bookmark a resolver
    /// - Returns: URL accesible resuelta desde el bookmark
    /// - Throws: Error si la resolución falla
    func resolveBookmark(bookmarkData: Data) async throws -> URL {
        // FASE 3: Consultar cache primero
        let cacheKey = bookmarkData.base64EncodedString()
        
        if let cachedURL = resolvedBookmarkCache[cacheKey] {
            logger.debug("⚡ Cache HIT para bookmark: \(cachedURL.lastPathComponent)")
            return cachedURL
        }
        
        logger.debug("🔍 Cache MISS - Resolviendo bookmark de forma asíncrona...")
        
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        if isStale {
            logger.warning("⚠️ Bookmark obsoleto detectado para: \(url.lastPathComponent)")
        }
        
        // FASE 3: Almacenar en cache para futuras resoluciones
        resolvedBookmarkCache[cacheKey] = url
        
        logger.info("✅ Bookmark resuelto y cacheado: \(url.lastPathComponent)")
        return url
    }
    
    // MARK: - Security-Scoped Resource Management
    
    /// Inicia el acceso a un security-scoped resource
    /// - Parameter url: URL del recurso
    /// - Returns: true si el acceso se inició correctamente
    func startAccessingSecurityScopedResource(url: URL) -> Bool {
        let normalizedPath = url.path
        
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("❌ No se pudo iniciar acceso security-scoped para: \(normalizedPath)")
            return false
        }
        
        activeSecurityScopedURLs.insert(normalizedPath)
        logger.debug("🔓 Acceso security-scoped iniciado: \(normalizedPath)")
        
        return true
    }
    
    /// Detiene el acceso a un security-scoped resource
    /// - Parameter url: URL del recurso
    func stopAccessingSecurityScopedResource(url: URL) {
        let normalizedPath = url.path
        
        guard activeSecurityScopedURLs.contains(normalizedPath) else {
            logger.debug("ℹ️ URL no tiene acceso activo: \(normalizedPath)")
            return
        }
        
        activeSecurityScopedURLs.remove(normalizedPath)
        url.stopAccessingSecurityScopedResource()
        logger.debug("🔒 Acceso security-scoped detenido: \(normalizedPath)")
    }
    
    /// Detiene todos los accesos security-scoped activos
    func stopAllSecurityScopedAccess() {
        logger.info("🧹 Deteniendo todos los accesos security-scoped (\(self.activeSecurityScopedURLs.count) activos)")
        
        for path in self.activeSecurityScopedURLs {
            if let url = URL(string: "file://\(path)") {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        self.activeSecurityScopedURLs.removeAll()
        logger.info("✅ Todos los accesos security-scoped detenidos")
    }
    
    // MARK: - Cache Management (Fase 3)
    
    /// Invalida el cache de bookmarks resueltos
    /// Se debe llamar cuando se cambia de video para forzar nueva resolución
    func invalidateCache() {
        let cacheSize = resolvedBookmarkCache.count
        resolvedBookmarkCache.removeAll()
        logger.info("🗑️ Cache de bookmarks invalidado (\(cacheSize) entradas eliminadas)")
    }
    
    /// Retorna el tamaño actual del cache (para debugging/testing)
    func getCacheSize() -> Int {
        return resolvedBookmarkCache.count
    }
    
    // MARK: - Debug & Monitoring
    
    /// Retorna el número de URLs con acceso activo (para debugging)
    func getActiveResourceCount() -> Int {
        return activeSecurityScopedURLs.count
    }
    
    /// Retorna información de debug sobre el estado del actor
    func getDebugInfo() -> String {
        var info = "=== BookmarkActor Debug Info ===\n"
        info += "Active security-scoped URLs: \(activeSecurityScopedURLs.count)\n"
        
        if !activeSecurityScopedURLs.isEmpty {
            info += "Active URLs:\n"
            for path in activeSecurityScopedURLs {
                info += "  - \(path)\n"
            }
        }
        
        return info
    }
}
