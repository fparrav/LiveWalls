# Repository Guidelines

Este documento guía a contribuidores del proyecto LiveWalls.

## Project Overview

LiveWalls es una aplicación nativa de macOS para usar videos como fondos de pantalla dinámicos. Construida con Swift/SwiftUI, permite a los usuarios establecer videos MP4/MOV como fondos de escritorio con escalado inteligente, soporte multi-monitor y ejecución en segundo plano. Requiere macOS 13.0+, Xcode 15.0+ y Swift 5.7+.

## Core Components

### Componentes Principales

1. **WallpaperManager** (`WallpaperManager.swift`)
   - Gestor central de funcionalidad de fondos de video
   - Maneja archivos de video, bookmarks con alcance de seguridad y creación de ventanas
   - Operaciones thread-safe con colas concurrentes y semáforos
   - Gestiona recursos de AVFoundation y limpieza de memoria

2. **DesktopVideoWindowMejorada** (`DesktopVideoWindowMejorada.swift`)
   - Subclase NSWindow personalizada para reproducción de video en escritorio
   - Maneja soporte multi-pantalla y renderizado de video
   - Gestiona ciclo de vida de ventana y limpieza de recursos

3. **VideoFile** (`VideoFile.swift`)
   - Modelo que representa archivos de video con metadatos
   - Contiene datos de bookmarks con alcance de seguridad para acceso de archivos
   - Incluye generación de miniaturas y persistencia

4. **BookmarkActor** (`BookmarkActor.swift`)
   - Actor para gestión segura de bookmarks con alcance de seguridad
   - Maneja inicio/detención de acceso a recursos con permisos de sandbox

5. **PersistenceActor** (`PersistenceActor.swift`)
   - Actor para operaciones de persistencia thread-safe
   - Gestiona guardado/carga de configuración y estado de la app

6. **VideoPreloader** (`VideoPreloader.swift`)
   - Sistema de precarga de videos para transiciones fluidas
   - Cachea el siguiente video en la cola para eliminar delays

7. **WindowCreationCoordinator** (`WindowCreationCoordinator.swift`)
   - Coordina creación asíncrona de ventanas para múltiples pantallas
   - Optimiza tiempo de inicio y transiciones

8. **TransitionManager** (`TransitionManager.swift`)
   - Gestiona transiciones visuales entre videos (crossfade)
   - Controla animaciones y timing de transiciones

9. **StartupCoordinator** (`StartupCoordinator.swift`)
   - Coordina secuencia de inicio de la aplicación
   - Maneja dependencias y sincronización al arrancar

10. **PlaybackHealthChecker** (`PlaybackHealthChecker.swift`)
    - Monitorea salud de reproducción de video
    - Detecta y reporta problemas de playback

11. **ThrottleManager** (`ThrottleManager.swift`)
    - Actor para throttling y debouncing de eventos frecuentes
    - Previene ejecuciones excesivas de handlers en eventos repetidos
    - Usado para optimizar Space changes y notificaciones del sistema

12. **BackgroundColorWindow** (`BackgroundColorWindow.swift`)
    - NSWindow para mostrar fondo de color durante transiciones
    - Crea efecto crossfade suave entre videos
    - Maneja z-ordering para transiciones visuales

13. **NotificationManager** (`NotificationManager.swift`)
    - Gestiona notificaciones del sistema (NSWorkspace, NSScreen)
    - Coordina respuesta a cambios de Space, pantallas y fullscreen
    - Centraliza observers de eventos del sistema

14. **WallpaperTimerManager** (`WallpaperTimerManager.swift`)
    - Gestiona timer para cambio automático de videos
    - Maneja scheduling y cancelación de cambios programados
    - Integra con sistema de auto-change de wallpapers

15. **ScheduledHealthCheckManager** (`ScheduledHealthCheckManager.swift`)
    - Programa verificaciones periódicas de salud de reproducción
    - Ejecuta health checks en intervalos configurables
    - Detecta y recupera de estados de reproducción degradados

16. **SystemReadinessObserver** (`SystemReadinessObserver.swift`)
    - Observa disponibilidad de pantallas y Spaces del sistema
    - Detecta cuando el sistema está listo para operaciones de wallpaper
    - Previene operaciones prematuras durante arranque

