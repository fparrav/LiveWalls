## Phase 6 Complete: Eliminar `RunLoop.current.run()` Bloqueante en `createDesktopWindows`

Eliminado el bloqueo explícito de RunLoop de 20ms por pantalla, reemplazándolo con coordinación asíncrona usando Task.yield() para dar tiempo al sistema sin bloquear el main thread.

**Files created/changed:**
- LiveWalls/WindowCreationCoordinator.swift (created, 142 lines)
- LiveWallsTests/WindowCreationCoordinatorTests.swift (created, 108 lines)
- LiveWalls/WallpaperManager.swift (modified - refactored createDesktopWindows to async)
- LiveWalls.xcodeproj/project.pbxproj (modified - added new files to target)

**Functions created/changed:**
- `WindowCreationCoordinator.createWindowsAsync(screens:videoFile:bookmarkActor:) async -> [NSWindow]` - Async window creation
- `WallpaperManager.createDesktopWindows() async` - Converted to async method
- `WallpaperManager.startWallpaperSafe()` - Updated to await createDesktopWindows
- `WallpaperManager.didWake()` - Updated to await createDesktopWindows
- `WallpaperManager.changeToNextVideoWithTransition()` - Updated to await createDesktopWindows

**Tests created/changed:**
- `testCreateDesktopWindowsDoesNotBlockRunLoop` - Verifies no RunLoop blocking (PASSED)
- `testWindowCreationCoordinatorCreatesWindowsAsync` - Verifies async creation (PASSED)
- `testMultipleScreenWindowCreationIsNonBlocking` - Verifies multi-screen non-blocking (PASSED)

**Review Status:** APPROVED - All tests passing, RunLoop blocking eliminated

**Git Commit Message:**
```
feat: Agregar WindowCreationCoordinator para creación asíncrona de ventanas

- Crear actor WindowCreationCoordinator para coordinación sin bloquear RunLoop
- Reemplazar RunLoop.current.run() con await Task.yield() por pantalla
- Convertir createDesktopWindows a método async
- Eliminar bloqueo de 20ms por pantalla durante creación de ventanas
- Añadir suite de 3 tests unitarios verificando no-bloqueo y async execution
- Todos los tests pasan exitosamente (3/3)
- Actualizar llamadas en startWallpaperSafe, didWake y changeToNextVideoWithTransition
```
