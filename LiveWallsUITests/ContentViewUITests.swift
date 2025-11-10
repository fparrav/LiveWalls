import XCTest

final class ContentViewUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testVideoListInteraction() {
        // Verificar que los elementos principales de la UI existen
        let importButton = app.buttons["Importar"]
        XCTAssertTrue(importButton.exists, "El botón Importar debería existir")
        
        let configButton = app.buttons["Configuración"] 
        XCTAssertTrue(configButton.exists, "El botón Configuración debería existir")
        
        // Verificar que el título de la app existe
        let titleText = app.staticTexts["LiveWalls"]
        XCTAssertTrue(titleText.exists, "El título LiveWalls debería existir")
    }
    
    func testVideoSelection() {
        // Probar el botón de importar (este abrirá el selector de archivos)
        let importButton = app.buttons["Importar"]
        XCTAssertTrue(importButton.exists, "El botón Importar debería existir")
        
        // Verificar que podemos interactuar con el botón
        importButton.tap()
        
        // Esperar un poco para que se abra el diálogo
        sleep(1)
        
        // Presionar Escape para cancelar el diálogo si está abierto
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }
    
    func testVideoContextMenu() {
        // Verificar que existen algunos elementos interactivos en la interfaz
        let importButton = app.buttons["Importar"]
        XCTAssertTrue(importButton.exists, "El botón Importar debería existir")
        
        let playButton = app.buttons["Reproducir"]  
        XCTAssertTrue(playButton.exists, "El botón Reproducir debería existir")
        
        let wallpaperButton = app.buttons["Establecer como Wallpaper"]
        XCTAssertTrue(wallpaperButton.exists, "El botón Establecer como Wallpaper debería existir")
        
        let deleteButton = app.buttons["Eliminar"]
        XCTAssertTrue(deleteButton.exists, "El botón Eliminar debería existir")
    }
    
    func testSettingsOptimizationButtons() {
        // Abrir ventana de configuración
        let configButton = app.buttons["Configuración"]
        XCTAssertTrue(configButton.exists, "El botón Configuración debería existir")
        configButton.tap()
        
        // Esperar a que se abra la ventana de configuración
        sleep(1)
        
        // Verificar que los botones de optimización existen usando accessibility identifiers
        let hevcOptimizeButton = app.buttons["optimize_hevc_button"]
        XCTAssertTrue(hevcOptimizeButton.exists, "El botón de optimización HEVC debería existir")
        
        let blackFrameOptimizeButton = app.buttons["remove_black_frames_button"]
        XCTAssertTrue(blackFrameOptimizeButton.exists, "El botón de eliminación de frames negros debería existir")
        
        let clearVideosButton = app.buttons["clear_videos_button"]
        XCTAssertTrue(clearVideosButton.exists, "El botón de limpiar videos debería existir")
        
        // Cerrar la ventana de configuración presionando Escape
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }
    
    func testBlackFrameOptimizationButtonInteraction() {
        // Abrir ventana de configuración
        let configButton = app.buttons["Configuración"]
        configButton.tap()
        
        // Esperar a que se abra la ventana
        sleep(2)
        
        // Verificar que el botón de eliminación de frames negros existe
        let blackFrameOptimizeButton = app.buttons["remove_black_frames_button"]
        XCTAssertTrue(blackFrameOptimizeButton.exists, "El botón de eliminación de frames negros debería existir")
        
        // Cerrar ventana
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    }
    
    // MARK: - Tests con identificadores de accesibilidad (Fase 1)
    
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