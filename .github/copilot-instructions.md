# Instrucciones personalizadas para GitHub Copilot en LiveWalls

Utiliza comentarios claros y descriptivos en español para todo el código nuevo o modificado.
Prioriza la seguridad y la gestión correcta de recursos en código que interactúa con AVFoundation, AppKit y recursos del sistema.
Prefiere patrones de diseño robustos para la gestión de memoria y recursos (por ejemplo, uso seguro de security-scoped bookmarks, observers y recursos de video).
Si se detectan errores de acceso a memoria, race conditions o problemas de concurrencia, prioriza la solución de estos antes de agregar nuevas funcionalidades.
Toda función pública debe tener documentación breve sobre su propósito y uso.
Los cambios que afecten la experiencia de usuario deben ser probados en todos los modos de pantalla y con múltiples videos.
Si se detecta código duplicado, sugiere refactorización.
Si el código Swift interactúa con recursos del sistema (archivos, ventanas, notificaciones), asegúrate de manejar correctamente los permisos y errores.

Usa SwiftLint y Prettier para mantener el formato del código.
Nombra las variables y funciones en español salvo APIs estándar.
Prefiere structs para modelos de datos y clases para controladores/gestores.
Mantén los archivos por debajo de 500 líneas cuando sea posible; sugiere modularización si se excede.
Crea commits utilizando conventional commits y gitmoji.
  
---
## Información del repositorio GitHub para integraciones automáticas

- **Owner:** `fparrav`
- **Repo:** `LiveWalls`
---