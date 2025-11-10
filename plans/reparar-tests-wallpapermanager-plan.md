## Plan: Reparar tests de WallpaperManager

Corregiremos dos fallos en la suite LiveWallsTests ajustando expectativas y precondiciones de los tests para que reflejen la lógica actual de `WallpaperManager` sin aflojar coberturas.

**Phases 3**
1. **Phase 1: Ajustes de tests**
    - **Objetivo:** Corregir `testAddVideoFiles` (nombre derivado) y `testCanGoToNextWallpaper` (precondiciones) en `LiveWallsTests/WallpaperManagerTests.swift`.
    - **Archivos/Funciones:** `WallpaperManagerTests.testAddVideoFiles`, `WallpaperManagerTests.testCanGoToNextWallpaper`.
    - **Tests a escribir/cambiar:** Actualizar expectativas y estados; no se agregan nuevos tests.
    - **Steps:**
        1. Cambiar expectativa de nombre a `video-test` (archivo temporal creado).
        2. Establecer `isAutoChangeEnabled = true` y ambos videos habilitados para la primera aserción; deshabilitar para la segunda.
2. **Phase 2: Ejecución**
    - **Objetivo:** Ejecutar únicamente `WallpaperManagerTests` y confirmar verde (con skips esperados en E2E).
    - **Steps:**
        1. Correr `xcodebuild` filtrando `WallpaperManagerTests` y revisar salida.
3. **Phase 3: Revisión y Commit**
    - **Objetivo:** Validar que los cambios son mínimos y coherentes; preparar mensaje de commit.
    - **Steps:**
        1. Revisar diffs y resultados; proponer commit convencional.

**Open Questions**
1. ¿Quieres reactivar UI tests en scheme tras resolver firma? (ahora están excluidos)
2. ¿Mantenemos `VideoOptimizerTests` excluido hasta reconstruir sus helpers?
