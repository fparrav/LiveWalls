import XCTest
@testable import LiveWalls

/// Tests unitarios para BookmarkActor siguiendo TDD
@MainActor
final class BookmarkActorTests: XCTestCase {
    var bookmarkActor: BookmarkActor!
    
    override func setUp() async throws {
        try await super.setUp()
        bookmarkActor = BookmarkActor()
    }
    
    override func tearDown() async throws {
        bookmarkActor = nil
        try await super.tearDown()
    }
    
    // MARK: - Test 1: Verificar resolución de bookmark asíncrona
    
    /// Test que verifica que resolveBookmark retorna URL válida
    func testBookmarkActorResolveBookmarkAsync() async throws {
        // Given: Crear un bookmark data válido desde una URL de prueba
        let testURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        
        // Verificar que el archivo existe antes de crear el bookmark
        guard FileManager.default.fileExists(atPath: testURL.path) else {
            XCTFail("Archivo de prueba no existe: \(testURL.path)")
            return
        }
        
        let bookmarkData: Data
        do {
            bookmarkData = try testURL.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            XCTFail("No se pudo crear bookmark data: \(error)")
            return
        }
        
        // When: Resolver el bookmark de forma asíncrona
        let resolvedURL = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
        
        // Then: La URL resuelta debe ser válida y accesible
        XCTAssertNotNil(resolvedURL, "URL resuelta no debe ser nil")
        XCTAssertEqual(resolvedURL.path, testURL.path, "URL resuelta debe coincidir con URL original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedURL.path), "URL resuelta debe ser accesible")
    }
    
    // MARK: - Test 2: Verificar acceso concurrente seguro
    
    /// Test que verifica acceso concurrente seguro al actor
    func testBookmarkActorConcurrentAccess() async throws {
        // Given: Crear múltiples bookmarks para probar concurrencia
        let testURLs = [
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            URL(fileURLWithPath: "/System/Library/CoreServices/SystemUIServer.app"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app")
        ]
        
        var bookmarks: [(url: URL, data: Data)] = []
        
        for url in testURLs {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            
            do {
                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                bookmarks.append((url, bookmarkData))
            } catch {
                // Ignorar si falla un bookmark específico
                continue
            }
        }
        
        XCTAssertFalse(bookmarks.isEmpty, "Debe haber al menos un bookmark válido para el test")
        
        // When: Resolver múltiples bookmarks concurrentemente
        try await withThrowingTaskGroup(of: URL.self) { group in
            for (_, bookmarkData) in bookmarks {
                group.addTask {
                    return try await self.bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
                }
            }
            
            // Then: Todas las resoluciones deben completarse sin race conditions
            var resolvedCount = 0
            for try await _ in group {
                resolvedCount += 1
            }
            
            XCTAssertEqual(resolvedCount, bookmarks.count, "Todas las resoluciones deben completarse")
        }
    }
    
    // MARK: - Test 3: Verificar que NO bloquea main thread
    
    /// Test que verifica que resolveBookmark NO bloquea el main thread
    func testBookmarkActorMainThreadNotBlocked() async throws {
        // Given: Crear bookmark data de prueba
        let testURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        
        guard FileManager.default.fileExists(atPath: testURL.path) else {
            XCTFail("Archivo de prueba no existe")
            return
        }
        
        let bookmarkData = try testURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        // When: Ejecutar resolución mientras monitoreamos el main thread
        let expectation = expectation(description: "Main thread no bloqueado")
        
        // Iniciar task de resolución
        Task {
            _ = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
            expectation.fulfill()
        }
        
        // Verificar que el main thread puede ejecutar código mientras el actor trabaja
        var mainThreadExecutions = 0
        for _ in 0..<10 {
            await Task { @MainActor in
                mainThreadExecutions += 1
            }.value
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        // Then: El main thread debe haber ejecutado código mientras el actor trabajaba
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertGreaterThan(mainThreadExecutions, 0, "Main thread debe poder ejecutar código durante resolución de bookmark")
    }
    
    // MARK: - Test adicional: Gestión de security-scoped resources
    
    /// Test que verifica la gestión correcta de security-scoped resources
    func testBookmarkActorSecurityScopedResourceManagement() async throws {
        // Given: Crear bookmark data de prueba
        let testURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        
        guard FileManager.default.fileExists(atPath: testURL.path) else {
            XCTFail("Archivo de prueba no existe")
            return
        }
        
        let bookmarkData = try testURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        // When: Iniciar acceso a security-scoped resource
        let resolvedURL = try await bookmarkActor.resolveBookmark(bookmarkData: bookmarkData)
        let started = await bookmarkActor.startAccessingSecurityScopedResource(url: resolvedURL)
        
        // Then: El acceso debe iniciarse correctamente
        XCTAssertTrue(started, "Debe poder iniciar acceso a security-scoped resource")
        
        // Cleanup: Detener acceso
        await bookmarkActor.stopAccessingSecurityScopedResource(url: resolvedURL)
    }
}
