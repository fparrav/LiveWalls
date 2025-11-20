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

### Arquitectura de UI
- Basada en SwiftUI con integración AppKit
- **ContentView**: Interfaz principal con grid de videos y controles
- **StatusBarMenuView**: Controles de barra de menú para operación en segundo plano
- **SettingsView**: Panel de configuración de preferencias
- **LaunchManager**: Gestiona comportamiento de inicio y auto-lanzamiento

## Project Structure & Module Organization

- `LiveWalls/`: Código fuente Swift/SwiftUI (App, managers, views).
- `LiveWallsTests/`, `LiveWallsUITests/`: Pruebas unitarias y de UI con XCTest.
- `LiveWalls/Assets.xcassets/`: Iconos e imágenes. `LiveWalls/Resources/Localizations/`: cadenas localizadas.
- Scripts: `build.sh`, `scripts/` (release y utilidades), `homebrew/` (fórmula).


### CLI & Build commands (copied from GEMINI.md)
- **Build Debug:** `./build.sh build` o `xcodebuild build -project LiveWalls.xcodeproj -scheme LiveWalls`
- **Run app:** `./build.sh run` (streams logs to terminal)
- **Clean build:** `./build.sh clean`
- **Archive release:** `./build.sh archive`
- **Open in Xcode:** `open LiveWalls.xcodeproj`

### Release Automation
- **CI:** Uses GitHub Actions workflow defined at `.github/workflows/release.yml`
- On tagging `v*.*.*` the workflow builds the app, creates a `.dmg`, generates a changelog with `git-cliff`, and creates a GitHub release.


## Build, Test, and Development Commands
- `LiveWalls/`: Código fuente Swift/SwiftUI (App, managers, views).
- `LiveWallsTests/`, `LiveWallsUITests/`: Pruebas unitarias y de UI con XCTest.
- `LiveWalls/Assets.xcassets/`: Iconos e imágenes. `LiveWalls/Resources/Localizations/`: cadenas localizadas.
- Scripts: `build.sh`, `scripts/` (release y utilidades), `homebrew/` (fórmula).

## Build, Test, and Development Commands
- Build debug: `./build.sh build` o `xcodebuild build -project LiveWalls.xcodeproj -scheme LiveWalls`.
- Run local: `./build.sh run` (compila y lanza la app mostrando logs).
- Clean: `./build.sh clean`.
- Tests: `./build.sh test` (ejecuta UI tests; unit tests requieren ejecución de scheme en Xcode con Cmd+U).
- Archive: `./build.sh archive` (Release `.xcarchive`).
- Abrir en Xcode: `open LiveWalls.xcodeproj`.

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

### Actualizador (Sparkle)
- Sparkle se integra vía SPM; el wrapper `InAppUpdater` usa `SPUStandardUpdaterController`.
- Configura `SUFeedURL` y `SUPublicEDKey` en `LiveWalls/Info.plist`.
- Nunca commitees la clave privada. Usa el secreto `SPARKLE_PRIVATE_KEY` en GitHub Actions.
- `.gitignore` ignora `private_eddsa.pem`, `ed25519_*.pem`, `public/` y `*.tar.xz`.

## Bug Tracking: Auto‑reproducción tras reinicio no inicia

- Estado: abierto (Issue creado: ver GitHub “Bug: Tras reiniciar, la app inicia pero el wallpaper no se reproduce automáticamente”). No cerrar hasta confirmar en build.
- Síntoma: al iniciar sesión después de reiniciar, la app se lanza pero el wallpaper no comienza; requiere presionar “Reproducir wallpaper”.

### Hipótesis (posibles causas)
- Arranque temprano tras login: pantallas/Spaces no estabilizados cuando corre `attemptAutoStart()`.
- Resolución de bookmarks: `startAccessingSecurityScopedResource()` puede fallar muy temprano o sin reintentos.
- Restauración de estado: no se persiste si el wallpaper estaba activo al salir; sólo depende de `AutoStartWallpaper`.
- Orden/z‑level de ventana: capa por debajo del escritorio de Finder en el arranque; requiere reordenar/recrear.
- Orden de inicialización: `WallpaperManager` auto‑arranca antes de que la sesión esté “activa” (Finder/Dock listos).

### Plan de trabajo (tareas atómicas y ordenadas)
1) Instrumentación de arranque: logs detallados
   - Añadir logs con causa en `attemptAutoStart()`, `waitForSystemReadiness()`, `startWallpaperSafe()` (marcar: pantallas, Space, bookmark resuelto, nº de ventanas creadas).
   - Aceptación: logs muestran claramente por qué no se inicia.

2) Gate de “sesión lista” y reintentos
   - Añadir observadores de `NSApplication.didBecomeActive`, `NSWorkspace.sessionDidBecomeActive` (si aplica) y reintento si `!isPlayingWallpaper`.
   - Añadir reintento con backoff si tras `startWallpaperSafe()` `desktopVideoInstances.isEmpty` en 1–2s.
   - Aceptación: tras login, si el primer intento falla, se reintenta y arranca sin intervención.

3) Persistir/usar “estaba reproduciendo”
   - Guardar `wasPlayingAtShutdown` en `willTerminate` y auto‑reproducir al lanzar si true, incluso si `AutoStartWallpaper` está off (opción separada en ajustes “Reanudar última sesión”).
   - Aceptación: si estaba reproduciendo antes de reiniciar, arranca solo.

4) Pre‑resolución robusta de bookmark
   - En `attemptAutoStart()`, pre‑resolver bookmark del `currentVideo` y, si falla, reintentar luego de 1–2s o notificar al usuario.
   - Aceptación: no hay fallos silenciosos por bookmark temprano.

5) Verificar y ajustar z‑level de ventana
   - Probar `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)` en lugar de `.desktopWindow - 1` y reordenar tras login.
   - Aceptación: las ventanas son visibles por encima del wallpaper del sistema y debajo de los íconos.

6) Reaplicación tardía de wallpaper estático
   - Si `setSystemStaticWallpaper` falla al primer intento, reintentar a 0.5s y 2s; ya existe lógica similar, verificar cobertura en login.
   - Aceptación: frame estático se aplica tras login en todos los Spaces.

7) Pruebas y verificación manual
   - Añadir un “Debug > Forzar verificación de estado” ya existente a menú para recolectar estado después de login.
   - Escribir test unitario para persistencia de `wasPlayingAtShutdown` y carga de `currentVideo`.
   - Checklist manual: activar “iniciar al login”, reiniciar y validar auto‑inicio sin intervención.

### Priorización (MVP -> Nice‑to‑have)
- MVP: (1) Instrumentación, (2) Gate + reintentos, (3) Persistencia estado.
- Secundario: (4) Bookmarks robustos, (5) z‑level verificación, (6) reintentos wallpaper estático, (7) pruebas.
