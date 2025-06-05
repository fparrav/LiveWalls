# Live Walls

Una aplicación nativa de macOS para usar videos como fondos de pantalla dinámicos.

## 🎥 Vista General

**Live Walls** te permite convertir cualquier video MP4 o MOV en un fondo de pantalla dinámico para macOS. Los videos se adaptan perfectamente a tu pantalla, funcionan en múltiples monitores y todos los espacios de trabajo, manteniéndose siempre en segundo plano sin interferir con tu flujo de trabajo.

## ✨ Características

- 🎬 **Soporte para videos MP4 y MOV**
- 📱 **Escalado inteligente**: Los videos se ajustan automáticamente con aspect fill
- 🖥️ **Múltiples pantallas**: Funciona en todas las pantallas conectadas
- 🏢 **Todos los escritorios**: Se muestra en todos los espacios de trabajo
- 👻 **Ejecución en segundo plano**: Se mantiene activa sin interferir
- 🎛️ **Interfaz gráfica**: Gestión visual de videos con thumbnails
- 🔄 **Reproducción en loop**: Los videos se repiten automáticamente
- 📍 **Menu bar**: Control desde la barra de menú

## 🚀 Inicio Rápido

### 1. Abrir en Xcode
```bash
./open-xcode.sh
```

### 2. Compilar y Ejecutar
```bash
./build.sh run
```

### 3. Usar la Aplicación
1. Agregar videos con el botón "+"
2. Seleccionar un video de la lista
3. Hacer clic en "Establecer como fondo de pantalla"
4. ¡Disfrutar del fondo dinámico!

## 📋 Requisitos del Sistema

- macOS 14.0 (Sonoma) o superior
- Xcode 15.0 o superior (para compilar)
- Al menos 4GB de RAM
- Espacio en disco para videos

## 🛠️ Instalación

### Compilar desde el código fuente

1. **Clonar el repositorio**:
   ```bash
   git clone [URL_DEL_REPO]
   cd LiveWalls
   ```

2. **Abrir en Xcode**:
   ```bash
   ./open-xcode.sh
   ```

3. **Configurar el proyecto**:
   - Selecciona tu equipo de desarrollo
   - Ajusta el Bundle Identifier si es necesario

4. **Compilar y ejecutar**:
   ```bash
   ./build.sh run
   ```
   O presiona `⌘+R` en Xcode

## 📖 Documentación

- **[USAGE.md](USAGE.md)** - Guía completa de uso
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Documentación técnica para desarrolladores

## 🎛️ Características Técnicas

### Escalado de Video
La aplicación usa `resizeAspectFill` para asegurar que:
- El video cubra toda la pantalla
- Se mantengan las proporciones originales
- No haya barras negras
- Se haga zoom si es necesario para llenar el espacio

### Compatibilidad con Múltiples Pantallas
- Detecta automáticamente todas las pantallas conectadas
- Crea una ventana de video por cada pantalla
- Se adapta automáticamente cuando se conectan/desconectan pantallas
- Funciona con configuraciones de pantalla en espejo o extendida

### Espacios de Trabajo (Spaces)
- Los videos aparecen en todos los espacios de trabajo de macOS
- No interfiere con Mission Control o App Exposé
- Se mantiene siempre por debajo de las ventanas del usuario

## 📁 Estructura del Proyecto

```
LiveWalls/
├── LiveWallsApp.swift          # Punto de entrada de la aplicación
├── ContentView.swift           # Interfaz principal
├── SettingsView.swift          # Ventana de configuración
├── WallpaperManager.swift      # Lógica principal de gestión
├── VideoPlayerView.swift       # Componente de reproductor
├── DesktopVideoWindow.swift    # Ventana del fondo de pantalla
├── VideoFile.swift             # Modelo de datos para videos
├── NotificationManager.swift   # Sistema de notificaciones
├── Assets.xcassets/            # Recursos gráficos
├── build.sh                    # Script de compilación
├── open-xcode.sh              # Script para abrir en Xcode
├── README.md                   # Este archivo
├── USAGE.md                    # Guía de usuario
└── DEVELOPMENT.md              # Documentación técnica
```

## 🔧 Scripts Incluidos

### `build.sh`
Script principal de compilación:
```bash
./build.sh clean   # Limpiar archivos de build
./build.sh build   # Compilar la aplicación
./build.sh run     # Compilar y ejecutar
./build.sh archive # Crear archivo para distribución
```

### `open-xcode.sh`
Abrir el proyecto en Xcode:
```bash
./open-xcode.sh    # Abre LiveWalls.xcodeproj
```

