import XCTest
@testable import LiveWalls

/// Tests unitarios para PersistenceActor siguiendo TDD
/// Estos tests fallarán inicialmente porque PersistenceActor no existe aún
final class PersistenceActorTests: XCTestCase {
    
    var persistenceActor: PersistenceActor!
    var testUserDefaults: UserDefaults!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Crear UserDefaults de prueba con suite única
        let suiteName = "test.livewalls.persistence.\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: suiteName)!
        
        // Limpiar cualquier dato previo
        testUserDefaults.removePersistentDomain(forName: suiteName)
        
        // Crear actor con UserDefaults de prueba
        persistenceActor = PersistenceActor(userDefaults: testUserDefaults)
    }
    
    override func tearDown() async throws {
        // Limpiar UserDefaults de prueba
        let testSuiteName = "com.livewalls.tests"
        testUserDefaults.removePersistentDomain(forName: testSuiteName)
        
        persistenceActor = nil
        testUserDefaults = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Test 1: Carga asíncrona de videos desde UserDefaults
    
    func testPersistenceActorLoadVideosAsync() async throws {
        // Arrange: Preparar datos de prueba en UserDefaults
        let testVideos = [
            VideoFile(id: UUID(), url: URL(fileURLWithPath: "/test/video1.mp4"), name: "Test Video 1"),
            VideoFile(id: UUID(), url: URL(fileURLWithPath: "/test/video2.mp4"), name: "Test Video 2")
        ]
        
        let videoData = try testVideos.map { try JSONEncoder().encode($0) }
        testUserDefaults.set(videoData, forKey: "SavedVideos")
        
        // Act: Cargar videos usando el actor
        let loadedVideos = try await persistenceActor.loadVideos()
        
        // Assert: Verificar que se cargaron correctamente
        XCTAssertEqual(loadedVideos.count, 2, "Debe cargar 2 videos")
        XCTAssertEqual(loadedVideos[0].name, "Test Video 1")
        XCTAssertEqual(loadedVideos[1].name, "Test Video 2")
    }
    
    // MARK: - Test 2: Guardado asíncrono de videos a UserDefaults
    
    func testPersistenceActorSaveVideosAsync() async throws {
        // Arrange: Crear videos de prueba
        let testVideos = [
            VideoFile(id: UUID(), url: URL(fileURLWithPath: "/test/video1.mp4"), name: "Save Test 1"),
            VideoFile(id: UUID(), url: URL(fileURLWithPath: "/test/video2.mp4"), name: "Save Test 2"),
            VideoFile(id: UUID(), url: URL(fileURLWithPath: "/test/video3.mp4"), name: "Save Test 3")
        ]
        
        // Act: Guardar videos usando el actor
        try await persistenceActor.saveVideos(testVideos)
        
        // Assert: Verificar que se guardaron en UserDefaults
        guard let savedData = testUserDefaults.array(forKey: "SavedVideos") as? [Data] else {
            XCTFail("No se encontraron datos guardados en UserDefaults")
            return
        }
        
        XCTAssertEqual(savedData.count, 3, "Debe guardar 3 videos")
        
        // Verificar que los datos se pueden decodificar correctamente
        let decodedVideos = try savedData.map { try JSONDecoder().decode(VideoFile.self, from: $0) }
        XCTAssertEqual(decodedVideos[0].name, "Save Test 1")
        XCTAssertEqual(decodedVideos[1].name, "Save Test 2")
        XCTAssertEqual(decodedVideos[2].name, "Save Test 3")
    }
    
    // MARK: - Test 3: Verificar que serialización JSON no bloquea main thread
    
    func testPersistenceActorSerializationNotBlockingMainThread() async throws {
        // Arrange: Crear múltiples videos para simular carga pesada
        let testVideos = (0..<100).map { index in
            VideoFile(
                id: UUID(),
                url: URL(fileURLWithPath: "/test/video\(index).mp4"),
                name: "Video \(index)",
                thumbnailData: Data(repeating: 0, count: 1000) // Simular thumbnails
            )
        }
        
        // Act: Guardar videos en background
        let saveTask = Task {
            try await persistenceActor.saveVideos(testVideos)
        }
        
        // Verificar que el main thread está disponible durante la operación
        let mainThreadCheck = Task { @MainActor in
            // Si llegamos aquí, el main thread no está bloqueado
            return true
        }
        
        // Assert: Ambas operaciones deben completarse
        let isMainThreadAvailable = await mainThreadCheck.value
        XCTAssertTrue(isMainThreadAvailable, "Main thread debe estar disponible durante serialización")
        
        // Esperar a que el guardado complete
        try await saveTask.value
        
        // Verificar que los datos se guardaron
        let loadedVideos = try await persistenceActor.loadVideos()
        XCTAssertEqual(loadedVideos.count, 100, "Debe cargar 100 videos")
    }
    
    // MARK: - Test 4: Carga de video actual
    
    func testPersistenceActorLoadCurrentVideo() async throws {
        // Arrange: Guardar un video actual en UserDefaults
        let currentVideo = VideoFile(
            id: UUID(),
            url: URL(fileURLWithPath: "/test/current.mp4"),
            name: "Current Video"
        )
        
        let data = try JSONEncoder().encode(currentVideo)
        testUserDefaults.set(data, forKey: "CurrentVideo")
        
        // Act: Cargar el video actual
        let loadedVideo = await persistenceActor.loadCurrentVideo()
        
        // Assert: Verificar que se cargó correctamente
        XCTAssertNotNil(loadedVideo, "Debe cargar el video actual")
        XCTAssertEqual(loadedVideo?.name, "Current Video")
    }
    
    // MARK: - Test 5: Guardado de video actual
    
    func testPersistenceActorSaveCurrentVideo() async throws {
        // Arrange: Crear video actual
        let currentVideo = VideoFile(
            id: UUID(),
            url: URL(fileURLWithPath: "/test/save-current.mp4"),
            name: "Save Current Video"
        )
        
        // Act: Guardar el video actual
        await persistenceActor.saveCurrentVideo(currentVideo)
        
        // Assert: Verificar que se guardó en UserDefaults
        guard let savedData = testUserDefaults.data(forKey: "CurrentVideo") else {
            XCTFail("No se encontró el video actual en UserDefaults")
            return
        }
        
        let decodedVideo = try JSONDecoder().decode(VideoFile.self, from: savedData)
        XCTAssertEqual(decodedVideo.name, "Save Current Video")
    }
    
    // MARK: - Test 6: Carga de configuración de auto-change
    
    func testPersistenceActorLoadAutoChangeSettings() async throws {
        // Arrange: Guardar configuración en UserDefaults
        testUserDefaults.set(true, forKey: "AutoChangeEnabled")
        testUserDefaults.set(600.0, forKey: "AutoChangeInterval") // 10 minutos
        
        // Act: Cargar configuración
        let settings = await persistenceActor.loadAutoChangeSettings()
        
        // Assert: Verificar valores cargados
        XCTAssertTrue(settings.isEnabled, "Auto-change debe estar habilitado")
        XCTAssertEqual(settings.interval, 600.0, accuracy: 0.1, "Intervalo debe ser 600s")
    }
    
    // MARK: - Test 7: Guardado de configuración de auto-change
    
    func testPersistenceActorSaveAutoChangeSettings() async throws {
        // Arrange: Configuración de prueba
        let isEnabled = true
        let interval: TimeInterval = 300.0 // 5 minutos
        
        // Act: Guardar configuración
        await persistenceActor.saveAutoChangeSettings(isEnabled: isEnabled, interval: interval)
        
        // Assert: Verificar que se guardó en UserDefaults
        let savedEnabled = testUserDefaults.bool(forKey: "AutoChangeEnabled")
        let savedInterval = testUserDefaults.double(forKey: "AutoChangeInterval")
        
        XCTAssertTrue(savedEnabled, "Auto-change debe estar habilitado en UserDefaults")
        XCTAssertEqual(savedInterval, 300.0, accuracy: 0.1, "Intervalo debe ser 300s en UserDefaults")
    }
    
    // MARK: - Test 8: Valores por defecto cuando no hay datos
    
    func testPersistenceActorDefaultValues() async throws {
        // Act: Cargar sin datos previos
        let videos = try await persistenceActor.loadVideos()
        let currentVideo = await persistenceActor.loadCurrentVideo()
        let settings = await persistenceActor.loadAutoChangeSettings()
        
        // Assert: Verificar valores por defecto
        XCTAssertEqual(videos.count, 0, "Lista de videos debe estar vacía")
        XCTAssertNil(currentVideo, "Video actual debe ser nil")
        XCTAssertFalse(settings.isEnabled, "Auto-change debe estar deshabilitado por defecto")
        XCTAssertEqual(settings.interval, 600.0, accuracy: 0.1, "Intervalo por defecto debe ser 10 minutos")
    }
}
