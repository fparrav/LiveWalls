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
    
    /// Test básico de existencia de elementos principales de UI
    /// Consolida verificación de elementos clave sin redundancia
    func testBasicUIElementsExist() {
        // Verificar título de la app
        let titleText = app.staticTexts["app_title_text"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 3), "El título LiveWalls debería existir")
        
        // Verificar botones principales del toolbar
        let importButton = app.buttons["toolbar_import_button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3), "El botón Importar debería existir")
        XCTAssertTrue(importButton.isEnabled, "El botón Importar debería estar habilitado")
        
        let configButton = app.buttons["toolbar_settings_button"] 
        XCTAssertTrue(configButton.waitForExistence(timeout: 3), "El botón Configuración debería existir")
    }
    
    /// Test de ventana de configuración y botones de optimización
    /// Consolida verificación de todos los botones en settings sin redundancia
    func testSettingsOptimizationButtons() {
        // Abrir ventana de configuración usando identificador
        let configButton = app.buttons["toolbar_settings_button"]
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
} 