#!/bin/bash

echo "🚀 LiveWalls - Script de Prueba"
echo "================================="

# Verificar que el proyecto se compila correctamente
echo "1. Compilando proyecto..."
xcodebuild -project LiveWalls.xcodeproj -scheme LiveWalls -configuration Debug build

if [ $? -eq 0 ]; then
    echo "✅ Compilación exitosa"
else
    echo "❌ Error en compilación"
    exit 1
fi

# Mostrar información del ejecutable
EXECUTABLE_PATH="/Users/felipe/Library/Developer/Xcode/DerivedData/LiveWalls-dpzwjwbcnceloleomdowsvaavtrx/Build/Products/Debug/LiveWalls.app"

echo "2. Información del ejecutable:"
echo "   Ubicación: $EXECUTABLE_PATH"
echo "   Tamaño: $(du -h "$EXECUTABLE_PATH" | cut -f1)"

# Verificar permisos y firma
echo "3. Verificando firma de código..."
codesign -dv "$EXECUTABLE_PATH" 2>&1

echo "4. Verificando frameworks incluidos..."
ls -la "$EXECUTABLE_PATH/Contents/Frameworks/" 2>/dev/null || echo "   No hay frameworks adicionales"

echo "5. Mostrando Info.plist..."
plutil -p "$EXECUTABLE_PATH/Contents/Info.plist"

echo ""
echo "🎯 Para probar la aplicación:"
echo "   1. Ejecutar: open '$EXECUTABLE_PATH'"
echo "   2. O usar Xcode para depuración"
echo "   3. Verificar que aparece el icono en la barra de menú"
echo "   4. Seleccionar videos MOV/MP4 desde el menú"
echo "   5. Verificar que los videos aparecen como fondo en todos los escritorios"

echo ""
echo "📋 Funcionalidades a verificar:"
echo "   ✓ Interfaz en barra de menú"
echo "   ✓ Selección de archivos de video"
echo "   ✓ Generación de miniaturas"
echo "   ✓ Reproducción en fondo de escritorio"
echo "   ✓ Soporte multi-pantalla"
echo "   ✓ Aspect fill sin distorsión"
echo "   ✓ Ejecución en segundo plano"