17. **FullscreenDetector** (`FullscreenDetector.swift`)
    - Detecta cuando hay aplicaciones en modo fullscreen
    - Permite ajustar comportamiento según contexto de pantalla completa
    - Optimiza recursos cuando fullscreen apps están activas

18. **VideoOptimizer** (`VideoOptimizer.swift`)
    - Optimiza configuración de video playback
    - Gestiona ajustes de rendimiento para AVPlayer
    - Balancea calidad vs. uso de recursos

19. **AppDelegate** (`AppDelegate.swift`)
    - Maneja eventos del ciclo de vida de la aplicación
    - Coordina terminación limpia y cleanup de recursos
    - Integra con sistema de notificaciones y eventos macOS

### Arquitectura de UI
- Basada en SwiftUI con integración AppKit
- **ContentView**: Interfaz principal con grid de videos y controles
- **StatusBarMenuView**: Controles de barra de menú para operación en segundo plano
- **SettingsView**: Panel de configuración de preferencias
- **AboutView**: Pantalla de información de la aplicación
- **LaunchManager**: Gestiona comportamiento de inicio y auto-lanzamiento

## Project Structure & Module Organization

- `LiveWalls/`: Código fuente Swift/SwiftUI (App, managers, views)
- `LiveWallsTests/`, `LiveWallsUITests/`: Pruebas unitarias y de UI con XCTest
- `LiveWalls/Assets.xcassets/`: Iconos e imágenes
- `LiveWalls/Resources/Localizations/`: Cadenas localizadas (10 idiomas soportados)
- Scripts: `build.sh`, `scripts/` (release y utilidades), `homebrew/` (fórmula)

## Build, Test, and Development Commands

### Building
- **Build Debug:** `./build.sh build` o `xcodebuild build -project LiveWalls.xcodeproj -scheme LiveWalls`
- **Run app:** `./build.sh run` (compila y lanza mostrando logs en terminal)
- **Clean build:** `./build.sh clean`
- **Archive release:** `./build.sh archive`
- **Open in Xcode:** `open LiveWalls.xcodeproj`

### Testing
- **Run tests:** `./build.sh test` (ejecuta UI tests)
- **Unit tests:** Ejecutar scheme en Xcode con Cmd+U
- **Test coverage:** Disponible en `build/DerivedData/Logs/Test/`

### Release Automation
- **CI/CD:** GitHub Actions workflow en `.github/workflows/release.yml`
- **Release trigger:** Al crear tag `v*.*.*` se construye la app, genera `.dmg`, changelog con `git-cliff` y crea GitHub release

## Coding Style & Naming Conventions
- Lenguaje: Swift. Código y comentarios en inglés; documentación en español.
- Estructuras para modelos (por ejemplo `VideoFile`), clases para managers (por ejemplo `WallpaperManager`).
- Estilo Swift estándar, 4 espacios, sin tabs; usa el formateador de Xcode.
- Nombres en inglés en `lowerCamelCase` (métodos/propiedades) y `UpperCamelCase` (tipos). Archivos < 500 líneas cuando sea posible.

## Testing Guidelines
- Framework: XCTest. Coloca pruebas en `LiveWallsTests/` y `LiveWallsUITests/` con sufijo `Tests`.
- Casos clave: multi‑monitor, limpieza de recursos (AVPlayer/NSWindow), bookmarks con alcance de seguridad, recreación de ventanas al cambiar pantallas.
- Ejecuta: `./build.sh test`. Cobertura en `build/DerivedData/Logs/Test/` si está disponible.

## Commit & Pull Request Guidelines
- Mensajes de commit en español; formato convencional cuando aplique (`feat:`, `fix:`, `docs:`...). No menciones ni atribuyas a herramientas de IA.
- Incluye descripción clara, pasos de prueba, y referencia a issue si procede. Adjunta capturas o GIFs para cambios visibles.
- Un PR debe mantener CI verde, incluir/actualizar pruebas, y limitar el alcance a una mejora o corrección por PR.
- Enfoque técnico: describe el cambio realizado, no la herramienta utilizada para implementarlo.

