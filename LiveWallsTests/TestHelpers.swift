import XCTest
import AVFoundation
import CoreGraphics
@testable import LiveWalls

// MARK: - Test Video Generator

class TestVideoGenerator {
    
    /// Crea un video de prueba sintético con frames específicos
    static func createTestVideo(with frames: [TestFrame], outputURL: URL) async throws {
        // Esta función crearía un video real para tests de integración
        // Por ahora, creamos un archivo mock
        let mockVideoData = "MOCK_VIDEO_DATA".data(using: .utf8)!
        try mockVideoData.write(to: outputURL)
    }
    
    /// Crea un video de prueba con frames negros al inicio y final
    static func createVideoWithBlackFrames(duration: Double = 5.0, blackFramesAtStart: Double = 1.0, blackFramesAtEnd: Double = 1.0) -> URL {
        let tempURL = createTempVideoURL()
        
        // En un entorno de test real, esto generaría un video con las características especificadas
        // Por ahora, retornamos una URL que simula este comportamiento
        return tempURL
    }
    
    /// Crea una URL temporal para videos de prueba
    static func createTempVideoURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("test_video_\(UUID().uuidString).mp4")
    }
}

// MARK: - Test Frame

struct TestFrame {
    let color: CGColor
    let duration: Double
    
    static let black = TestFrame(color: CGColor.black, duration: 1.0)
    static let white = TestFrame(color: CGColor.white, duration: 1.0)
    static let gray = TestFrame(color: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0), duration: 1.0)
}

// MARK: - Mock Video File

class MockVideoFile: VideoFile {
    var mockBookmarkData: Data?
    var shouldFailBookmarkResolution: Bool = false
    
    init(url: URL, name: String, bookmarkData: Data? = nil, shouldFailBookmarkResolution: Bool = false) {
        self.mockBookmarkData = bookmarkData
        self.shouldFailBookmarkResolution = shouldFailBookmarkResolution
        super.init(url: url, name: name, bookmarkData: bookmarkData)
    }
    
    override var bookmarkData: Data? {
        return shouldFailBookmarkResolution ? nil : mockBookmarkData
    }
}

// MARK: - Mock Wallpaper Manager

class MockWallpaperManager: WallpaperManager {
    var mockResolveBookmarkResult: URL?
    var shouldFailBookmarkResolution: Bool = false
    
    override func resolveBookmark(for videoFile: VideoFile) -> URL? {
        if shouldFailBookmarkResolution {
            return nil
        }
        return mockResolveBookmarkResult ?? super.resolveBookmark(for: videoFile)
    }
}

// MARK: - Test Image Generator

class TestImageGenerator {
    
    /// Crea una imagen de prueba con el color y tamaño especificados
    static func createImage(color: NSColor, size: CGSize = CGSize(width: 100, height: 100)) -> CGImage {
        return createImage(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, size: size)
    }
    
    /// Crea una imagen con componentes RGB específicos
    static func createImage(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0, size: CGSize = CGSize(width: 100, height: 100)) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        let redByte = UInt8(red * 255)
        let greenByte = UInt8(green * 255)
        let blueByte = UInt8(blue * 255)
        let alphaByte = UInt8(alpha * 255)
        
        for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
            pixelData[i] = redByte
            pixelData[i + 1] = greenByte
            pixelData[i + 2] = blueByte
            pixelData[i + 3] = alphaByte
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        return context.makeImage()!
    }
    
    /// Crea una imagen con gradiente para testing más complejo
    static func createGradientImage(from startColor: NSColor, to endColor: NSColor, size: CGSize = CGSize(width: 100, height: 100)) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        for y in 0..<height {
            let progress = CGFloat(y) / CGFloat(height)
            let red = startColor.redComponent + (endColor.redComponent - startColor.redComponent) * progress
            let green = startColor.greenComponent + (endColor.greenComponent - startColor.greenComponent) * progress
            let blue = startColor.blueComponent + (endColor.blueComponent - startColor.blueComponent) * progress
            
            let redByte = UInt8(red * 255)
            let greenByte = UInt8(green * 255)
            let blueByte = UInt8(blue * 255)
            let alphaByte: UInt8 = 255
            
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                pixelData[pixelIndex] = redByte
                pixelData[pixelIndex + 1] = greenByte
                pixelData[pixelIndex + 2] = blueByte
                pixelData[pixelIndex + 3] = alphaByte
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        return context.makeImage()!
    }
    
    /// Crea una imagen con patrón de ruido para testing
    static func createNoiseImage(brightness: CGFloat = 0.5, size: CGSize = CGSize(width: 100, height: 100)) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        for i in stride(from: 0, to: totalBytes, by: bytesPerPixel) {
            let randomValue = brightness + CGFloat.random(in: -0.1...0.1)
            let clampedValue = max(0, min(1, randomValue))
            let byteValue = UInt8(clampedValue * 255)
            
            pixelData[i] = byteValue     // R
            pixelData[i + 1] = byteValue // G
            pixelData[i + 2] = byteValue // B
            pixelData[i + 3] = 255       // A
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        return context.makeImage()!
    }
}

// MARK: - Test Assertions

extension XCTestCase {
    
    /// Verifica que dos tiempos CMTime sean aproximadamente iguales
    func assertTimesEqual(_ time1: CMTime, _ time2: CMTime, accuracy: Double = 0.1, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(time1.seconds, time2.seconds, accuracy: accuracy, 
                      "Los tiempos no son iguales: \(time1.seconds) vs \(time2.seconds)", 
                      file: file, line: line)
    }
    
    /// Verifica que un CGSize sea válido (no cero)
    func assertSizeValid(_ size: CGSize, file: StaticString = #file, line: UInt = #line) {
        XCTAssertGreaterThan(size.width, 0, "El ancho debe ser mayor que 0", file: file, line: line)
        XCTAssertGreaterThan(size.height, 0, "La altura debe ser mayor que 0", file: file, line: line)
    }
    
    /// Verifica que una duración sea válida (positiva)
    func assertDurationValid(_ duration: Double, file: StaticString = #file, line: UInt = #line) {
        XCTAssertGreaterThan(duration, 0, "La duración debe ser mayor que 0", file: file, line: line)
        XCTAssertLessThan(duration, 3600, "La duración no debería ser mayor que una hora para tests", file: file, line: line)
    }
}

// MARK: - Test Constants

struct TestConstants {
    static let blackThreshold: CGFloat = 0.05
    static let defaultTestImageSize = CGSize(width: 100, height: 100)
    static let largeTestImageSize = CGSize(width: 1920, height: 1080)
    static let defaultTestDuration: Double = 5.0
    static let blackFrameDuration: Double = 1.0
    
    // Colores de prueba específicos
    struct TestColors {
        static let pureBlack = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
        static let pureWhite = NSColor(red: 1, green: 1, blue: 1, alpha: 1)
        static let darkGray = NSColor(red: 0.03, green: 0.03, blue: 0.03, alpha: 1) // Por debajo del umbral
        static let lightGray = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)   // Por encima del umbral
        static let threshold = NSColor(red: blackThreshold, green: blackThreshold, blue: blackThreshold, alpha: 1)
    }
}