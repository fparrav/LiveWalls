import Foundation
import os.log

/// Actor dedicado para manejar operaciones de resolución de bookmarks y acceso a archivos
/// Ejecuta operaciones I/O fuera del main thread para evitar bloqueos durante el arranque
actor BookmarkActor {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.livewalls.app", category: "BookmarkActor")
    
    /// Task 2.6 / Design D6: per-URL ref-count of security-scoped accesses.
    /// Key = `url.path` (normalized file identity), Value = (resolved URL, count).
    /// - count is incremented on every `start`, decremented on every `stop`.
    /// - The real URL is kept (not just the path) so `stop` calls `url.stopAccessingSecurityScopedResource()`
    ///   on the same instance that was started — fixes the prior `URL(string:)` reconstruction.
    /// - double-stop decrements only when an entry exists; an absent entry is a silent no-op.
    /// - a start-after-failure does NOT create a dangling stop: the entry is only created
    ///   if the underlying `startAccessingSecurityScopedResource()` returned true.
    /// - Task 2.8 / D9: kill-switch `bookmarkRefCount`. OFF = legacy Set semantics (no ref-count).
    private var securityScopedAccess: [String: (url: URL, count: Int)] = [:]
    
    /// FASE 3: Cache de bookmarks resueltos para evitar resoluciones redundantes
    /// Key: bookmark data hash, Value: resolved URL
    private var resolvedBookmarkCache: [String: URL] = [:]
    
    /// PHASE 3: Timestamp tracking for bookmark staleness detection
    /// Key: bookmark data hash, Value: timestamp of when bookmark was resolved
    private var bookmarkTimestamps: [String: Date] = [:]
    
     /// PHASE 3: Threshold for marking bookmarks as stale (5 minutes = 300 seconds)
     /// Bookmarks older than this are considered potentially unreliable
     /// 5-minute threshold chosen to balance freshness vs performance:
     /// - macOS bookmarks typically valid for hours/days in normal sessions
     /// - 5 minutes catches cases where system woke from sleep or network shares reconnected
     /// - Prevents excessive re-resolution during normal use
     private let bookmarkStaleThreshold: TimeInterval = 300.0
    
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
        
        // PHASE 3: Store timestamp for staleness detection
        bookmarkTimestamps[cacheKey] = Date()
        
        logger.info("✅ Bookmark resuelto y cacheado: \(url.lastPathComponent)")
        return url
    }
    
    // MARK: - Security-Scoped Resource Management
    
    /// Inicia el acceso a un security-scoped resource (con ref-count).
    /// - Parameter url: URL del recurso (con acceso security-scoped válido).
    /// - Returns: true si el acceso se inició/ya estaba activo; false si la API del sistema falló.
    func startAccessingSecurityScopedResource(url: URL) -> Bool {
        let normalizedPath = url.path

        // Si ya hay una entrada para este path, incrementamos el contador
        // y NO volvemos a llamar a la API del sistema — ya hay un acceso vivo.
        if var entry = securityScopedAccess[normalizedPath] {
            entry.count += 1
            securityScopedAccess[normalizedPath] = entry
            logger.debug("🔓 Acceso security-scoped REF-COUNT incrementado a \(entry.count): \(normalizedPath)")
            return true
        }

        // Primera vez para este path: intentamos iniciar el acceso real.
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("❌ No se pudo iniciar acceso security-scoped para: \(normalizedPath)")
            return false
        }

        // Éxito: creamos la entrada con count = 1 y guardamos el URL real resuelto.
        securityScopedAccess[normalizedPath] = (url: url, count: 1)
        logger.debug("🔓 Acceso security-scoped INICIADO (count=1): \(normalizedPath)")

        return true
    }

    /// Detiene el acceso a un security-scoped resource.
    /// - Task 2.8 / D9: kill-switch `bookmarkRefCount`. OFF = legacy Set semantics.
    ///   ON (true) = ref-count por URL (como abajo). OFF = tratar como Set booleano.
    /// - Parameter url: URL del recurso. El path normalizado identifica la entrada.
    func stopAccessingSecurityScopedResource(url: URL) {
        let useRefCount = RecoveryDebugFlags.bookmarkRefCount
        let normalizedPath = url.path

        if useRefCount {
            // ---- REF-COUNT PATH (Task 2.6 fix) ----
            guard var entry = securityScopedAccess[normalizedPath] else {
                // Double-stop silencioso: no hay entrada → nada que hacer.
                logger.debug("ℹ️ stopAccessingSecurityScopedResource: sin entrada para \(normalizedPath) (double-stop safe)")
                return
            }

            // Decrementar contador.
            entry.count -= 1

            if entry.count > 0 {
                // Todavía hay referencias vivas → solo actualizamos count.
                securityScopedAccess[normalizedPath] = entry
                logger.debug("🔒 Acceso security-scoped REF-COUNT decrementado a \(entry.count): \(normalizedPath)")
                return
            }

            // Count llegó a 0 → llamamos a la API del sistema SOBRE el URL GUARDADO
            // (no reconstruido desde string) y eliminamos la entrada.
            entry.url.stopAccessingSecurityScopedResource()
            securityScopedAccess.removeValue(forKey: normalizedPath)
            logger.debug("🔒 Acceso security-scoped LIBERADO (count→0): \(normalizedPath)")
        } else {
            // ---- LEGACY SET PATH (Task 2.6 OFF) ----
            guard securityScopedAccess[normalizedPath] != nil else {
                // No había entrada → doble stop silencioso.
                logger.debug("ℹ️ stopAccessingSecurityScopedResource: sin entrada para \(normalizedPath) (double-stop safe, legacy)")
                return
            }
            // Tenía entrada → liberar y borrar.
            securityScopedAccess[normalizedPath]?.url.stopAccessingSecurityScopedResource()
            securityScopedAccess.removeValue(forKey: normalizedPath)
            logger.debug("🔒 Acceso security-scoped LIBERADO (legacy Set): \(normalizedPath)")
        }
    }

    /// Detiene TODOS los accesos security-scoped activos (teardown forzado).
    /// Usa los URLs guardados, NO `URL(string:)`.
    func stopAllSecurityScopedAccess() {
        let entryCount = securityScopedAccess.count
        var totalCount = 0

        logger.info("🧹 Deteniendo todos los accesos security-scoped (\(entryCount) entradas, recuento total pendiente)")

        for (path, entry) in securityScopedAccess {
            totalCount += entry.count
            // Forzamos una sola llamada stop por entrada (teardown completo).
            // El count acumulado se ignora — esta es una limpieza de emergencia.
            entry.url.stopAccessingSecurityScopedResource()
            logger.debug("🔒 stopAllSecurityScopedAccess: liberado \(path)")
        }

        securityScopedAccess.removeAll()
        logger.info("✅ Todos los accesos security-scoped detenidos (\(entryCount) entradas, \(totalCount) accesos acumulados)")
    }

    /// Task 2.6 / Design D6: drena el estado a cero para que el rebuild
    /// empiece desde un estado limpio conocido. Idempotente.
    /// - Una llamada `stopAccessingSecurityScopedResource()` por entrada:
    ///   el actor sólo hace UN `start` real por entrada (los siguientes sólo
    ///   incrementan el count), así que un solo `stop` real la balancea.
    ///   Apple documenta que llamar `stop` más veces de las que se llamó
    ///   `start` es incorrecto, por eso NO se drena `count` veces.
    ///   Idéntico en efecto a `stopAllSecurityScopedAccess()`; se mantiene
    ///   aparte por el logging de contexto de recovery.
    func reconcile() {
        let entryCount = securityScopedAccess.count
        var totalCount = 0

        guard entryCount > 0 else {
            logger.debug("🔄 reconcile: ya en estado cero (sin entradas)")
            return
        }

        logger.info("🔄 reconcile: drenando \(entryCount) entradas activas al inicio del rebuild")

        for (path, entry) in securityScopedAccess {
            totalCount += entry.count
            entry.url.stopAccessingSecurityScopedResource()
            logger.debug("🔄 reconcile: liberado \(path) (count lógico=\(entry.count))")
        }

        securityScopedAccess.removeAll()
        logger.info("✅ reconcile completado: \(entryCount) entradas, \(totalCount) accesos lógicos drenados → estado cero")
    }
    
    // MARK: - Cache Management (Fase 3)
    
    /// PHASE 3: Checks if a bookmark is stale (older than threshold)
    /// Stale bookmarks may have lost security-scoped access validity
    /// - Parameter bookmarkData: The bookmark data to check for staleness
    /// - Returns: true if bookmark is stale or not in cache, false if fresh
    func isBookmarkStale(for bookmarkData: Data) -> Bool {
        let cacheKey = bookmarkData.base64EncodedString()
        
        guard let timestamp = bookmarkTimestamps[cacheKey] else {
            // No timestamp = bookmark not in cache or very old
            logger.debug("⚠️ Bookmark timestamp not found (stale)")
            return true
        }
        
        let age = Date().timeIntervalSince(timestamp)
        let isStale = age > self.bookmarkStaleThreshold
        
        if isStale {
            logger.warning("⚠️ Bookmark is stale (\(age)s > \(self.bookmarkStaleThreshold)s threshold)")
        } else {
            logger.debug("✅ Bookmark is fresh (\(age)s)")
        }
        
        return isStale
    }
    
    /// Invalida el cache de bookmarks resueltos
    /// Se debe llamar cuando se cambia de video para forzar nueva resolución
    func invalidateCache() {
        let cacheSize = resolvedBookmarkCache.count
        resolvedBookmarkCache.removeAll()
        bookmarkTimestamps.removeAll()
        logger.info("🗑️ Cache de bookmarks invalidado (\(cacheSize) entradas eliminadas)")
    }
    
    /// Retorna el tamaño actual del cache (para debugging/testing)
    func getCacheSize() -> Int {
        return resolvedBookmarkCache.count
    }
    
    // MARK: - Debug & Monitoring
    
    /// Retorna el número de URLs con acceso activo (para debugging)
    func getActiveResourceCount() -> Int {
        return securityScopedAccess.count
    }

    /// Retorna información de debug sobre el estado del actor
    func getDebugInfo() -> String {
        var info = "=== BookmarkActor Debug Info ===\n"
        info += "Active security-scoped entries: \(securityScopedAccess.count)\n"

        if !securityScopedAccess.isEmpty {
            info += "Active entries:\n"
            for (path, entry) in securityScopedAccess {
                info += "  - \(path) (count=\(entry.count))\n"
            }
        }

        return info
    }
}
