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
    
    /// Test básico de existencia de elementos principales de UI (sidebar controls)
    /// Verifica que los controles del sidebar con glass effect existan
    func testBasicUIElementsExist() {
        // Verificar botones del sidebar
        let importButton = app.buttons["sidebar_import_button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3), "El botón Importar en sidebar debería existir")
        XCTAssertTrue(importButton.isEnabled, "El botón Importar debería estar habilitado")
        
        let configButton = app.buttons["sidebar_settings_button"] 
        XCTAssertTrue(configButton.waitForExistence(timeout: 3), "El botón Configuración en sidebar debería existir")
        
        // Verificar botones de playback
        let playButton = app.buttons["sidebar_play_toggle_button"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 3), "El botón Play/Stop en sidebar debería existir")
    }
    
    /// Test de ventana de configuración y botones de optimización
    /// Consolida verificación de todos los botones en settings sin redundancia
    func testSettingsOptimizationButtons() {
        // Abrir ventana de configuración usando identificador del sidebar
        let configButton = app.buttons["sidebar_settings_button"]
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
    
     /// Test completo de botones del toolbar con identificadores de accesibilidad
     func testToolbarButtonsExistByIdentifier() {
         // Verificar título de la app
         let titleText = app.staticTexts["app_title_text"]
         XCTAssertTrue(titleText.waitForExistence(timeout: 2), "El título 'app_title_text' debería existir")
         
         // Verificar botón de importar
         let importButton = app.buttons["toolbar_import_button"]
         XCTAssertTrue(importButton.waitForExistence(timeout: 2), "El botón 'toolbar_import_button' debería existir")
         
         // Verificar botón de configuración
         let settingsButton = app.buttons["toolbar_settings_button"]
         XCTAssertTrue(settingsButton.waitForExistence(timeout: 2), "El botón 'toolbar_settings_button' debería existir")
     }
     
      /// Test completo de controles inferiores con identificadores de accesibilidad
      func testBottomControlsExistByIdentifier() {
          // Verificar botón de reproducir/detener
          let playToggleButton = app.buttons["bottom_play_toggle_button"]
          XCTAssertTrue(playToggleButton.waitForExistence(timeout: 2), "El botón 'bottom_play_toggle_button' debería existir")
          
          // Verificar botón de establecer como wallpaper
          let setWallpaperButton = app.buttons["bottom_set_wallpaper_button"]
          XCTAssertTrue(setWallpaperButton.waitForExistence(timeout: 2), "El botón 'bottom_set_wallpaper_button' debería existir")
          
          // Verificar botón de eliminar
          let deleteButton = app.buttons["bottom_delete_button"]
          XCTAssertTrue(deleteButton.waitForExistence(timeout: 2), "El botón 'bottom_delete_button' debería existir")
      }
      
    // MARK: - Phase 2: Playback Mode Picker Tests (Sidebar)
    
    /// Test de existencia del picker de modo de reproducción en sidebar (Playlist/Shuffle)
    func testPlaybackModePickerExists() {
        let picker = app.segmentedControls["sidebar_mode_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker de modo de reproducción debería existir en sidebar con ID 'sidebar_mode_picker'")
    }
    
    /// Test de segmentos del picker (Playlist y Shuffle)
    func testPlaybackModePickerHasTwoSegments() {
        let picker = app.segmentedControls["sidebar_mode_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker debería existir en sidebar")
        
        // Verificar que tiene 2 segmentos
        let buttons = picker.buttons
        XCTAssertEqual(buttons.count, 2, "El picker debería tener 2 segmentos")
    }
    
    /// Test de interacción: tap en segmento Shuffle
    func testTappingShuffleSegmentEnablesShuffle() {
        let picker = app.segmentedControls["sidebar_mode_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker debería existir en sidebar")
        
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
        let picker = app.segmentedControls["sidebar_mode_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker debería existir en sidebar")
        
        let playlistButton = picker.buttons.element(boundBy: 0) // Primer segmento
        XCTAssertTrue(playlistButton.waitForExistence(timeout: 3), "El segmento Playlist debería existir")
        
        playlistButton.tap()
        
        // Dar tiempo para que la UI se actualice
        sleep(1)
        
        // Verificar que el segmento Playlist está seleccionado
        XCTAssertEqual(playlistButton.value as? String, "1", "El segmento Playlist debería estar seleccionado")
    }
    
    /// Test de posición del picker (debería estar en sidebar)
    func testPlaybackModePickerPosition() {
        let picker = app.segmentedControls["sidebar_mode_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker debería existir en sidebar")
        
        // El picker existe y es visible
        XCTAssertTrue(picker.isHittable, "El picker debería ser interactivo")
    }
    
    /// Test de estado inicial del picker (Playlist por defecto)
    func testPlaybackModePickerReflectsCurrentState() {
        let picker = app.segmentedControls["sidebar_mode_picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "El picker debería existir en sidebar")
        
        let playlistButton = picker.buttons.element(boundBy: 0)
        XCTAssertTrue(playlistButton.waitForExistence(timeout: 3), "El segmento Playlist debería existir")
        
        // Por defecto debería estar en modo Playlist
        XCTAssertEqual(playlistButton.value as? String, "1", "Por defecto debería estar en modo Playlist")
    }
}