## 🔒 Permisos Requeridos

La aplicación requiere los siguientes permisos (configurados en `LiveWalls.entitlements`):
- ✅ Acceso a archivos seleccionados por el usuario
- ✅ Lectura/escritura de archivos de video
- ✅ App Sandbox habilitado para seguridad

## 🎨 Uso Típico

1. **Agregar videos**: Arrastra videos MP4/MOV a la aplicación
2. **Vista previa**: Selecciona videos para ver un preview
3. **Activar fondo**: Establece cualquier video como fondo de pantalla
4. **Control**: Usa el menu bar para controlar la reproducción
5. **Configurar**: Ajusta calidad y opciones de auto-inicio

## 🐛 Solución de Problemas

### Video no se reproduce
- Verificar formato (MP4/MOV)
- Comprobar que el archivo exista
- Revisar permisos de acceso

### No aparece en múltiples pantallas
- Reiniciar la aplicación
- Verificar configuración de pantallas
- Desconectar/reconectar monitores externos

### Problemas de rendimiento
- Reducir calidad en configuración
- Usar videos de menor resolución
- Cerrar otras aplicaciones que usen video

## 🔮 Roadmap

### Próximas características
- [ ] Soporte para GIFs animados
- [ ] Playlist con rotación automática
- [ ] Efectos de transición entre videos
- [ ] Configuración individual por pantalla
- [ ] Soporte para videos en línea (URLs)
- [ ] Compresión automática de videos grandes

### Mejoras de UX
- [ ] Drag & drop de videos
- [ ] Búsqueda y filtros en la lista
- [ ] Vista en grid para thumbnails
- [ ] Categorías y tags para videos

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Para contribuir:

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

### Guías para Contribuidores

- Sigue las convenciones de código Swift
- Documenta las nuevas funcionalidades
- Incluye tests para funcionalidades críticas
- Actualiza la documentación cuando sea necesario

### Modelo de Contribución Dual

**Live Walls** opera bajo un modelo dual que beneficia a toda la comunidad:

🆓 **Versión Open Source**:
- Código completo disponible (MIT License)
- Desarrollo dirigido por la comunidad
- Ideal para aprender y experimentar
- Base para proyectos derivados

💰 **Versión Comercial** (Mac App Store):
- Interfaz pulida y optimizada
- Soporte técnico oficial
- Actualizaciones automáticas
- Funciones premium exclusivas
- Financia el desarrollo continuo

**¿Cómo ayudan las contribuciones?**
- Las mejoras en código abierto benefician ambas versiones
- Los contributors reciben reconocimiento en ambas versiones  
- Las funciones community-driven pueden llegar a la versión comercial
- Los ingresos comerciales financian más desarrollo open source

**Reconocimiento**: Todos los contributors aparecen en los créditos de ambas versiones.

## 📄 Licencia

Este proyecto está licenciado bajo la **MIT License** - consulta el archivo [LICENSE](LICENSE) para más detalles.

### 🏪 Uso Comercial

**Live Walls** es un proyecto de **código abierto con fines comerciales**:

- ✅ **Código libre**: El código fuente está disponible bajo MIT License
- ✅ **Uso comercial**: Puedes usar, modificar y distribuir libremente
- ✅ **Reconocimiento requerido**: Debes mantener el aviso de copyright
- 🏷️ **Venta oficial**: La versión oficial se vende en Mac App Store
- 🤝 **Contribuciones bienvenidas**: Las mejoras benefician a toda la comunidad

**Si usas este código:**
- Incluye el aviso de copyright en tu distribución
- Menciona "Based on Live Walls by [Tu Nombre]" en los créditos
- Enlaza al repositorio original cuando sea posible

**Diferencias entre versiones:**
- **Código fuente (MIT)**: Gratis, completo, para desarrolladores
- **Mac App Store**: Versión pulida, soporte oficial, actualizaciones automáticas

## 🙏 Créditos

- Desarrollado con Swift y SwiftUI
- Usa AVFoundation para reproducción de video
- Iconos del sistema de SF Symbols
- Comunidad open source por contribuciones y feedback

### 📚 Documentación Adicional

- **[LICENSE](LICENSE)** - Licencia MIT completa
- **[COMMERCIAL.md](COMMERCIAL.md)** - Información detallada del modelo comercial
- **[USAGE.md](USAGE.md)** - Guía completa de uso
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Documentación técnica para desarrolladores

---

**¡Transforma tu escritorio con fondos de pantalla dinámicos!** 🎉

*Proyecto open source con modelo comercial sostenible - Lo mejor de ambos mundos* ✨
