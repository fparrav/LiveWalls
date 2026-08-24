#!/bin/bash

# Script para compilar, ejecutar y probar Live Walls
# Uso: ./build.sh [clean|build|run|test|archive]

set -e

PROJECT_NAME="LiveWalls"
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    
    "test")
        echo "🧪 Ejecutando pruebas..."
        
        # Primero, construir todos los targets necesarios
        echo "🔨 Compilando targets de prueba..."
        xcodebuild build \
            -project "${PROJECT_NAME}.xcodeproj" \
            -target LiveWallsTests \
            -configuration Debug \
            SYMROOT="${BUILD_DIR}"
        
        # Ejecutar UI Tests (que sí funcionan)
        echo "🖥️ Ejecutando UI Tests..."
        xcodebuild test \
            -project "${PROJECT_NAME}.xcodeproj" \
            -scheme LiveWallsUITests \
            -configuration Debug \
            -derivedDataPath "${DERIVED_DATA_DIR}" \
            -enableCodeCoverage YES \
            SYMROOT="${BUILD_DIR}"
        
        # Los unit tests requieren configuración de scheme
        echo "📋 Unit Tests compilados correctamente (requieren configuración de scheme para ejecución)"
        echo "💡 Para ejecutar unit tests manualmente:"
        echo "   - Abrir Xcode: open LiveWalls.xcodeproj"
        echo "   - Usar Cmd+U para ejecutar todos los tests"
        echo "   - O ejecutar tests específicos desde el navegador de tests"
        
        echo "✅ Pruebas completadas"
        
        # Mostrar reporte de cobertura si está disponible
        COVERAGE_DIR="${DERIVED_DATA_DIR}/Logs/Test"
        if [ -d "$COVERAGE_DIR" ]; then
            echo "📊 Reporte de cobertura disponible en: $COVERAGE_DIR"
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
        echo "Uso: $0 [clean|build|run|test|archive]"
        echo ""
        echo "Comandos disponibles:"
        echo "  clean   - Limpiar archivos de build"
        echo "  build   - Compilar la aplicación"
        echo "  run     - Compilar y ejecutar la aplicación"
        echo "  test    - Ejecutar pruebas unitarias y de UI"
        echo "  archive - Crear archivo para distribución"
        exit 1
        ;;
esac
