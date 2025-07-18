import XCTest
import AVFoundation
import CoreGraphics
@testable import LiveWalls

final class VideoOptimizerTests: XCTestCase {
    var videoOptimizer: VideoOptimizer!
    
    override func setUp() {
        super.setUp()
        videoOptimizer = VideoOptimizer()
    }
    
    override func tearDown() {
        videoOptimizer = nil
        super.tearDown()
    }
    
    // MARK: - Black Frame Detection Tests
    
    func testIsBlackOrDarkFrame_PureBlack() {
        // Given
        let blackImage = TestImageGenerator.createImage(color: TestConstants.TestColors.pureBlack)
        
        // When
        let isBlack = videoOptimizer.isBlackOrDarkFrame(blackImage)
        
        // Then
        XCTAssertTrue(isBlack, "Una imagen completamente negra debería ser detectada como frame negro")
    }
    
    func testIsBlackOrDarkFrame_PureWhite() {
        // Given
        let whiteImage = TestImageGenerator.createImage(color: TestConstants.TestColors.pureWhite)
        
        // When
        let isBlack = videoOptimizer.isBlackOrDarkFrame(whiteImage)
        
        // Then
        XCTAssertFalse(isBlack, "Una imagen completamente blanca no debería ser detectada como frame negro")
    }
    
    func testIsBlackOrDarkFrame_DarkGray() {
        // Given - Color gris muy oscuro (cerca del umbral del 5%)
        let darkGrayImage = TestImageGenerator.createImage(color: TestConstants.TestColors.darkGray)
        
        // When
        let isBlack = videoOptimizer.isBlackOrDarkFrame(darkGrayImage)
        
        // Then
        XCTAssertTrue(isBlack, "Una imagen con menos del 5% de brillo debería ser detectada como frame negro")
    }
    
    func testIsBlackOrDarkFrame_LightGray() {
        // Given - Color gris claro (por encima del umbral del 5%)
        let lightGrayImage = TestImageGenerator.createImage(color: TestConstants.TestColors.lightGray)
        
        // When
        let isBlack = videoOptimizer.isBlackOrDarkFrame(lightGrayImage)
        
        // Then
        XCTAssertFalse(isBlack, "Una imagen con más del 5% de brillo no debería ser detectada como frame negro")
    }
    
    func testIsBlackOrDarkFrame_ThresholdEdge() {
        // Given - Color exactamente en el umbral del 5%
        let thresholdImage = TestImageGenerator.createImage(color: TestConstants.TestColors.threshold)
        
        // When
        let isBlack = videoOptimizer.isBlackOrDarkFrame(thresholdImage)
        
        // Then
        XCTAssertFalse(isBlack, "Una imagen con exactamente 5% de brillo no debería ser detectada como frame negro (umbral exclusivo)")
    }
    
    // MARK: - Video Analysis Tests
    
    func testAnalyzeVideo_ValidVideo() async throws {
        // Este test requiere un archivo de video real, se omite en el entorno de test automático
        // En un entorno de test real, se podría usar un video de muestra incluido en el bundle
        throw XCTSkip("Requiere archivo de video real para testing")
    }
    
    func testDetectVideoCodec_H264() async throws {
        // Este test requiere un archivo de video real para analizar el codec
        throw XCTSkip("Requiere archivo de video real para testing")
    }
    
    // MARK: - Composition Creation Tests
    
    func testCreateTrimmedComposition_ValidRange() throws {
        // Este test requiere un archivo de video real para crear composiciones
        throw XCTSkip("Requiere archivo de video real para testing")
    }
    
    func testCreateTrimmedComposition_HasVideoTrack() throws {
        // Este test requiere un archivo de video real para verificar tracks
        throw XCTSkip("Requiere archivo de video real para testing")
    }
    
    // MARK: - Error Handling Tests
    
    func testAnalyzeVideo_InvalidURL() async {
        // Given
        let invalidURL = URL(fileURLWithPath: "/path/to/nonexistent/video.mp4")
        
        // When & Then
        do {
            _ = try await videoOptimizer.analyzeVideo(at: invalidURL)
            XCTFail("Debería haber lanzado un error para una URL inválida")
        } catch {
            // Se espera que lance un error
            XCTAssertNotNil(error, "Debería haber un error para una URL inválida")
        }
    }
    
