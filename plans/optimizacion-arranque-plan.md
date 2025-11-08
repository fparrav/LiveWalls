## Plan: Optimización de Arranque y Eliminación de Bloqueos en Main Thread

El análisis revela **11 operaciones bloqueantes críticas** que causan cuelgues de 6-12 segundos durante el arranque. La solución refactoriza la arquitectura moviendo operaciones I/O y polling loops a actors dedicados, usando AsyncStream para observación reactiva, eliminando bloqueos del main thread y mejorando el rendimiento **30-60x** (reducción a <200ms).

**Fases: 8 fases**

### 1. Phase 1: Crear BookmarkActor para Operaciones de Archivos Asíncronas
- **Objetivo:** Mover todas las operaciones de resolución de bookmarks y acceso a archivos fuera del main thread a un actor dedicado
- **Archivos a Modificar/Crear:**
  - `LiveWalls/BookmarkActor.swift` (nuevo)
  - `LiveWalls/WallpaperManager.swift` (modificar `resolveBookmark`, `saveVideos`, `loadSavedVideos`)
- **Tests a Escribir:**
  - `testBookmarkActorResolveBookmarkAsync`
  - `testBookmarkActorConcurrentAccess`
  - `testBookmarkActorMainThreadNotBlocked`
- **Pasos:**
  1. Crear nuevo archivo `BookmarkActor.swift` con actor para operaciones de bookmarks
  2. Escribir tests que verifiquen que `resolveBookmark` no bloquea main thread (test fallando)
  3. Implementar `BookmarkActor` con método `resolveBookmark() async throws -> URL?`
  4. Migrar lógica de resolución de bookmarks de WallpaperManager a BookmarkActor
  5. Actualizar WallpaperManager para usar `await bookmarkActor.resolveBookmark()`
  6. Ejecutar tests para confirmar que pasan y main thread no se bloquea

### 2. Phase 2: Crear PersistenceActor para Operaciones de UserDefaults y Serialización
- **Objetivo:** Mover operaciones de carga/guardado de UserDefaults y serialización JSON a actor dedicado para eliminar bloqueos de I/O
- **Archivos a Modificar/Crear:**
  - `LiveWalls/PersistenceActor.swift` (nuevo)
  - `LiveWalls/WallpaperManager.swift` (modificar `loadSavedVideos`, `saveVideos`, `loadCurrentVideo`, `saveCurrentVideo`)
- **Tests a Escribir:**
  - `testPersistenceActorLoadVideosAsync`
  - `testPersistenceActorSaveVideosAsync`
  - `testPersistenceActorSerializationNotBlockingMainThread`
- **Pasos:**
  1. Crear tests para PersistenceActor que verifiquen carga/guardado asíncrono (tests fallando)
  2. Implementar `PersistenceActor` con métodos `loadVideos()`, `saveVideos()`, `loadCurrentVideo()`, `saveCurrentVideo()`
  3. Migrar lógica de serialización JSON y UserDefaults de WallpaperManager
  4. Actualizar WallpaperManager init para llamar `await persistenceActor.loadVideos()` en background
  5. Reemplazar llamadas síncronas de save/load con versiones async
  6. Ejecutar tests y verificar que pasan sin bloqueos

### 3. Phase 3: Eliminar Loop de Polling `waitForSystemReadiness` y Reemplazar con Observación Reactiva
- **Objetivo:** Eliminar el loop while síncrono que verifica pantallas cada 150ms y reemplazarlo con observación reactiva de notificaciones de sistema
- **Archivos a Modificar/Crear:**
  - `LiveWalls/SystemReadinessObserver.swift` (nuevo)
  - `LiveWalls/WallpaperManager.swift` (eliminar `waitForSystemReadiness`, modificar `attemptAutoStart`)
- **Tests a Escribir:**
  - `testSystemReadinessObserverReportsReadyWhenScreensAvailable`
  - `testSystemReadinessObserverDoesNotBlockMainThread`
  - `testAutoStartWaitsForSystemReadiness`
- **Pasos:**
  1. Escribir tests para SystemReadinessObserver que usen notificaciones de NSScreen (tests fallando)
  2. Crear `SystemReadinessObserver` que publique AsyncStream<Bool> basado en notificaciones
  3. Implementar observación de `NSApplication.didChangeScreenParametersNotification`
  4. Reemplazar `waitForSystemReadiness` con `await systemReadinessObserver.isReady`
  5. Actualizar `attemptAutoStart` para usar observación reactiva en lugar de polling
  6. Ejecutar tests y verificar eliminación de loop bloqueante

### 4. Phase 4: Refactorizar `attemptAutoStart` para Eliminar Reintentos Síncronos en Main Thread
- **Objetivo:** Eliminar el loop de 25 reintentos cada 0.2s (5s total de bloqueo) y usar estrategia de inicio diferido con backoff exponencial
- **Archivos a Modificar/Crear:**
  - `LiveWalls/WallpaperManager.swift` (refactorizar `attemptAutoStart`)
  - `LiveWalls/StartupCoordinator.swift` (nuevo)
- **Tests a Escribir:**
  - `testAttemptAutoStartDoesNotBlockMainThread`
  - `testAttemptAutoStartRetriesWithExponentialBackoff`
  - `testAttemptAutoStartStopsAfterMaxRetries`
