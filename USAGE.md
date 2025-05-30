# Live Walls - Instrucciones de Instalación y Uso

## 🎥 ¿Qué es Live Walls?

**Live Walls** es una aplicación nativa de macOS que te permite usar videos como fondos de pantalla dinámicos. Los videos se adaptan perfectamente a tu pantalla manteniendo las proporciones correctas y funcionan en todos los escritorios y pantallas conectadas.

## ✨ Características Principales

- 🎬 **Soporte para MP4 y MOV**: Compatible con los formatos de video más comunes
- 📱 **Escalado Inteligente**: Los videos se ajustan automáticamente con aspect fill (sin distorsión)
- 🖥️ **Múltiples Pantallas**: Funciona en todas las pantallas conectadas simultáneamente  
- 🏢 **Todos los Escritorios**: Se muestra en todos los espacios de trabajo de macOS
- 👻 **Segundo Plano**: Corre silenciosamente sin interferir con tu trabajo
- 🎛️ **Gestión Visual**: Interfaz gráfica para administrar tus videos con thumbnails
- 🔄 **Reproducción Continua**: Los videos se repiten automáticamente en loop
- 📍 **Menu Bar**: Control rápido desde la barra de menú

## 🛠️ Instalación

### Método 1: Compilar desde el código fuente

1. **Clonar o descargar** este proyecto
2. **Abrir Terminal** y navegar a la carpeta del proyecto:
   ```bash
   cd /Users/felipe/source-code/swift/LiveWalls
   ```

3. **Compilar y ejecutar** usando el script incluido:
   ```bash
   ./build.sh run
   ```

4. **O compilar con Xcode**:
   - Abrir `LiveWalls.xcodeproj` en Xcode
   - Seleccionar tu equipo de desarrollo
   - Presionar `⌘+R` para compilar y ejecutar

### Requisitos del Sistema
- macOS 14.0 (Sonoma) o superior
- Xcode 15.0 o superior (para compilar)
- Al menos 4GB de RAM recomendados
- Espacio en disco para videos

## 🚀 Primeros Pasos

### 1. Ejecutar la Aplicación
- Al iniciar, Live Walls aparecerá en la barra de menú (🎥)
- La ventana principal se abrirá automáticamente la primera vez

### 2. Agregar Videos
1. Haz clic en el botón **"+"** en la barra lateral
2. Selecciona uno o más archivos de video (.mp4 o .mov)
3. Los videos aparecerán en la lista con thumbnails generados automáticamente

### 3. Establecer como Fondo de Pantalla
1. **Selecciona un video** de la lista
2. Haz clic en **"Establecer como fondo de pantalla"**
3. O usa el **menú contextual** (clic derecho) → "Establecer como fondo"

### 4. Controlar la Reproducción
- **Iniciar/Detener**: Botón de play/stop en la parte inferior
- **Menu Bar**: Acceso rápido desde el ícono de la barra de menú
- **Auto-inicio**: Se puede configurar para iniciar automáticamente

## 📖 Uso Detallado

### Gestión de Videos

#### Agregar Videos
- **Formatos soportados**: MP4, MOV
- **Múltiples archivos**: Puedes seleccionar varios videos a la vez
- **Ubicación**: Los videos pueden estar en cualquier carpeta de tu sistema
- **Thumbnails**: Se generan automáticamente para vista previa

#### Organizar Videos
- **Lista lateral**: Todos tus videos aparecen organizados
- **Vista previa**: Selecciona un video para ver un preview en la zona principal
- **Información**: Nombre del archivo y ubicación completa
- **Eliminar**: Clic derecho → "Eliminar" para quitar videos de la lista

### Configuración del Fondo de Pantalla

#### Escalado de Video
- **Aspect Fill**: Los videos mantienen sus proporciones originales
- **Sin distorsión**: No se estiran ni deforman
- **Cobertura completa**: El video siempre cubre toda la pantalla
- **Zoom automático**: Si es necesario, se hace zoom para llenar el espacio

#### Múltiples Pantallas
- **Detección automática**: Reconoce todas las pantallas conectadas
- **Sincronización**: El mismo video se reproduce en todas las pantallas
- **Adaptación dinámica**: Se ajusta automáticamente al conectar/desconectar pantallas
- **Configuraciones mixtas**: Funciona con pantallas de diferentes resoluciones

#### Espacios de Trabajo (Spaces)
- **Todos los escritorios**: El fondo se muestra en todos los espacios de trabajo
- **Mission Control**: No interfiere con la vista de Mission Control
- **App Exposé**: No aparece en la vista de aplicaciones
- **Cambio de espacios**: El fondo permanece constante al cambiar entre espacios

