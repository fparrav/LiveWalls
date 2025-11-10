## Plan: Estabilizar UI Tests LiveWalls

Plan para estabilizar y robustecer los UI tests: añadiremos localización mínima y accessibility identifiers, adaptaremos los tests a identificadores con esperas fiables, activaremos política de ventana adecuada en modo pruebas, re‑habilitaremos el target de UI tests y ampliaremos cobertura básica, siguiendo TDD en fases.

**Phases 5**
1. **Phase 1: Localización base + Identifiers críticos**
    - **Objective:** Incorporar claves esenciales de localización (es/en) y añadir accessibility identifiers a botones y elementos fundamentales en `ContentView` y acciones principales de `SettingsView`.
    - **Files/Functions to Modify/Create:** `LiveWalls/ContentView.swift`, `LiveWalls/SettingsView.swift`, `LiveWalls/es.lproj/Localizable.strings`, `LiveWalls/en.lproj/Localizable.strings`.
    - **Tests to Write:** `testToolbarButtonsExistByIdentifier`, `testBottomControlsExistByIdentifier`.
    - **Steps:**
        1. Escribir tests nuevos referenciando IDs planeados (deben fallar inicialmente).
        2. Añadir `.accessibilityIdentifier` a botones Importar, Configuración, Reproducir/Detener, Establecer como wallpaper, Eliminar, botón de estado vacío, y título.
        3. Añadir claves mínimas de localización en es/en para los textos visibles usados.
        4. Ejecutar tests y verificar que pasan.

2. **Phase 2: Refactor UI tests a identifiers + waits**
    - **Objective:** Reemplazar dependencia de textos localizados por identifiers y eliminar `sleep()` usando `waitForExistence` y helpers.
    - **Files/Functions to Modify/Create:** `LiveWallsUITests/ContentViewUITests.swift`, helper `LiveWallsUITests/XCUIElement+Waits.swift`.
    - **Tests to Write:** `testOpensSettingsViaIdentifier`, `testImportButtonInteractionByIdentifier`, `testPlayStopTogglePresenceByIdentifier`.
    - **Steps:**
        1. Escribir y ajustar tests a IDs + esperas (fallan si faltan helpers).
        2. Implementar helper de espera y aplicar en tests.
        3. Eliminar `sleep()` y verificaciones por texto.
        4. Ejecutar suite y validar verde.

3. **Phase 3: Activación app en modo UI tests**
    - **Objective:** Detectar argumento `-UITests` y asegurar `NSApp.setActivationPolicy(.regular)` y ventana principal visible/activa durante las pruebas.
    - **Files/Functions to Modify/Create:** `LiveWalls/LiveWallsApp.swift` o `LiveWalls/AppDelegate.swift` (lógica condicional).
    - **Tests to Write:** `testMainWindowBecomesKeyAndVisible`, `testAppActivationPolicyRegularInUITests`.
    - **Steps:**
        1. Añadir tests que validen la ventana principal (fallarán primero).
        2. Implementar detección de argumento y activación de ventana.
        3. Re‑ejecutar pruebas hasta que pasen.
        4. Validar que en modo normal se mantiene `.accessory`.

4. **Phase 4: Re‑habilitar esquema UI tests y firma**
    - **Objective:** Re‑añadir el bundle de UI tests al esquema, asegurar Info.plist y firma automática, y validar ejecución por `xcodebuild`.
    - **Files/Functions to Modify/Create:** `LiveWalls.xcodeproj/xcshareddata/xcschemes/LiveWalls.xcscheme` y ajustes mínimos en `project.pbxproj` si fueran necesarios.
    - **Tests to Write:** Verificación de ejecución de UI tests vía `xcodebuild` (script de validación local/CI).
    - **Steps:**
        1. Re‑incluir el testable UI en el esquema.
        2. Verificar Info.plist generado y firma automática del bundle UI tests.
        3. Ejecutar UI tests por CLI y confirmar estabilidad.

5. **Phase 5: Cobertura adicional (persistencia + settings)**
    - **Objective:** Validar persistencia de ajustes (mute, auto‑start) tras relanzar y visibilidad de toggles de transiciones.
    - **Files/Functions to Modify/Create:** Nuevos casos en `LiveWallsUITests/` (posible `SettingsPersistenceUITests.swift`).
    - **Tests to Write:** `testMutePersistsAfterRelaunch`, `testAutoStartSettingPersists`, `testTransitionToggleVisibility`.
    - **Steps:**
        1. Añadir tests que relancen la app usando `launchArguments`.
        2. Limpiar/restaurar `UserDefaults` con argumento `-resetUserDefaults` si aplica.
        3. Ejecutar y confirmar persistencia.

**Open Questions**
1. Localización: se usará localización mínima para es/en centrada en textos críticos de UI.
2. Importación: los UI tests no interactuarán con el panel real; se centrará en existencia/activación de controles (sin importar archivos reales).
3. Idioma de tests: se prioriza usar identifiers, por lo que no dependerán del idioma; si hace falta, se fijará `en` para entornos CI.
4. Persistencia: se limpiará `UserDefaults` entre tests mediante argumento `-resetUserDefaults` cuando se requiera.
5. Documentación: el `TESTING_GUIDE.md` se añadirá al finalizar, no en la Fase 1.

---

## Estado de Implementación

### Phase 1: ⚠️ NEEDS_REVISION - Pendiente de corrección

**Completado:**
- ✅ Accessibility identifiers añadidos en `ContentView.swift` (7 identificadores)
- ✅ Accessibility identifiers añadidos en `SettingsView.swift` (2 identificadores)
- ✅ Nuevos tests UI creados: `testToolbarButtonsExistByIdentifier`, `testBottomControlsExistByIdentifier`
- ✅ Tests nuevos usan `waitForExistence` sin `sleep()`
- ✅ Unit tests permanecen en verde (47/49 pasando, 2 skipped esperados)

**Pendiente de Corrección:**
- ❌ **CRÍTICO**: Las claves de localización se añadieron a archivos huérfanos (`LiveWalls/es.lproj/Localizable.strings` y `LiveWalls/en.lproj/Localizable.strings`) en lugar de los archivos correctos en `LiveWalls/Resources/Localizations/es.lproj/Localizable.strings` y `LiveWalls/Resources/Localizations/en.lproj/Localizable.strings`
- ⚠️ **Acción requerida**: Eliminar archivos huérfanos y verificar que los archivos correctos contienen todas las claves necesarias (aparentemente ya las tienen)
- ⚠️ UI tests no ejecutables actualmente (target no habilitado en scheme - planeado para Phase 4)

**Archivos Modificados:**
- `LiveWalls/ContentView.swift` (+7 identificadores)
- `LiveWalls/SettingsView.swift` (+2 identificadores)
- `LiveWalls/es.lproj/Localizable.strings` (⚠️ archivo huérfano, debe eliminarse)
- `LiveWalls/en.lproj/Localizable.strings` (⚠️ archivo huérfano, debe eliminarse)
- `LiveWallsUITests/ContentViewUITests.swift` (+2 tests nuevos)

### Phases 2-5: Not Started

Las fases restantes esperan la corrección de Phase 1 antes de proceder.
