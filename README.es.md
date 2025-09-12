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

1. Ve a [GitHub Releases](https://github.com/fparrav/LiveWalls/releases)
2. Descarga el archivo `.dmg` más reciente
3. Abre el DMG y arrastra LiveWalls a Aplicaciones

### 🍺 Instalación con Homebrew (Recomendado para usuarios avanzados)

**¿No tienes Homebrew?** [Instálalo aquí](https://brew.sh)

```bash
brew tap fparrav/livewalls
brew install livewalls
```

**Ventajas del método Homebrew:**
- ✅ Instalación automática sin configuración manual
- ✅ Sin problemas de quarantine de macOS  
- ✅ Actualizaciones fáciles con `brew upgrade`

**📋 Nota:** LiveWalls no está en el repositorio oficial de Homebrew porque requiere certificado Apple Developer ($99/año) para apps firmadas. Como proyecto open source gratuito, usamos un "tap" personal que permite distribución segura de apps no firmadas.

## 🔄 Actualizaciones automáticas (Sparkle)

LiveWalls integra un actualizador con Sparkle para que el usuario decida instalar, cancelar u omitir una versión. Para que funcione en CI y se publique automáticamente:

1) Habilita GitHub Pages del repo (Source: GitHub Actions)
2) Agrega el secreto `SPARKLE_PRIVATE_KEY` (contenido de tu clave EdDSA privada de Sparkle)
3) Asegúrate de que `SUFeedURL` en `LiveWalls/Info.plist` apunte a `https://<owner>.github.io/<repo>/sparkle/appcast.xml` (por defecto apunta a tu repo).
4) Genera un tag con `./scripts/create-release.sh 1.5.2` (o sin arg para patch auto)

El workflow de GitHub Actions:
- Compila y genera el DMG
- Firma el update (Sparkle) y genera `appcast.xml`
- Publica DMG y `appcast.xml` en GitHub Pages (`/sparkle/`)
- Actualiza el Release y Homebrew

### Integración en Xcode (Sparkle 2)

- Añade Sparkle con Swift Package Manager en Xcode:
  - File → Add Packages… → `https://github.com/sparkle-project/Sparkle`
  - Producto a añadir: `Sparkle` (para el target `LiveWalls`). Xcode añadirá los XPC de Sparkle automáticamente.
- Claves en `LiveWalls/Info.plist` (ya presentes):
  - `SUFeedURL` → `https://<owner>.github.io/<repo>/sparkle/appcast.xml`
  - `SUPublicEDKey` → tu clave pública EdDSA (reemplaza `REPLACE_WITH_EDDSA_PUBLIC_KEY`).
  - `SUEnableAutomaticChecks` = `true` (busca en segundo plano)
  - `SUAllowsAutomaticUpdates` = `false` (el usuario decide instalar)
- Código: ya existe `InAppUpdater` que usa `SPUStandardUpdaterController` si Sparkle está disponible (`canImport(Sparkle)`) y expone:
  - Check manual: `InAppUpdater.shared.checkForUpdates()` (botón en Ajustes, Acerca de y menú).
  - Check en arranque: `InAppUpdater.shared.checkOnLaunchAndNotify()` (en `AppDelegate`).

### Generar claves Sparkle (EdDSA)

1) Descarga Sparkle local o usa herramientas del release de Sparkle:
   - `generate_keys` (CLI de Sparkle) produce `ed25519_private.pem` y `ed25519_public.pem`.
2) Copia el contenido de `ed25519_public.pem` en `SUPublicEDKey` (Info.plist).
3) Añade el contenido de `ed25519_private.pem` a un secreto de GitHub `SPARKLE_PRIVATE_KEY`.

Al publicar un tag con `./scripts/create-release.sh`, el workflow:
- Firmará el DMG con tu clave privada (CLI `sign_update`).
- Generará `appcast.xml` (CLI `generate_appcast`).
- Subirá `/public/sparkle/` a GitHub Pages. La app leerá ese feed en `SUFeedURL`.

### Seguridad de claves y artefactos

- No commitees tu clave privada Sparkle. El repo ignora: `private_eddsa.pem`, `ed25519_*.pem`, `public/` y `*.tar.xz`.
- Sube la privada como secreto `SPARKLE_PRIVATE_KEY` en GitHub Actions.
- El `appcast.xml` y DMGs se publican vía GitHub Actions (no van al repo).

### ⚠️ Importante: Aplicación sin firma digital

**LiveWalls es un proyecto open source** y no cuenta con certificado de desarrollador de Apple ($99/año).
Para abrir la aplicación por primera vez:

#### Método 1: Comando Terminal (Recomendado)
```bash
xattr -d com.apple.quarantine /Applications/LiveWalls.app
```

#### Método 2: Configuración del Sistema
1. Intenta abrir LiveWalls (aparecerá un aviso de seguridad)
2. Ve a **Configuración del Sistema** → **Privacidad y Seguridad**  
3. En la sección "Seguridad", haz clic en **"Abrir de todos modos"**

#### Método 3: Click derecho
1. Haz **click derecho** en LiveWalls.app
2. Selecciona **"Abrir"**
3. Confirma **"Abrir"** en el diálogo de seguridad

## 🛠️ Compilar desde código fuente

1. **Clonar el repositorio**:
   ```bash
   git clone https://github.com/fparrav/LiveWalls.git
   cd LiveWalls
   ```

2. **Abrir en Xcode**:
   ```bash
   open LiveWalls.xcodeproj
   ```

3. **Compilar y ejecutar**:
   - Presiona `⌘+R` en Xcode
   - O usa el script: `./build.sh run`

## 🔒 Permisos y Seguridad

### Permisos requeridos:

- ✅ Acceso a archivos seleccionados por el usuario
- ✅ App Sandbox habilitado para seguridad

### 🛡️ Sobre la seguridad de LiveWalls

**LiveWalls es un proyecto 100% open source** que puedes revisar y compilar tú mismo. 

**¿Por qué no está firmada digitalmente?**
- La membresía de Apple Developer cuesta $99 USD/año
- Como proyecto gratuito y open source, preferimos esos recursos para desarrollo
- El código fuente está disponible para inspección completa

**💡 Para máxima seguridad:**
1. **Revisa el código fuente** en este repositorio
2. **Compila la aplicación** desde el código fuente (instrucciones abajo)
3. **Verifica** que hace exactamente lo que promete

**📋 Nota importante**: Este es un proyecto de código abierto sin fines de lucro. No pagamos la suscripción de Apple Developer para este tipo de aplicaciones. Si prefieres máxima seguridad, recomendamos compilar el código tú mismo siguiendo las instrucciones de abajo.

## 🤝 Contribuir

¡Las contribuciones son bienvenidas!

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/mi-mejora`)
3. Commit tus cambios (`git commit -m 'Agrega mi-mejora'`)
4. Push a la rama (`git push origin feature/mi-mejora`)
5. Abre un Pull Request

## Licencia

Este proyecto está licenciado bajo la **MIT License** - consulta el archivo [LICENSE](LICENSE) para más detalles.

## 🙏 Créditos y Agradecimientos

- **Inspiración**: Este proyecto fue inspirado por [LiveWallpaperMacOS](https://github.com/thusvill/LiveWallpaperMacOS), reimplementado desde cero en Swift/SwiftUI
- **Desarrollado con**: Swift, SwiftUI y AVFoundation
- **Iconos**: SF Symbols de Apple

---

**¡Transforma tu escritorio con fondos de pantalla dinámicos!** 🎉
