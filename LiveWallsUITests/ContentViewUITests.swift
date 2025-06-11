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
        // Verificar que la lista de videos está vacía inicialmente
        let videoList = app.tables.firstMatch
        XCTAssertTrue(videoList.exists)
        XCTAssertEqual(videoList.cells.count, 0)
        
        // Verificar que el botón de agregar existe
        let addButton = app.buttons["plus"]
        XCTAssertTrue(addButton.exists)
    }
    
    func testVideoSelection() {
        // Agregar un video (esto abrirá el selector de archivos)
        let addButton = app.buttons["plus"]
        addButton.tap()
        
        // Aquí deberías simular la selección de un archivo
        // Nota: La selección real de archivos requiere permisos especiales en las pruebas de UI
    }
    
    func testVideoContextMenu() {
        // Verificar que el menú contextual existe
        let videoList = app.tables.firstMatch
        let firstCell = videoList.cells.firstMatch
        
        if firstCell.exists {
            firstCell.rightClick()
            
            // Verificar que las opciones del menú contextual existen
            XCTAssertTrue(app.menuItems["Fijar como Fondo"].exists)
            XCTAssertTrue(app.menuItems["Eliminar"].exists)
        }
    }
} 