# 🚀 Mejores Prácticas: AVPlayer en Swift vs Objective-C

## 📋 Resumen del Problema

Tu app de wallpaper está experimentando crashes al detener/cambiar videos. Esto es común en Swift debido a diferencias fundamentales con Objective-C en la gestión de memoria y concurrencia.

## 🔍 Principales Diferencias Swift vs Objective-C

### **1. Gestión de Memoria**
- **Objective-C**: Control manual con `retain`/`release`
- **Swift**: ARC automático, pero requiere atención a **reference cycles**

### **2. Observadores KVO**
- **Objective-C**: `addObserver`/`removeObserver` manual
- **Swift**: Usar `NSKeyValueObservation` con invalidación automática

### **3. Concurrencia y Thread Safety**
- **Swift**: `async/await` y `@MainActor` para UI
- **Objective-C**: Manual con GCD

## 🛡️ Problemas Comunes y Soluciones

### **Problema 1: Double Release de Observadores KVO**
```swift
// ❌ MAL - Puede causar crashes
var observer: NSKeyValueObservation?
player.removeObserver(self, forKeyPath: "status") // Crash si ya se removió

// ✅ BIEN - Gestión segura con NSKeyValueObservation
private var observations: [NSKeyValueObservation] = []

let statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, change in
    // Manejo seguro
}
observations.append(statusObservation)

// Limpieza automática en deinit o manual:
observations.forEach { $0.invalidate() }
observations.removeAll()
```

### **Problema 2: Race Conditions en Cambio de Videos**
```swift
// ❌ MAL - Race condition
func setActiveVideo(_ video: VideoFile) {
    stopWallpaper()      // Async
    startWallpaper()     // Se ejecuta antes que termine stop
}

// ✅ BIEN - Sincronización con semáforos/queues
private let wallpaperOperationQueue = DispatchQueue(label: "wallpaper.operations", qos: .userInitiated)
private let wallpaperOperationSemaphore = DispatchSemaphore(value: 1)

func setActiveVideo(_ video: VideoFile) {
    wallpaperOperationQueue.async { [weak self] in
        self?.wallpaperOperationSemaphore.wait()
        
        // Operaciones sincronizadas aquí
        self?.stopWallpaperInternal { [weak self] in
            self?.startWallpaperInternal { success in
                self?.wallpaperOperationSemaphore.signal()
            }
        }
    }
}
```

### **Problema 3: Limpieza Incorrecta de AVPlayer**
```swift
// ❌ MAL - Orden incorrecto puede causar crashes
player = nil
playerLayer = nil
playerItem = nil

// ✅ BIEN - Secuencia correcta de limpieza
func cleanupPlayerSafely() {
    // 1. Pausar primero
    player?.pause()
    
    // 2. Invalidar observadores
    observations.forEach { $0.invalidate() }
    observations.removeAll()
    
    // 3. Desconectar capa
    playerLayer?.player = nil
    playerLayer?.removeFromSuperlayer()
    
    // 4. Limpiar player
    player?.replaceCurrentItem(with: nil)
    
    // 5. Limpiar referencias
    playerLayer = nil
    player = nil
    playerItem = nil
}
```

### **Problema 4: Security-Scoped Resources Leaks**
```swift
// ❌ MAL - No trackear el estado puede causar crashes
url.stopAccessingSecurityScopedResource() // Crash si ya se detuvo

// ✅ BIEN - Trackear estado de recursos
private var activeSecurityScopedURLs: Set<String> = []

private func safeStartSecurityScopedAccess(for url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    
    if url.startAccessingSecurityScopedResource() {
        activeSecurityScopedURLs.insert(path)
        return true
    }
    return false
}

private func safeStopSecurityScopedAccess(for url: URL) {
    let path = url.standardizedFileURL.path
    
    if activeSecurityScopedURLs.contains(path) {
        url.stopAccessingSecurityScopedResource()
        activeSecurityScopedURLs.remove(path)
    }
}
```

## 🎯 Implementación Recomendada

### **1. Crear Gestor de Recursos Especializado**
```swift
final class VideoPlayerResourceManager {
    private var observations: [NSKeyValueObservation] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var isCleaningUp = false
    
    func setupSafeObservers(player: AVPlayer, playerItem: AVPlayerItem) {
        // Configurar observadores seguros
    }
    
    func cleanupAllResources() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        
        // Limpieza ordenada y segura
    }
}
```

### **2. Mejorar DesktopVideoWindow**
```swift
class DesktopVideoWindow: NSWindow {
    private var resourceManager: VideoPlayerResourceManager?
    private var isClosing = false
    
    override func close() {
        guard !isClosing else { return }
        isClosing = true
        
        resourceManager?.cleanupAllResources()
        super.close()
    }
}
```

### **3. Usar async/await para Configuración**
```swift
private func setupPlayer(with url: URL) async {
    let asset = AVURLAsset(url: url)
    
    do {
        let (isPlayable, tracks) = try await asset.load(.isPlayable, .tracks)
        
        guard isPlayable else {
            throw VideoPlayerError.notPlayable
        }
        
        await MainActor.run {
            self.configurePlayerOnMainThread(asset)
        }
    } catch {
        await MainActor.run {
            self.handleError(error)
        }
    }
}
```

## 🔧 Cambios Inmediatos Recomendados

### **1. En DesktopVideoWindow.swift:**
- Reemplazar observadores KVO manuales con `NSKeyValueObservation`
- Implementar limpieza ordenada en `cleanupResources()`
- Usar `weak self` en todos los closures

### **2. En WallpaperManager.swift:**
- Sincronizar operaciones de start/stop con semáforos
- Mejorar tracking de security-scoped resources
- Implementar timeouts para operaciones de transición

### **3. Añadir Logging Detallado:**
```swift
private let memoryLogger = Logger(subsystem: "com.livewalls.app", category: "MemoryManagement")

func criticalOperation() {
    memoryLogger.info("🔄 Iniciando operación crítica")
    // ...operación...
    memoryLogger.info("✅ Operación completada")
}
```

## 🚨 Pasos de Debugging

1. **Activar logs detallados** en todas las operaciones críticas
2. **Instrumentar con Xcode** para detectar memory leaks
3. **Probar transiciones rápidas** entre videos para reproducir crashes
4. **Verificar thread safety** de todas las operaciones UI

## 📈 Siguiente Pasos

1. Implementar `VideoPlayerResourceManager` como clase auxiliar
2. Refactorizar `DesktopVideoWindow` para usar el gestor
3. Mejorar sincronización en `WallpaperManager`
4. Añadir tests unitarios para casos de edge

¿Te gustaría que implemente alguna de estas mejoras específicas en tu código actual?