### Controles de Reproducción

#### Iniciar/Detener
- **Botón principal**: En la ventana de la app
- **Menu bar**: Desde el ícono de la barra de menú
- **Estado visual**: Indicador verde cuando hay un video activo

#### Configuración Avanzada
- **Auto-inicio**: Iniciar fondo automáticamente al abrir la app
- **Calidad**: Ajustar calidad de reproducción (baja, media, alta)
- **Silencio**: Los videos están silenciados por defecto

## 🎛️ Configuración

### Acceder a Configuración
1. **Menu bar** → "Abrir Configuración"
2. O desde la ventana principal → botón "Configuración"

### Opciones Disponibles
- **Auto-inicio**: Iniciar fondo de pantalla automáticamente
- **Calidad de video**: Baja/Media/Alta (afecta el rendimiento)
- **Silenciar videos**: Controlar audio de los videos
- **Gestión de videos**: Limpiar lista de videos guardados

## 🔧 Solución de Problemas

### El video no se reproduce
**Posibles causas:**
- Formato no soportado → Usar MP4 o MOV
- Archivo dañado → Probar con otro video
- Permisos insuficientes → Verificar acceso al archivo
- Espacio en disco → Liberar espacio si es necesario

**Soluciones:**
1. Verificar que el archivo existe y es accesible
2. Probar con un video diferente
3. Reiniciar la aplicación
4. Revisar los logs en Consola.app

### No aparece en todas las pantallas
**Soluciones:**
1. **Desconectar y reconectar** pantallas externas
2. **Reiniciar la aplicación**
3. Verificar **configuración de pantallas** en Preferencias del Sistema
4. Asegurar que las pantallas estén en **modo extendido** (no espejo)

### Problemas de rendimiento
**Optimizaciones:**
1. **Reducir calidad** en configuración (baja en lugar de alta)
2. **Videos más pequeños** (resolución menor)
3. **Cerrar otras apps** que usen video intensivamente
4. **Verificar uso de CPU** en Monitor de Actividad

### La app no aparece en el Dock
**Esto es normal** - Live Walls está configurada para ejecutarse en segundo plano:
- Accede desde el **ícono de la barra de menú** (🎥)
- O desde **"Abrir Configuración"** en el menu bar
- Para salir completamente: Menu bar → "Salir"

## 🎨 Consejos y Mejores Prácticas

### Selección de Videos
- **Resolución**: Videos de 1080p o 4K funcionan mejor
- **Duración**: Videos de 10-60 segundos son ideales para loops
- **Contenido**: Escenas suaves se ven mejor como fondo
- **Tamaño**: Archivos de menos de 100MB para mejor rendimiento

### Performance
- **Una sola instancia**: No ejecutes múltiples copias de la app
- **Recursos del sistema**: Monitor el uso de CPU/memoria
- **Batería**: En laptops, puede afectar la duración de la batería
- **Calidad adaptativa**: Usar calidad baja si experimentas lag

### Organización
- **Carpeta dedicada**: Mantén tus videos de fondo en una carpeta específica
- **Nombres descriptivos**: Usa nombres claros para tus videos
- **Backup**: Respalda tus videos favoritos
- **Pruebas**: Prueba videos antes de usarlos como fondo

## 🆘 Obtener Ayuda

### Logs del Sistema
Para diagnosticar problemas:
1. Abrir **Consola.app**
2. Filtrar por **"LiveWalls"**
3. Reproducir el problema
4. Revisar mensajes de error

### Información del Sistema
- **Versión de macOS**: Preferencias del Sistema → Acerca de este Mac
- **Pantallas conectadas**: Preferencias del Sistema → Pantallas
- **Espacio disponible**: Finder → Aplicaciones → Utilidades → Información del Sistema

### Contacto y Reporte de Bugs
Si encuentras problemas:
1. Describe el comportamiento esperado vs actual
2. Incluye información del sistema (macOS, modelo de Mac)
3. Adjunta logs relevantes de Consola.app
4. Especifica los pasos para reproducir el problema

## 📝 Licencia y Código Fuente

Este proyecto es de **código abierto**. Puedes:
- ✅ Usar la aplicación libremente
- ✅ Modificar el código fuente
- ✅ Distribuir versiones modificadas
- ✅ Contribuir con mejoras

**¡Disfruta de tus fondos de pantalla dinámicos!** 🎉
