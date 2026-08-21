import XCTest
    
    // MARK: - XCUIElement Wait Helper Extension
    extension XCUIElement {
        /// Waits for the element to exist and be hittable with a default timeout
        @discardableResult
        func waitForExistenceAndHittable(timeout: TimeInterval = 3.0) -> Bool {
            return self.waitForExistence(timeout: timeout) && self.isHittable
        }
    }
    
    final class ContentViewUITests: XCTestCase {
        var app: XCUIApplication!
        
        override func setUp() {
            super.setUp()
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["-UITests"]
            app.launch()
        }
        
        /// Reveals the glass library rail on the right side of the main window
        /// if it is not visible yet, by tapping the floating library toggle.
        @discardableResult
        func revealLibraryRailIfNeeded() -> XCUIElement {
            // The rail starts hidden; check whether it is already visible before toggling.
            if !app.buttons["library_import_button"].waitForExistence(timeout: 0.5) {
                let libraryToggle = app.buttons["main_library_toggle_button"]
                XCTAssertTrue(libraryToggle.waitForExistence(timeout: 3), "El botón para revelar la biblioteca debería existir")
                libraryToggle.tap()
            }
            
            let rail = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'library_rail'"))
                .firstMatch
            XCTAssertTrue(rail.waitForExistence(timeout: 3), "El contenedor 'library_rail' debería existir")
            return rail
        }
        
        /// Ensures the auto-change switch on the bottom glass bar is on, which is
        /// required for the interval and playback-mode pickers to become visible.
        func ensureAutoChangeEnabled() {
            let autochangeToggle = app.switches["bottom_bar_autochange_toggle"]
            XCTAssertTrue(autochangeToggle.waitForExistence(timeout: 3), "El toggle de cambio automático en la barra inferior debería existir")
            if autochangeToggle.value as? String != "1" {
                autochangeToggle.tap()
                sleep(1)
            }
        }
        
        /// Test básico de existencia de elementos principales de UI (controles flotantes)
        /// Verifica que los controles de vidrio flotantes de la ventana principal existan
        func testBasicUIElementsExist() {
            // Verificar botón de configuración flotante (pill del traffic-light)
            let configButton = app.buttons["main_settings_button"]
            XCTAssertTrue(configButton.waitForExistence(timeout: 3), "El botón Configuración flotante debería existir")
            
            // Verificar botón de playback flotante (pill de transporte)
            let playButton = app.buttons["main_transport_play_toggle_button"]
            XCTAssertTrue(playButton.waitForExistence(timeout: 3), "El botón Play/Stop flotante debería existir")
            
            // Revelar la biblioteca y verificar el botón Importar dentro de library_rail
            let rail = revealLibraryRailIfNeeded()
            let importButton = rail.buttons["library_import_button"]
            XCTAssertTrue(importButton.waitForExistence(timeout: 3), "El botón Importar en la biblioteca debería existir")
            XCTAssertTrue(importButton.isEnabled, "El botón Importar debería estar habilitado")
        }
        
        /// Test de ventana de configuración y botones de optimización
        /// Consolida verificación de todos los botones en settings sin redundancia
        func testSettingsOptimizationButtons() {
            // Abrir ventana de configuración usando el botón flotante de la ventana principal
            let configButton = app.buttons["main_settings_button"]
            XCTAssertTrue(configButton.waitForExistence(timeout: 3), "El botón Configuración debería existir")
            configButton.tap()
            
            // Esperar a que la ventana de configuración aparezca
            // SwiftUI sheets pueden tardar en aparecer - timeout generoso
            let hevcOptimizeButton = app.buttons["optimize_hevc_button"]
            XCTAssertTrue(hevcOptimizeButton.waitForExistence(timeout: 5), "El botón de optimización HEVC debería existir")
            
            let blackFrameOptimizeButton = app.buttons["remove_black_frames_button"]
            XCTAssertTrue(blackFrameOptimizeButton.waitForExistence(timeout: 3), "El botón de eliminación de frames negros debería existir")
            
            let clearVideosButton = app.buttons["clear_videos_button"]
            XCTAssertTrue(clearVideosButton.waitForExistence(timeout: 3), "El botón de limpiar videos debería existir")
            
            // Cerrar la ventana de configuración
            let cancelButton = app.buttons["settings_cancel_button"]
            if cancelButton.waitForExistence(timeout: 2) {
                cancelButton.tap()
            } else {
                // Fallback a Escape si no encontramos el botón
                app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            }
        }
        
        // MARK: - Tests consolidados con identificadores de accesibilidad
        
         /// Test de diagnóstico: verificar qué elementos encuentra XCTest
         /// Útil para debugging cuando los tests fallan
         func testDiagnosticUIHierarchy() {
             print("=== DIAGNOSTIC TEST START ===")
             print("Windows count: \(app.windows.count)")
             print("Buttons count: \(app.buttons.count)")
             print("StaticTexts count: \(app.staticTexts.count)")
             
             // Give extra time for window to appear (increased from 2s to 3s)
             sleep(3)
             
             print("After 3s - Windows count: \(app.windows.count)")
             print("After 3s - Buttons count: \(app.buttons.count)")
             print("After 3s - StaticTexts count: \(app.staticTexts.count)")
             
             // Try to find ANY button
             if app.buttons.count > 0 {
                 print("=== BUTTONS FOUND ===")
                 for i in 0..<min(app.buttons.count, 5) {
                     let button = app.buttons.element(boundBy: i)
                     print("Button \(i): identifier='\(button.identifier)', label='\(button.label)'")
                 }
             }
             
             // Try to find ANY static text
             if app.staticTexts.count > 0 {
                 print("=== STATIC TEXTS FOUND ===")
                 for i in 0..<min(app.staticTexts.count, 5) {
                     let text = app.staticTexts.element(boundBy: i)
                     print("StaticText \(i): identifier='\(text.identifier)', label='\(text.label)'")
                 }
             }
             
             // Try to find ANY window
             if app.windows.count > 0 {
                 print("=== WINDOWS FOUND ===")
                 for i in 0..<app.windows.count {
                     let window = app.windows.element(boundBy: i)
                     print("Window \(i): identifier='\(window.identifier)', title='\(window.title)'")
                 }
             }
             
             print("=== DIAGNOSTIC TEST END ===")
             
             // Assertion: At least one window should exist in UI test mode
             XCTAssertTrue(app.windows.count > 0, "At least one window should exist in UI test mode")
         }
         
          /// Test completo de la barra inferior de vidrio con identificadores de accesibilidad
          func testBottomGlassBarExistsByIdentifier() {
              // Verificar toggle de cambio automático (siempre visible en la barra inferior)
              let autochangeToggle = app.switches["bottom_bar_autochange_toggle"]
              XCTAssertTrue(autochangeToggle.waitForExistence(timeout: 2), "El toggle 'bottom_bar_autochange_toggle' debería existir")
              
              // Verificar contador de videos (siempre visible en la barra inferior)
              let videoCount = app.staticTexts["bottom_bar_video_count"]
              XCTAssertTrue(videoCount.waitForExistence(timeout: 2), "El contador 'bottom_bar_video_count' debería existir")
          }
          
        // MARK: - Phase 2: Playback Mode Picker Tests (Bottom Bar)
        
        /// Test de existencia del picker de modo de reproducción (Playlist/Shuffle)
        func testPlaybackModePickerExists() {
            // El picker de modo solo es visible con el toggle de cambio automático activado
            ensureAutoChangeEnabled()
            
            let picker = app.segmentedControls["bottom_bar_mode_picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker de modo de reproducción debería existir con ID 'bottom_bar_mode_picker'")
        }
        
        /// Test de segmentos del picker (Playlist y Shuffle)
        func testPlaybackModePickerHasTwoSegments() {
            ensureAutoChangeEnabled()
            
            let picker = app.segmentedControls["bottom_bar_mode_picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker de modo de reproducción debería existir")
            
            // Verificar que tiene 2 segmentos
            let buttons = picker.buttons
            XCTAssertEqual(buttons.count, 2, "El picker debería tener 2 segmentos")
        }
        
        /// Test de interacción: tap en segmento Shuffle
        func testTappingShuffleSegmentEnablesShuffle() {
            ensureAutoChangeEnabled()
            
            let picker = app.segmentedControls["bottom_bar_mode_picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker de modo de reproducción debería existir")
            
            let shuffleButton = picker.buttons.element(boundBy: 1) // Segundo segmento
            XCTAssertTrue(shuffleButton.waitForExistence(timeout: 3), "El segmento Shuffle debería existir")
            
            shuffleButton.tap()
            
            // Dar tiempo para que la UI se actualice
            sleep(1)
            
            // Verificar que el segmento Shuffle está seleccionado
            XCTAssertEqual(shuffleButton.value as? String, "1", "El segmento Shuffle debería estar seleccionado")
        }
        
        /// Test de interacción: tap en segmento Playlist
        func testTappingPlaylistSegmentDisablesShuffle() {
            ensureAutoChangeEnabled()
            
            let picker = app.segmentedControls["bottom_bar_mode_picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker de modo de reproducción debería existir")
            
            let playlistButton = picker.buttons.element(boundBy: 0) // Primer segmento
            XCTAssertTrue(playlistButton.waitForExistence(timeout: 3), "El segmento Playlist debería existir")
            
            playlistButton.tap()
            
            // Dar tiempo para que la UI se actualice
            sleep(1)
            
            // Verificar que el segmento Playlist está seleccionado
            XCTAssertEqual(playlistButton.value as? String, "1", "El segmento Playlist debería estar seleccionado")
        }
        
        /// Test de posición del picker (debe ser interactivo en la barra inferior)
        func testPlaybackModePickerPosition() {
            ensureAutoChangeEnabled()
            
            let picker = app.segmentedControls["bottom_bar_mode_picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker de modo de reproducción debería existir")
            
            // El picker existe y es visible
            XCTAssertTrue(picker.isHittable, "El picker debería ser interactivo")
        }
        
        /// Test de estado inicial del picker (Playlist por defecto)
        func testPlaybackModePickerReflectsCurrentState() {
            ensureAutoChangeEnabled()
            
            let picker = app.segmentedControls["bottom_bar_mode_picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker de modo de reproducción debería existir")
            
            let playlistButton = picker.buttons.element(boundBy: 0)
            XCTAssertTrue(playlistButton.waitForExistence(timeout: 3), "El segmento Playlist debería existir")
            
            // Por defecto debería estar en modo Playlist
            XCTAssertEqual(playlistButton.value as? String, "1", "Por defecto debería estar en modo Playlist")
        }
    }