- **Pasos:**
  1. Escribir tests que verifiquen que attemptAutoStart no bloquea y usa backoff (tests fallando)
  2. Crear `StartupCoordinator` que gestione reintentos con Task.sleep en background
  3. Implementar backoff exponencial (0.2s, 0.5s, 1s, 2s) en lugar de 25 reintentos fijos
  4. Mover lógica de reintentos a StartupCoordinator con Task.detached
  5. Actualizar attemptAutoStart para delegar a StartupCoordinator
  6. Ejecutar tests y verificar eliminación de bloqueos de reintentos

### 5. Phase 5: Refactorizar `ensurePlaying` para Verificaciones Asíncronas No Bloqueantes
- **Objetivo:** Convertir verificaciones síncronas de estado de ventanas y bookmarks en operaciones asíncronas que no bloquean el main thread
- **Archivos a Modificar/Crear:**
  - `LiveWalls/WallpaperManager.swift` (refactorizar `ensurePlaying`)
  - `LiveWalls/PlaybackHealthChecker.swift` (nuevo)
- **Tests a Escribir:**
  - `testEnsurePlayingDoesNotBlockMainThread`
  - `testEnsurePlayingRestartsPlaybackWhenNeeded`
  - `testPlaybackHealthCheckerRunsAsynchronously`
- **Pasos:**
  1. Escribir tests que verifiquen que ensurePlaying no bloquea main thread (tests fallando)
  2. Crear `PlaybackHealthChecker` actor para verificaciones de estado asíncronas
  3. Implementar métodos async para verificar estado de ventanas y bookmarks
  4. Refactorizar ensurePlaying para llamar a PlaybackHealthChecker de forma asíncrona
  5. Eliminar verificaciones síncronas y reemplazar con Task { await check() }
  6. Ejecutar tests y verificar que pasan sin bloqueos

### 6. Phase 6: Eliminar `RunLoop.current.run()` Bloqueante en `createDesktopWindows`
- **Objetivo:** Eliminar el bloqueo explícito de RunLoop de 20ms por pantalla y usar coordinación asíncrona para creación de ventanas
- **Archivos a Modificar/Crear:**
  - `LiveWalls/WallpaperManager.swift` (modificar `createDesktopWindows`)
  - `LiveWalls/WindowCreationCoordinator.swift` (nuevo)
- **Tests a Escribir:**
  - `testCreateDesktopWindowsDoesNotBlockRunLoop`
  - `testWindowCreationCoordinatorCreatesWindowsAsync`
  - `testMultipleScreenWindowCreationIsNonBlocking`
- **Pasos:**
  1. Escribir tests que verifiquen creación de ventanas sin RunLoop.run (tests fallando)
  2. Crear `WindowCreationCoordinator` que coordine creación asíncrona de ventanas
  3. Implementar await Task.yield() en lugar de RunLoop.run para dar tiempo al sistema
  4. Actualizar createDesktopWindows para usar WindowCreationCoordinator
  5. Eliminar todas las llamadas a RunLoop.current.run()
  6. Ejecutar tests y verificar eliminación de bloqueos de RunLoop

### 7. Phase 7: Optimizar Verificaciones Post-Arranque Programadas
- **Objetivo:** Optimizar las verificaciones programadas con DispatchQueue.main.asyncAfter (1s, 3s) para que no saturen el main thread
- **Archivos a Modificar/Crear:**
  - `LiveWalls/WallpaperManager.swift` (modificar `startWallpaperSafe`)
  - `LiveWalls/ScheduledHealthCheckManager.swift` (nuevo)
- **Tests a Escribir:**
  - `testScheduledHealthChecksRunInBackground`
  - `testHealthCheckManagerDoesNotSaturateMainThread`
  - `testHealthChecksCanBeCancelled`
- **Pasos:**
  1. Escribir tests para ScheduledHealthCheckManager con verificaciones background (tests fallando)
  2. Crear `ScheduledHealthCheckManager` que ejecute verificaciones en background queue
  3. Implementar scheduling con Task.sleep en lugar de DispatchQueue.main.asyncAfter
  4. Migrar verificaciones post-arranque a ScheduledHealthCheckManager
  5. Actualizar startWallpaperSafe para usar el nuevo manager
  6. Ejecutar tests y verificar optimización de scheduling

### 8. Phase 8: Pruebas de Integración y Validación de Performance
- **Objetivo:** Crear tests de integración end-to-end que validen que el arranque completo no bloquea el main thread y medir mejoras de performance
- **Archivos a Modificar/Crear:**
  - `LiveWallsTests/StartupPerformanceTests.swift` (nuevo)
  - `LiveWallsTests/MainThreadBlockingTests.swift` (nuevo)
- **Tests a Escribir:**
  - `testFullStartupDoesNotBlockMainThread`
  - `testStartupTimeUnder200ms`
  - `testNoMainThreadBlockingDuringAutoStart`
  - `testBackgroundTasksCompleteWithinTimeout`
- **Pasos:**
  1. Crear tests de performance que midan tiempo total de arranque (baseline actual 6-12s)
  2. Implementar tests que detecten bloqueos del main thread usando XCTWaiter
  3. Crear test de integración completo que simule arranque completo con auto-start
  4. Ejecutar tests y establecer baseline de performance
  5. Validar que mejoras reducen tiempo a <200ms como objetivo
  6. Documentar mejoras de performance y actualizar AGENTS.md con resultados

**Preguntas Abiertas:**
1. ✅ Actors en archivos separados para mejor modularidad
2. ✅ Agregar logging de performance durante arranque
3. ✅ Objetivo de <200ms es aceptable
4. ✅ Mantener transparente al usuario, sin UI de loading adicional
