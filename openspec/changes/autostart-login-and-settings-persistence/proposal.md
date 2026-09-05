## Why

Al activar "Iniciar Live Walls con el sistema" la app arranca en el login, pero
la reproducción del wallpaper no se inicia sola: hay que darle a reproducir a
mano después de cada reinicio. Además, el toggle "Iniciar wallpaper
automáticamente" no se conserva de forma fiable: se puede activar en el panel de
Ajustes y encontrarlo apagado en la siguiente sesión.

Ambos problemas tienen causas concretas en el código:

1. **El panel de Ajustes descarta cambios.** `SettingsView` se refactorizó de un
   `.sheet` modal a un panel de vidrio flotante que se cierra al tocar fuera,
   pero conserva el modelo de guardado diferido: los toggles son `@State` local
   y solo se escriben a `UserDefaults` en `saveAllSettings()`, que únicamente
   invoca el botón "Aceptar". Cerrar el panel tocando fuera (`onClose`) o con
   Escape (`.cancelAction`) descarta el cambio en silencio.
2. **El auto-inicio en login es un disparo único y frágil.**
   `attemptAutoStart()` corre una sola vez en el `init` de `WallpaperManager`,
   con una ventana de backoff acotada (~7.7 s) que compite con la carga async de
   la persistencia bajo la contención de disco del login. Si se agota,
   `autoStartScheduled` queda en `true` y nadie reprograma. El único rescate
   (`ensurePlaying()` vía `didBecomeActive`) no dispara en login porque la app
   arranca como `.accessory` en segundo plano y nunca se activa. `resolveBookmark()`
   tampoco reintenta ante volúmenes o iCloud no montados aún.
3. **"Iniciar con el sistema" y "Iniciar wallpaper automáticamente" son ajustes
   independientes** con etiquetas que no dejan clara la relación ("al abrir la
   app" no se lee como "cuando el sistema lanza la app en el login").

## What Changes

- El panel de Ajustes persiste los cambios de preferencias al cerrarse por
  cualquier vía de confirmación (tocar fuera, Escape, "Aceptar"), y solo los
  revierte con una acción explícita de "Cancelar". Se elimina el riesgo de
  perder cambios en silencio para `AutoStartWallpaper`, `MuteVideo`, manejo de
  duplicados y config de auto-cambio.
- El auto-inicio del wallpaper deja de ser un disparo único: se convierte en un
  intento con reintento acotado y rescate posterior, de modo que un fallo
  transitorio en el arranque de login (persistencia lenta, bookmark no
  resoluble, pantallas no listas) no deja la reproducción apagada de forma
  permanente.
- `resolveBookmark()` en la ruta de auto-inicio reintenta de forma acotada ante
  fallos recuperables (volumen/iCloud no montado) antes de rendirse y notificar.
- Se aclara la relación entre "Iniciar con el sistema" y "Iniciar wallpaper
  automáticamente": al activar el arranque con el sistema se ofrece / activa
  también el auto-inicio de reproducción, y se ajusta el copy de ambos toggles y
  su texto de ayuda.

## Capabilities

### New Capabilities

- `settings-persistence`: cómo el panel de Ajustes confirma, descarta y aplica
  los cambios de preferencias del usuario, incluida la semántica de cierre del
  panel (confirmar vs cancelar) y la sincronización con `UserDefaults` y los
  managers.
- `playback-autostart`: inicio automático de la reproducción del wallpaper al
  lanzar la app —incluido el lanzamiento en el login del sistema—, su política
  de reintento y rescate, y su relación con el ajuste "Iniciar con el sistema".

### Modified Capabilities

<!-- Ninguna: no existen specs de lifecycle de reproducción ni de ajustes todavía. -->

## Impact

- **Código afectado:**
  - `LiveWalls/SettingsView.swift` — modelo de guardado (`saveAllSettings`,
    `cancelChanges`, `loadCurrentSettings`, `onClose`).
  - `LiveWalls/ContentView.swift` — `settingsPanel` / `onClose`, catcher de
    tap-outside.
  - `LiveWalls/WallpaperManager.swift` — `attemptAutoStart()`,
    `autoStartScheduled`, `ensurePlaying()`, ruta de `resolveBookmark` en
    `startWallpaperSafe()`.
  - `LiveWalls/StartupCoordinator.swift` — política de reintento / rescate.
  - `LiveWalls/LaunchManager.swift` y `SettingsView` — vínculo entre
    launch-at-login y auto-inicio.
  - `LiveWalls/Resources/Localizations/*.lproj/Localizable.strings` — copy de
    `auto_start_wallpaper`, `launch_at_login`, `launch_at_login_help` (13 idiomas).
- **Preferencias (`UserDefaults`):** `AutoStartWallpaper` (semántica de escritura
  y posible default). Sin migración destructiva.
- **Interacción con la rama en curso:** `wake-recovery-hardening` toca
  `ensurePlaying()` y `StartupCoordinator`; coordinar para evitar conflictos.
- **Sin cambios de API pública ni dependencias nuevas.**
