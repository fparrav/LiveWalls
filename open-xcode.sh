#!/bin/bash

# Script para abrir Live Walls en Xcode
# Uso: ./open-xcode.sh

set -e

PROJECT_DIR="/Users/felipe/source-code/swift/LiveWalls"
PROJECT_FILE="${PROJECT_DIR}/LiveWalls.xcodeproj"

echo "🚀 Abriendo Live Walls en Xcode..."

if [ ! -d "$PROJECT_FILE" ]; then
    echo "❌ Error: No se encontró el archivo del proyecto en $PROJECT_FILE"
    exit 1
fi

cd "$PROJECT_DIR"
open "$PROJECT_FILE"

echo "✅ Proyecto abierto en Xcode"
echo ""
echo "💡 Próximos pasos:"
echo "1. Selecciona tu equipo de desarrollo en las configuraciones del proyecto"
echo "2. Presiona ⌘+R para compilar y ejecutar"
echo "3. La aplicación aparecerá en la barra de menú con el ícono 🎥"
