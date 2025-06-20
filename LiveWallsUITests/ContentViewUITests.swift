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
} 