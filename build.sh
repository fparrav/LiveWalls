#!/bin/bash

# Script para compilar y ejecutar Live Walls
# Uso: ./build.sh [clean|build|run|archive]

set -e

PROJECT_NAME="LiveWalls"
WORKSPACE_DIR="/Users/felipe/source-code/swift/LiveWalls"
BUILD_DIR="${WORKSPACE_DIR}/build"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"

cd "${WORKSPACE_DIR}"

case "${1:-build}" in
    "clean")
        echo "🧹 Limpiando archivos de build..."
        rm -rf "${BUILD_DIR}"
        rm -rf "${DERIVED_DATA_DIR}"
        xcodebuild clean -project "${PROJECT_NAME}.xcodeproj" -scheme "${PROJECT_NAME}"
        echo "✅ Limpieza completada"
        ;;
    
    "build")
        echo "🔨 Compilando ${PROJECT_NAME}..."
        xcodebuild build \
            -project "${PROJECT_NAME}.xcodeproj" \
            -scheme "${PROJECT_NAME}" \
            -configuration Debug \
            -derivedDataPath "${DERIVED_DATA_DIR}" \
            SYMROOT="${BUILD_DIR}"
        echo "✅ Compilación exitosa"
        ;;
    
    "run")
        echo "🔨 Compilando y ejecutando ${PROJECT_NAME}..."
        xcodebuild build \
            -project "${PROJECT_NAME}.xcodeproj" \
            -scheme "${PROJECT_NAME}" \
            -configuration Debug \
            -derivedDataPath "${DERIVED_DATA_DIR}" \
            SYMROOT="${BUILD_DIR}"
        
        # Buscar el archivo .app compilado
        APP_PATH=$(find "${BUILD_DIR}" -name "${PROJECT_NAME}.app" -type d | head -1)
        
        if [ -n "$APP_PATH" ]; then
            echo "🚀 Ejecutando aplicación (logs en esta terminal)..."
            # Ejecutar el binario directamente para ver los logs
            "${APP_PATH}/Contents/MacOS/${PROJECT_NAME}"
        else
            echo "❌ No se encontró la aplicación compilada"
            exit 1
        fi
        ;;
    
    "archive")
        echo "📦 Creando archivo de distribución..."
        xcodebuild archive \
            -project "${PROJECT_NAME}.xcodeproj" \
            -scheme "${PROJECT_NAME}" \
            -configuration Release \
            -derivedDataPath "${DERIVED_DATA_DIR}" \
            -archivePath "${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
        echo "✅ Archivo creado en ${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
        ;;
    
    *)
        echo "Uso: $0 [clean|build|run|archive]"
        echo ""
        echo "Comandos disponibles:"
        echo "  clean   - Limpiar archivos de build"
        echo "  build   - Compilar la aplicación"
        echo "  run     - Compilar y ejecutar la aplicación"
        echo "  archive - Crear archivo para distribución"
        exit 1
        ;;
esac
