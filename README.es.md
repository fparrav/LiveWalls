# LiveWalls

<p align="center">
  <img src="icon_asset/icono-macOS-Default-1024x1024@2x.png" alt="LiveWalls" width="200" height="200">
</p>

## 📖 Leer en otros idiomas

[🇺🇸 English](README.en.md) | [🇪🇸 Español](README.es.md) | [🇫🇷 Français](README.fr.md) | [🇩🇪 Deutsch](README.de.md) | [🇮🇹 Italiano](README.it.md)

[🇯🇵 日本語](README.ja.md) | [🇰🇷 한국어](README.ko.md) | [🇧🇷 Português](README.pt-BR.md) | [🇨🇳 简体中文](README.zh-CN.md) | [🇹🇼 繁體中文](README.zh-TW.md)

---

Una aplicación nativa de macOS para usar videos como fondos de pantalla dinámicos.

## 🎥 ¿Qué es LiveWalls?

**LiveWalls** te permite convertir cualquier video MP4 o MOV en un fondo de pantalla dinámico para macOS. Los videos se adaptan perfectamente a tu pantalla, funcionan en múltiples monitores y se mantienen siempre en segundo plano sin interferir con tu trabajo.

## ✨ Características

- 🎬 **Soporte para videos MP4 y MOV**
- 📱 **Escalado inteligente**: Los videos se ajustan automáticamente a tu pantalla
- 🖥️ **Múltiples pantallas**: Funciona en todas las pantallas conectadas
- 🏢 **Todos los escritorios**: Se muestra en todos los espacios de trabajo de macOS
- 👻 **Ejecución en segundo plano**: No interfiere con otras aplicaciones
- 🎛️ **Interfaz gráfica**: Gestión visual de videos con thumbnails
- 🔄 **Reproducción en loop**: Los videos se repiten automáticamente
- 📍 **Menú en status bar**: Control rápido desde la barra de menú
- 🚀 **Inicio automático**: Opción para iniciar con el sistema
- ⚙️ **Persistencia**: Recuerda tu último wallpaper al reiniciar

## 🎮 Uso

### 1. Agregar Videos

- Haz clic en el botón "+" para seleccionar videos
- Arrastra archivos MP4 o MOV a la aplicación

### 2. Establecer Wallpaper

- Selecciona un video de la lista
- Haz clic en "Establecer como Wallpaper"
- ¡Disfruta tu fondo dinámico!

### 3. Control Rápido

- Usa el ícono en la barra de menú para controlar la reproducción
- Activa/desactiva el inicio automático
- Abre la aplicación desde el background

## 📋 Requisitos

- macOS 14.0 (Sonoma) o superior
- Xcode 15.0 o superior (para compilar desde código)

## ⚙️ Instalación

### 📥 Descarga Release (Recomendado)

Descarga la última versión compilada desde [GitHub Releases](https://github.com/fparrav/LiveWalls/releases/latest).

**⚠️ Importante:** Como la app no está firmada con un certificado de Apple Developer, necesitarás permitir manualmente que se ejecute.

#### Método 1: Comando Terminal (Recomendado)

```bash
sudo xattr -rd com.apple.quarantine /ruta/a/LiveWalls.app
```

#### Método 2: Configuración del Sistema

1. Intenta abrir LiveWalls (aparecerá un aviso de seguridad)
2. Ve a **Configuración del Sistema** → **Privacidad y Seguridad**
3. Busca "LiveWalls fue bloqueado" y haz clic en **"Abrir de todas formas"**

#### Método 3: Click derecho

1. Haz **click derecho** en LiveWalls.app
2. Selecciona **"Abrir"** del menú contextual
3. Haz clic en **"Abrir"** en el diálogo de seguridad

### 🛠️ Compilar desde Código

   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

   ```bash
   ./build.sh
   ```

   La app compilada estará en la carpeta `build/Debug/`.

## 🔒 Seguridad y Privacidad

### Permisos requeridos

- **Accesibilidad**: Para establecer el wallpaper en el escritorio
- **Archivos y Carpetas**: Para acceder a los videos seleccionados

**LiveWalls es un proyecto 100% open source** que puedes revisar y compilar tú mismo.

### ¿Por qué la app no está firmada?

- La membresía de Apple Developer cuesta $99 USD/año
- Este es un proyecto gratuito sin fines comerciales
- Puedes verificar la seguridad revisando el código fuente

### Cómo verificar la seguridad

1. **Revisa el código fuente** en este repositorio
2. **Compila tú mismo** usando Xcode
3. **Inspecciona el build** antes de ejecutarlo

## 🚀 Desarrollo

Para desarrolladores que quieran contribuir o entender mejor el código, consulta la documentación de desarrollo.

## 📄 Licencia

Este proyecto está bajo la Licencia MIT. Ver el archivo `LICENSE` para más detalles.

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas! Por favor:

1. Haz fork del repositorio
2. Crea una rama para tu característica
3. Realiza tus cambios
4. Envía un pull request

## ⭐ Apoyo

Si te gusta LiveWalls, ¡por favor dale una estrella en GitHub! Esto ayuda a otros usuarios a descubrir el proyecto.

---

Hecho con ❤️ para la comunidad de macOS
