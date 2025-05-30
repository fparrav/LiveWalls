# Live Walls - Guía de Desarrollo

## Estructura del Proyecto

### Archivos Principales

1. **LiveWallsApp.swift** - Punto de entrada de la aplicación
   - Configura el ciclo de vida de la app
   - Maneja el menu bar y la ejecución en segundo plano
   - Integra el WallpaperManager como environmentObject

2. **WallpaperManager.swift** - Lógica central de la aplicación
   - Gestiona la lista de videos
   - Controla la reproducción de fondos de pantalla
   - Maneja la persistencia de datos
   - Detecta cambios de pantalla

3. **DesktopVideoWindow.swift** - Ventana de fondo de pantalla
   - Crea ventanas transparentes por cada pantalla
   - Configura el reproductor de video con aspect fill
   - Maneja el nivel de ventana para aparecer detrás del escritorio

4. **VideoPlayerView.swift** - Componente de reproductor
   - Vista SwiftUI para reproducir videos
   - Soporta preview y controles básicos
   - Integración con AVKit

5. **ContentView.swift** - Interfaz principal
   - Sidebar con lista de videos
   - Vista de detalle con preview
   - Controles de reproducción

## Funcionalidades Clave

### Escalado de Video (Aspect Fill)
El escalado se maneja en `DesktopVideoWindow.swift`:
```swift
playerView.videoGravity = .resizeAspectFill
```
Esto asegura que:
- El video cubra toda la pantalla
- Se mantengan las proporciones
- Se haga zoom automático si es necesario

### Múltiples Pantallas
La detección de pantallas se hace en `WallpaperManager.swift`:
```swift
let screens = NSScreen.screens
for screen in screens {
    let window = DesktopVideoWindow(screen: screen, videoURL: video.url)
}
```

### Todos los Espacios de Trabajo
Configurado en `DesktopVideoWindow.swift`:
```swift
self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
```

## Configuración del Entorno

### Permisos Requeridos
En `LiveWalls.entitlements`:
- `com.apple.security.files.user-selected.read-only`
- `com.apple.security.files.user-selected.read-write`
- App Sandbox habilitado

### Compilación
Usar el script `build.sh`:
```bash
./build.sh run    # Compilar y ejecutar
./build.sh build  # Solo compilar
./build.sh clean  # Limpiar build
```

## Manejo de Errores

### Archivos No Encontrados
- Verificación en `addVideoFiles()` antes de agregar
- Validación en `startWallpaper()` antes de reproducir
- Notificaciones de error al usuario

### Formatos No Soportados
- Filtro por extensión (.mp4, .mov)
- Mensajes informativos en consola

### Pantallas Desconectadas
- Observer para `NSApplication.didChangeScreenParametersNotification`
- Recreación automática de ventanas

## Persistencia de Datos

### UserDefaults
- Lista de videos: JSON codificado
- Video actual: JSON codificado
- Configuraciones de usuario

### Thumbnails
- Generación asíncrona con AVAssetImageGenerator
- Almacenamiento como Data en el modelo VideoFile
- Guardado automático en UserDefaults

## Optimizaciones

### Performance
- Thumbnails de tamaño limitado (200x200)
- Videos silenciados por defecto
- Limpieza de observers en deinit

### Memoria
- Weak references en closures
- Cleanup apropiado de AVPlayer
- Destrucción de ventanas al cambiar video

## Testing

### Manual Testing
1. **Agregar Videos**:
   - Seleccionar múltiples archivos .mp4/.mov
   - Verificar generación de thumbnails
   - Comprobar que aparezcan en la lista

2. **Fondo de Pantalla**:
   - Activar un video
   - Verificar que aparezca en todas las pantallas
   - Probar con múltiples espacios de trabajo

3. **Cambios de Pantalla**:
   - Conectar/desconectar monitor externo
   - Verificar recreación automática de ventanas

### Casos Edge
- Videos muy grandes (>4K)
- Archivos corruptos o inaccesibles
- Cambios rápidos de video
- Múltiples instancias de la app

## Futuras Mejoras

### Performance
- [ ] Compression automática de videos grandes
- [ ] Caching inteligente de thumbnails
- [ ] Lazy loading de preview videos

### Funcionalidades
- [ ] Soporte para GIFs
- [ ] Playlist con rotación automática
- [ ] Efectos de transición
- [ ] Configuración por pantalla individual

### UX
- [ ] Drag & drop de videos
- [ ] Búsqueda y filtros
- [ ] Categorías de videos
- [ ] Vista en grid/lista

## Troubleshooting

### La app no aparece en el Dock
**Normal** - Configurado como `accessory` app. Usar el menu bar.

### Video no se reproduce
1. Verificar formato (MP4/MOV)
2. Comprobar permisos de archivo
3. Revisar logs en consola
4. Verificar espacio en disco

### No aparece en múltiples pantallas
1. Reiniciar la app
2. Verificar configuración de pantallas en Sistema
3. Comprobar que las pantallas estén en modo extendido

### Performance issues
1. Reducir calidad de video en configuración
2. Cerrar otras apps que usen video
3. Verificar uso de CPU/memoria en Activity Monitor