## Security & Architecture Tips
- Acceso a archivos: usa bookmarks con alcance de seguridad y resuélvelos con `resolveBookmark(for:)`; inicia y detén el acceso de forma segura.
- Concurrencia: operaciones de wallpaper en `wallpaperOperationQueue`/actor; UI siempre en el main thread (`@MainActor`).
- Recursos: libera `AVPlayer`, `AVPlayerLayer` y ventanas al detener o cambiar videos para evitar fugas.
- Multi‑pantalla: crea una ventana por `NSScreen` y maneja cambios de pantallas.

### Resource Management (Gestión de Recursos)
- Siempre usa bookmarks con alcance de seguridad para acceso a archivos
- Libera correctamente recursos de AVFoundation (players, layers, assets)
- Usa colas concurrentes con semáforos para thread-safety
- Rastrea y limpia ventanas de escritorio al terminar la app
- Implementa weak references en closures para evitar ciclos de retención

### Concurrency (Concurrencia)
- WallpaperManager usa `wallpaperOperationQueue` para operaciones thread-safe
- Las actualizaciones de UI deben ocurrir en la cola principal
- El rastreo de recursos usa una cola concurrente con barriers
- Las operaciones de wallpaper se ejecutan en colas dedicadas fuera del main thread
- Usa concurrency gates (`isEnsurePlayingRunning`) para prevenir ejecuciones concurrentes
- Implementa rate limiting con timestamps para funciones frecuentemente llamadas

### Performance Optimizations (Optimizaciones de Rendimiento)
- **Throttling/Debouncing**: ThrottleManager maneja eventos frecuentes (Space changes, notificaciones)
- **Caching**: BookmarkActor cachea resoluciones de bookmarks; VideoPreloader cachea AVAssets
- **Lazy Loading**: WindowCreationCoordinator crea ventanas asíncronamente sin bloquear main thread
- **Resource Pooling**: Reutiliza assets precargados para transiciones instantáneas
- **Concurrency Control**: Gates y rate limiting en funciones críticas como `ensurePlaying()`

### Actualizador (Sparkle)
- Sparkle se integra vía SPM; el wrapper `InAppUpdater` usa `SPUStandardUpdaterController`.
- Configura `SUFeedURL` y `SUPublicEDKey` en `LiveWalls/Info.plist`.
- Nunca commitees la clave privada. Usa el secreto `SPARKLE_PRIVATE_KEY` en GitHub Actions.
- `.gitignore` ignora `private_eddsa.pem`, `ed25519_*.pem`, `public/` y `*.tar.xz`.

## Known Issues

### Auto-start tras reinicio no funciona consistentemente
- **Estado:** Abierto
- **Síntoma:** Al iniciar sesión después de reiniciar, la app se lanza pero el wallpaper no comienza automáticamente; requiere presionar "Reproducir wallpaper" manualmente.
- **Métodos relevantes:** `attemptAutoStart()`, `startWallpaperSafe()` en `WallpaperManager.swift`
- **User defaults:** `AutoStartWallpaper` controla si el auto-inicio está habilitado
- **Posibles causas:**
  - Arranque temprano tras login: pantallas/Spaces no estabilizados cuando corre `attemptAutoStart()`
  - Resolución de bookmarks: `startAccessingSecurityScopedResource()` puede fallar muy temprano
  - No se persiste estado de reproducción al salir
  - Orden/z-level de ventana incorrecto al arranque
- **Mitigaciones implementadas:**
  - SystemReadinessObserver detecta cuando sistema está listo
  - BookmarkActor cachea resoluciones para reducir fallos
  - StartupCoordinator coordina secuencia de inicio con dependencias

## Recent Performance Improvements

### Phases 1-5 Optimizations (Nov 2025)
Completadas optimizaciones significativas que eliminan operaciones redundantes y mejoran responsividad:

1. **Phase 1** (Commit 23f37b5): Eliminadas aplicaciones redundantes de wallpaper estático
   - Reducción 85% (7→1 aplicaciones por cambio de Space)

2. **Phase 2** (Commit 37da42b): Throttling para cambios de Space
   - Reducción 83% (12→2 reactivaciones por cambio)
   - Implementado ThrottleManager para eventos frecuentes

3. **Phase 3** (Commit 263c296): Caching de resoluciones de bookmarks
   - Reducción 67% (3→1 resoluciones, 2 cache hits)

4. **Phase 4** (Commit 0ed7b5d): Caching de AVAssets para creación rápida de ventanas
   - Reducción 97% esperada (18s→<500ms cuando precargado)
   - VideoPreloader retorna assets completamente cargados

