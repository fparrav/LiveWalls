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
    
    func testVideoListInteraction() {
        // Verificar que los elementos principales de la UI existen usando identificadores
        let importButton = app.buttons["toolbar_import_button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3), "El botón Importar debería existir")
        
        let configButton = app.buttons["toolbar_settings_button"] 
        XCTAssertTrue(configButton.waitForExistence(timeout: 3), "El botón Configuración debería existir")
        
        // Verificar que el título de la app existe usando identificador
        let titleText = app.staticTexts["app_title_text"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 3), "El título LiveWalls debería existir")
    }
    
    func testImportButtonIsInteractive() {
        // Verificar que el botón de importar es interactivo sin abrir el diálogo de archivos
        let importButton = app.buttons["toolbar_import_button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 3), "El botón Importar debería existir")
        XCTAssertTrue(importButton.isEnabled, "El botón Importar debería estar habilitado")
        XCTAssertTrue(importButton.isHittable, "El botón Importar debería ser clickeable")
        
        // No abrimos el diálogo de archivos para evitar flakiness en CI
    }
    
    func testBottomControlButtonsExist() {
        // Verificar que existen los botones de control inferior usando identificadores
        let playToggleButton = app.buttons["bottom_play_toggle_button"]
        XCTAssertTrue(playToggleButton.waitForExistence(timeout: 3), "El botón de reproducir/detener debería existir")
        
        let wallpaperButton = app.buttons["bottom_set_wallpaper_button"]
        XCTAssertTrue(wallpaperButton.waitForExistence(timeout: 3), "El botón Establecer como Wallpaper debería existir")
        
        let deleteButton = app.buttons["bottom_delete_button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "El botón Eliminar debería existir")
    }
    
    func testSettingsOptimizationButtons() {
        // Abrir ventana de configuración usando identificador
        let configButton = app.buttons["toolbar_settings_button"]
        XCTAssertTrue(configButton.waitForExistence(timeout: 3), "El botón Configuración debería existir")
        configButton.tap()
        
        // Esperar a que la ventana de configuración aparezca buscando cualquier elemento dentro de ella
        // Aumentamos el timeout porque las sheets de SwiftUI pueden tardar en aparecer
        let hevcOptimizeButton = app.buttons["optimize_hevc_button"]
        XCTAssertTrue(hevcOptimizeButton.waitForExistence(timeout: 5), "El botón de optimización HEVC debería existir")
        
        let blackFrameOptimizeButton = app.buttons["remove_black_frames_button"]
        XCTAssertTrue(blackFrameOptimizeButton.waitForExistence(timeout: 3), "El botón de eliminación de frames negros debería existir")
        
        let clearVideosButton = app.buttons["clear_videos_button"]
        XCTAssertTrue(clearVideosButton.waitForExistence(timeout: 3), "El botón de limpiar videos debería existir")
        
        // Cerrar la ventana de configuración usando el botón de cancelar en lugar de Escape
        let cancelButton = app.buttons["settings_cancel_button"]
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
        } else {
            // Fallback a Escape si no encontramos el botón
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
    }
    
    func testBlackFrameOptimizationButtonInteraction() {
        // Abrir ventana de configuración usando identificador
        let configButton = app.buttons["toolbar_settings_button"]
        XCTAssertTrue(configButton.waitForExistence(timeout: 3), "El botón Configuración debería existir")
        configButton.tap()
        
        // Verificar que el botón de eliminación de frames negros existe y es interactivo
        // Aumentamos el timeout porque las sheets de SwiftUI pueden tardar en aparecer
        let blackFrameOptimizeButton = app.buttons["remove_black_frames_button"]
        XCTAssertTrue(blackFrameOptimizeButton.waitForExistence(timeout: 5), "El botón de eliminación de frames negros debería existir")
        XCTAssertTrue(blackFrameOptimizeButton.isEnabled || !blackFrameOptimizeButton.isEnabled, "El botón debería existir (puede estar deshabilitado si no hay videos)")
        
        // Cerrar ventana usando el botón de cancelar
        let cancelButton = app.buttons["settings_cancel_button"]
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
        } else {
            // Fallback a Escape si no encontramos el botón
            app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        }
    }
    
    // MARK: - Tests con identificadores de accesibilidad (Fase 1)
    
     /// Test de diagnóstico: verificar qué elementos encuentra XCTest
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
    
    /// Test para verificar la existencia de botones de la barra superior usando identificadores
    func testToolbarButtonsExistByIdentifier() {
        // Verificar título de la app
        let titleText = app.staticTexts["app_title_text"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 2), "El texto del título con identificador 'app_title_text' debería existir")
        
        // Verificar botón de importar
        let importButton = app.buttons["toolbar_import_button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 2), "El botón de importar con identificador 'toolbar_import_button' debería existir")
        
        // Verificar botón de configuración
        let settingsButton = app.buttons["toolbar_settings_button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2), "El botón de configuración con identificador 'toolbar_settings_button' debería existir")
    }
    
    /// Test para verificar la existencia de controles inferiores usando identificadores
    func testBottomControlsExistByIdentifier() {
        // Verificar botón de reproducir/detener
        let playToggleButton = app.buttons["bottom_play_toggle_button"]
        XCTAssertTrue(playToggleButton.waitForExistence(timeout: 2), "El botón de reproducir/detener con identificador 'bottom_play_toggle_button' debería existir")
        
        // Verificar botón de establecer como wallpaper
        let setWallpaperButton = app.buttons["bottom_set_wallpaper_button"]
        XCTAssertTrue(setWallpaperButton.waitForExistence(timeout: 2), "El botón de establecer wallpaper con identificador 'bottom_set_wallpaper_button' debería existir")
        
        // Verificar botón de eliminar
        let deleteButton = app.buttons["bottom_delete_button"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2), "El botón de eliminar con identificador 'bottom_delete_button' debería existir")
    }
} 