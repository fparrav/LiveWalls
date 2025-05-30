#!/usr/bin/env swift

import Foundation
import AVFoundation

let videoPath = "/System/Library/CoreServices/NotificationCenter.app/Contents/Resources/mac_widgets-edu_small.mov"
let url = URL(fileURLWithPath: videoPath)

print("Probando carga de video: \(videoPath)")
print("URL: \(url)")

// Verificar que el archivo existe
if FileManager.default.fileExists(atPath: videoPath) {
    print("✅ El archivo existe")
} else {
    print("❌ El archivo no existe")
    exit(1)
}

// Crear AVAsset
let asset = AVAsset(url: url)

// Cargar propiedades asíncronamente
let semaphore = DispatchSemaphore(value: 0)

asset.loadValuesAsynchronously(forKeys: ["playable", "duration", "tracks"]) {
    print("\n📄 Propiedades del video cargadas:")
    
    var error: NSError?
    let status = asset.statusOfValue(forKey: "playable", error: &error)
    
    print("Status: \(status.rawValue)")
    if let error = error {
        print("❌ Error: \(error.localizedDescription)")
    } else {
        print("✅ Sin errores al cargar")
    }
    
    if asset.isPlayable {
        print("✅ El video es reproducible")
        print("📏 Duración: \(asset.duration.seconds) segundos")
        
        let videoTracks = asset.tracks(withMediaType: .video)
        print("🎬 Tracks de video: \(videoTracks.count)")
        
        if let videoTrack = videoTracks.first {
            print("📐 Tamaño natural: \(videoTrack.naturalSize)")
        }
    } else {
        print("❌ El video NO es reproducible")
    }
    
    semaphore.signal()
}

semaphore.wait()
print("\n🏁 Prueba completada")
