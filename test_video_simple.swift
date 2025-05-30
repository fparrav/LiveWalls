#!/usr/bin/env swift

import Foundation
import AVFoundation

print("=== Prueba de Video LiveWalls ===")

let videoPath = "/System/Library/CoreServices/NotificationCenter.app/Contents/Resources/mac_widgets-edu_small.mov"
print("Probando: \(videoPath)")

let url = URL(fileURLWithPath: videoPath)
print("URL creada: \(url)")

if FileManager.default.fileExists(atPath: videoPath) {
    print("✅ Archivo existe")
    
    let asset = AVAsset(url: url)
    print("✅ AVAsset creado")
    
    // Usar la nueva API síncrona para probar
    do {
        let duration = try await asset.load(.duration)
        print("✅ Duración: \(duration.seconds) segundos")
    } catch {
        print("❌ Error cargando duración: \(error)")
    }
    
} else {
    print("❌ Archivo no existe")
}

print("Fin de la prueba")