    func testDetectVideoCodec_AssetWithoutVideoTrack() async {
        // Given - Un asset que simula no tener pistas de video
        let emptyAsset = AVURLAsset(url: URL(fileURLWithPath: "/dev/null"))
        
        // When & Then
        do {
            _ = try await videoOptimizer.detectVideoCodec(asset: emptyAsset)
            XCTFail("Debería haber lanzado un error para un asset sin pistas de video")
        } catch {
            // Se espera que lance un error VideoOptimizerError.noVideoTrack
            if let videoError = error as? VideoOptimizerError {
                XCTAssertEqual(videoError, .noVideoTrack, "Debería ser un error de 'no video track'")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testBlackFrameDetectionPerformance() {
        // Given
        let testImage = TestImageGenerator.createImage(color: TestConstants.TestColors.pureBlack, 
                                                     size: TestConstants.largeTestImageSize)
        
        // When & Then
        measure {
            _ = videoOptimizer.isBlackOrDarkFrame(testImage)
        }
    }
    
    // MARK: - Integration Tests
    
    func testOptimizeVideoWithBlackFrameDetection_MockScenario() async {
        // Given
        let mockVideoFile = MockVideoFile(
            url: TestVideoGenerator.createTempVideoURL(),
            name: "Test Video",
            bookmarkData: nil, // Sin bookmark data para simular error
            shouldFailBookmarkResolution: true
        )
        let outputURL = TestVideoGenerator.createTempVideoURL()
        
        // When & Then
        do {
            _ = try await videoOptimizer.optimizeVideoWithBlackFrameDetection(mockVideoFile, to: outputURL)
            XCTFail("Debería haber lanzado un error con datos mock sin bookmark")
        } catch VideoOptimizerError.noBookmarkData {
            // Se espera este error con datos mock sin bookmark
            XCTAssertTrue(true, "Error esperado con datos mock sin bookmark")
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }
    
    func testTrimVideoBlackFrames_MockScenario() async {
        // Given
        let mockVideoFile = MockVideoFile(
            url: TestVideoGenerator.createTempVideoURL(),
            name: "Test Video",
            bookmarkData: nil, // Sin bookmark data para simular error
            shouldFailBookmarkResolution: true
        )
        let outputURL = TestVideoGenerator.createTempVideoURL()
        
        // When & Then
        do {
            _ = try await videoOptimizer.trimVideoBlackFrames(mockVideoFile, to: outputURL)
            XCTFail("Debería haber lanzado un error con datos mock sin bookmark")
        } catch VideoOptimizerError.noBookmarkData {
            // Se espera este error con datos mock sin bookmark
            XCTAssertTrue(true, "Error esperado con datos mock sin bookmark")
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }
    
    func testTrimVideoBlackFrames_NoBlackFrames() async {
        // Este test simula un video sin frames negros
        // En un entorno de test real, se usaría un video que no tenga frames negros
        // y se verificaría que el resultado sea (URL, false)
        throw XCTSkip("Requiere archivo de video real sin frames negros para testing")
    }
    
    func testTrimVideoBlackFrames_WithBlackFrames() async {
        // Este test simula un video con frames negros
        // En un entorno de test real, se usaría un video que tenga frames negros
        // y se verificaría que el resultado sea (URL, true)
        throw XCTSkip("Requiere archivo de video real con frames negros para testing")
    }
    
    // MARK: - Additional Edge Case Tests
    
    func testIsBlackOrDarkFrame_NoiseImage() {
        // Given - Imagen con ruido oscuro
        let noisyDarkImage = TestImageGenerator.createNoiseImage(brightness: 0.02) // Por debajo del umbral
        let noisyLightImage = TestImageGenerator.createNoiseImage(brightness: 0.1) // Por encima del umbral
        
        // When & Then
        XCTAssertTrue(videoOptimizer.isBlackOrDarkFrame(noisyDarkImage), 
                     "Una imagen oscura con ruido debería ser detectada como frame negro")
        XCTAssertFalse(videoOptimizer.isBlackOrDarkFrame(noisyLightImage), 
                      "Una imagen clara con ruido no debería ser detectada como frame negro")
    }
    
    func testIsBlackOrDarkFrame_GradientImage() {
        // Given - Imagen con gradiente de negro a blanco
        let gradientImage = TestImageGenerator.createGradientImage(
            from: TestConstants.TestColors.pureBlack, 
            to: TestConstants.TestColors.pureWhite
        )
        
        // When
        let isBlack = videoOptimizer.isBlackOrDarkFrame(gradientImage)
        
        // Then - Depende del promedio del gradiente, debería ser alrededor del 50%
        XCTAssertFalse(isBlack, "Una imagen con gradiente negro-blanco no debería ser detectada como frame negro")
    }
    
    // MARK: - Localization Tests
    
    func testBlackFrameRemovalLocalizations() {
        // Given - Verificar que las localizaciones existen y no son placeholders
        let title = NSLocalizedString("remove_black_frames_title", comment: "Remove black frames title")
        let message = NSLocalizedString("remove_black_frames_message", comment: "Remove black frames message")
        let completeTitle = NSLocalizedString("black_frames_complete_title", comment: "Black frames complete title")
        let completeMessage = NSLocalizedString("black_frames_complete_message", comment: "Black frames complete message")
        
        // Then - Verificar que las localizaciones no son claves sin traducir
        XCTAssertFalse(title.isEmpty, "El título de eliminación de frames negros no debería estar vacío")
        XCTAssertFalse(title.hasPrefix("remove_black_frames_title"), "El título no debería ser la clave sin localizar")
        XCTAssertFalse(message.isEmpty, "El mensaje de eliminación de frames negros no debería estar vacío")
        XCTAssertFalse(message.hasPrefix("remove_black_frames_message"), "El mensaje no debería ser la clave sin localizar")
        XCTAssertFalse(completeTitle.isEmpty, "El título de completación no debería estar vacío")
        XCTAssertFalse(completeTitle.hasPrefix("black_frames_complete_title"), "El título de completación no debería ser la clave sin localizar")
        XCTAssertFalse(completeMessage.isEmpty, "El mensaje de completación no debería estar vacío")
        XCTAssertFalse(completeMessage.hasPrefix("black_frames_complete_message"), "El mensaje de completación no debería ser la clave sin localizar")
    }
    
    func testErrorHandlingLocalizations() {
        // Given - Verificar que las nuevas localizaciones de error existen
        let errorTitle = NSLocalizedString("optimization_errors_title", comment: "Optimization errors title")
        let errorMessage = NSLocalizedString("optimization_errors_message", comment: "Optimization errors message")
        
        // Then - Verificar que las localizaciones de error no son claves sin traducir
        XCTAssertFalse(errorTitle.isEmpty, "El título de errores no debería estar vacío")
        XCTAssertFalse(errorTitle.hasPrefix("optimization_errors_title"), "El título de errores no debería ser la clave sin localizar")
        XCTAssertFalse(errorMessage.isEmpty, "El mensaje de errores no debería estar vacío")
        XCTAssertFalse(errorMessage.hasPrefix("optimization_errors_message"), "El mensaje de errores no debería ser la clave sin localizar")
    }
    
    func testFormattedMessages() {
        // Given - Probar que los mensajes formateados funcionan correctamente
        let completeMessage = NSLocalizedString("black_frames_complete_message", comment: "Black frames complete message")
        let errorMessage = NSLocalizedString("optimization_errors_message", comment: "Optimization errors message")
        
        // When - Formatear los mensajes con valores de prueba
        let formattedCompleteMessage = String(format: completeMessage, 5, 3, 2)
        let formattedErrorMessage = String(format: errorMessage, "Error de prueba")
        
        // Then - Verificar que el formateo funciona y contiene los valores esperados
        XCTAssertTrue(formattedCompleteMessage.contains("5"), "El mensaje formateado debería contener el número total de videos")
        XCTAssertTrue(formattedCompleteMessage.contains("3"), "El mensaje formateado debería contener el número de videos procesados")
        XCTAssertTrue(formattedCompleteMessage.contains("2"), "El mensaje formateado debería contener el número de videos omitidos")
        XCTAssertTrue(formattedErrorMessage.contains("Error de prueba"), "El mensaje de error formateado debería contener el error específico")
        
        // Verificar que no quedan placeholders sin reemplazar
        XCTAssertFalse(formattedCompleteMessage.contains("%d"), "No deberían quedar placeholders %d sin reemplazar")
        XCTAssertFalse(formattedErrorMessage.contains("%@"), "No deberían quedar placeholders %@ sin reemplazar")
    }
}