5. **Phase 5** (Commit 80bc47b): Concurrency gate y rate limiting en ensurePlaying()
   - Elimina race conditions causando "0 playing windows"
   - 500ms rate limiting entre llamadas

**Impacto general:** Reducción significativa en CPU usage, memory churn y bloqueos de UI durante cambios de Space y transiciones de video.

### Video Playback Stability Fixes (Nov 2025)
Plan comprehensivo de 7 fases para eliminar congelamientos aleatorios y parpadeos en cambios de Space (Issue #24):

**✅ COMPLETADAS (7/7) - Plan finalizado exitosamente**

1. **Phase 1** (Commit e3fbc46): Auditoría de arquitectura de playback
   - Documentados 8 failure points (4 críticos)
   - Baseline de métricas de rendimiento establecido
   - Tests de auditoría: PlaybackArchitectureAuditTests.swift (8 tests)

2. **Phase 2** (Commit f7e7adb): AVQueuePlayer + AVPlayerLooper
   - Reemplazado AVPlayer manual looping con AVQueuePlayer
   - Eliminados 3 observers de looping manual
   - Beneficios: Seek glitches eliminados, arquitectura más robusta
   - Tests: AVQueuePlayerLoopingTests.swift (7 tests)

3. **Phase 3** (Commit f202c6a): Reutilización de ventanas en cambios de Space
   - Implementada lógica de reuso de ventanas (health check → reuse vs recreate)
   - Agregados métodos: `isHealthy()`, `updateForSpace()`, `areCurrentWindowsHealthy()`
   - Beneficios: 50-75% reducción en recreaciones, flickers eliminados
   - Tests: WindowRecreationTests.swift (7 tests)

4. **Phase 4** (Commit bef221f): Limpieza diferida de recursos durante transiciones
   - Aumentado `resourceReleaseDelay` de 0.1s a 2.5s
   - Agregado callback `onTransitionComplete` en TransitionManager
   - Beneficios: Frame drops durante crossfade eliminados, smooth 60 FPS mantenido
   - Tests: TransitionTimingTests.swift (6 tests)

5. **Phase 5** (Commit 92e63d2): Simplificación de z-ordering y window levels
   - Corregida inconsistencia de window level en `updateForSpace()`
   - Uso consistente de `kCGDesktopIconWindowLevel - 1` en creación y actualización
   - Beneficios: Z-ordering consistente, ventanas siempre en nivel correcto
   - Tests: WindowLevelTests.swift (6 tests)

6. **Phase 6** (Commit c061f4e): Optimización de gestión de estado de player
   - Agregado `getTimeControlStatus()` para detección precisa de stalls
   - PlaybackHealthChecker usa timeControlStatus como indicador primario
   - Rate limiting aumentado de 500ms a 2.0s (75% reducción)
   - Health check intervals aumentados de 60s a 120s (50% reducción)
   - Beneficios: CPU usage reducido, detección de stalls más precisa
   - Tests: PlaybackHealthCheckerTests actualizados (6 tests + 3 nuevos)

7. **Phase 7** (Commit 840264d): Tests de integración y telemetría
   - Creado PlaybackTelemetry actor para monitoring de métricas
   - 5 tests de integración end-to-end para validación completa
   - Tracking de stalls, recreaciones, frame drops, health checks
   - Beneficios: Visibilidad completa de salud de playback, detección de regresiones
   - Tests: 5 integration tests en PlaybackHealthCheckerTests.swift

**Impacto acumulado:**
- ✅ Seek glitches eliminados (Phase 2)
- ✅ 50-75% reducción en recreaciones de ventanas (Phase 3)
- ✅ Frame drops durante transiciones eliminados (Phase 4)
- ✅ Z-ordering consistente (Phase 5)
- ✅ 75% reducción en health checks (Phase 6)
- ✅ Monitoring comprehensivo y tests de integración (Phase 7)
- ✅ 94 tests pasando, 0 fallos
- ✅ Playback estable sin freezes ni parpadeos

**Componentes nuevos agregados:**
- PlaybackHealthChecker: Actor para health checks asíncronos
- ScheduledHealthCheckManager: Programación de chequeos en background
- PlaybackTelemetry: Tracking de métricas de producción
- Tests: 34 nuevos tests, cobertura completa de stability fixes
