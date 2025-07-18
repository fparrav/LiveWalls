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
} 