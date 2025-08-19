#!/bin/bash

# Script para crear release local y tag
# Uso: ./scripts/create-release.sh [version]

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar ayuda
show_help() {
    echo -e "${BLUE}🚀 Script de Release para LiveWalls${NC}"
    echo ""
    echo "Uso: $0 [version]"
    echo ""
    echo "Ejemplos:"
    echo "  $0 1.0.0          # Release v1.0.0"
    echo "  $0 1.1.0-beta.1   # Pre-release v1.1.0-beta.1"
    echo "  $0                # Incremental patch version"
    echo ""
    echo "El script:"
    echo "  1. 🔍 Verifica que el working tree esté limpio"
    echo "  2. 📝 Actualiza el version en Info.plist"
    echo "  3. 🏷️ Crea el tag de Git"
    echo "  4. 📤 Hace push del tag (que trigerea el GitHub Action)"
    echo "  5. 🍺 GitHub Actions actualizará automáticamente Homebrew"
    echo ""
}

# Función para obtener la última versión
get_latest_version() {
    git tag -l "v*.*.*" | sort -V | tail -n1 | sed 's/^v//'
}

# Función para incrementar versión patch
increment_patch_version() {
    local version=$1
    local major=$(echo $version | cut -d. -f1)
    local minor=$(echo $version | cut -d. -f2)
    local patch=$(echo $version | cut -d. -f3)
    local new_patch=$((patch + 1))
    echo "$major.$minor.$new_patch"
}

# Función para validar formato de versión
validate_version() {
    local version=$1
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?$ ]]; then
        echo -e "${RED}❌ Error: Formato de versión inválido${NC}"
        echo "   Debe ser: X.Y.Z o X.Y.Z-prerelease"
        echo "   Ejemplos: 1.0.0, 1.2.3, 2.0.0-beta.1"
        exit 1
    fi
}

# Variable global para el build number
BUILD_NUMBER=""

# Función para actualizar Info.plist
update_info_plist() {
    local version=$1
    local plist_path="LiveWalls/Info.plist"
    
    if [ ! -f "$plist_path" ]; then
        echo -e "${YELLOW}⚠️  Info.plist no encontrado, saltando actualización...${NC}"
        return
    fi
    
    echo -e "${BLUE}📝 Actualizando Info.plist...${NC}"
    
    # Actualizar CFBundleShortVersionString (versión de marketing)
    plutil -replace CFBundleShortVersionString -string "$version" "$plist_path"
    
    # Actualizar CFBundleVersion (usar timestamp para build number)
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$plist_path"
    
    echo -e "${GREEN}✅ Info.plist actualizado a $version (build: $BUILD_NUMBER)${NC}"
}

# Función para actualizar el archivo de proyecto de Xcode
update_xcode_project() {
    local version=$1
    local build_number=$2
    local project_file="LiveWalls.xcodeproj/project.pbxproj"

    if [ ! -f "$project_file" ]; then
        echo -e "${YELLOW}⚠️  project.pbxproj no encontrado, saltando actualización...${NC}"
        return
    fi

    echo -e "${BLUE}📝 Actualizando proyecto de Xcode...${NC}"

    # Usar sed para actualizar las versiones en todas las configuraciones (Debug/Release)
    # La opción -i '' es para la compatibilidad con sed de macOS (BSD)
    sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/g" "$project_file"
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $build_number;/g" "$project_file"

    echo -e "${GREEN}✅ Proyecto de Xcode actualizado a $version (build: $build_number)${NC}"
}


# Verificar argumentos
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Verificar que estamos en un repositorio Git
if [ ! -d ".git" ]; then
    echo -e "${RED}❌ Error: No es un repositorio Git${NC}"
    exit 1
fi

# Verificar que el working tree esté limpio (excepto cambios de versión previos)
STAGED_CHANGES=$(git diff --cached --name-only)
UNSTAGED_CHANGES=$(git diff --name-only)
VERSION_FILES="LiveWalls/Info.plist LiveWalls.xcodeproj/project.pbxproj"

# Verificar cambios no relacionados con versioning
NON_VERSION_CHANGES=$(git status --porcelain | grep -v -E "^\s*[MA]\s+(LiveWalls/Info\.plist|LiveWalls\.xcodeproj/project\.pbxproj)$" || true)

if [ -n "$NON_VERSION_CHANGES" ]; then
    echo -e "${RED}❌ Error: Hay cambios sin commitear no relacionados con versioning${NC}"
    echo "   Commit todos los cambios antes de crear un release, excepto Info.plist y project.pbxproj"
    echo ""
    echo "Cambios detectados:"
    echo "$NON_VERSION_CHANGES"
    exit 1
fi

# Mostrar cambios de versión previos si existen
if [ -n "$STAGED_CHANGES" ] || [ -n "$UNSTAGED_CHANGES" ]; then
    echo -e "${YELLOW}⚠️  Se detectaron cambios previos de versioning que serán sobrescritos:${NC}"
    if [ -n "$STAGED_CHANGES" ]; then
        echo "  📁 Staged: $STAGED_CHANGES"
    fi
    if [ -n "$UNSTAGED_CHANGES" ]; then
        echo "  📝 Modified: $UNSTAGED_CHANGES"
    fi
    echo ""
fi

# Determinar versión
if [ -n "$1" ]; then
    VERSION="$1"
    validate_version "$VERSION"
else
    # Auto-incrementar patch version
    LATEST=$(get_latest_version)
    if [ -z "$LATEST" ]; then
        VERSION="1.0.0"
        echo -e "${BLUE}🎉 Primera release detectada${NC}"
    else
        VERSION=$(increment_patch_version "$LATEST")
        echo -e "${BLUE}⬆️  Auto-incrementando de v$LATEST a v$VERSION${NC}"
    fi
fi

# Mostrar información y solicitar confirmación
echo ""
echo -e "${BLUE}📋 Información del release:${NC}"
echo "  🏷️  Tag: v$VERSION"
echo "  📁 Última versión: $(git tag -l 'v*.*.*' | sort -V | tail -n1 || echo 'ninguna')"
echo "  📝 Se actualizarán: Info.plist y project.pbxproj"
echo "  🚀 Se creará y hará push del tag v$VERSION"
echo ""
echo -e "${YELLOW}⚠️  ¿Continuar con la creación del release v$VERSION? (y/N)${NC}"
read -r response
if [[ ! "$response" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo -e "${BLUE}🚫 Release cancelado${NC}"
    exit 0
fi

TAG="v$VERSION"

# Verificar que el tag no exista
if git tag -l | grep -q "^$TAG$"; then
    echo -e "${RED}❌ Error: El tag $TAG ya existe${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 Creando release $TAG${NC}"

# Generar BUILD_NUMBER antes de usarlo
BUILD_NUMBER=$(date +%Y%m%d%H%M)
echo -e "${BLUE}🔢 Build number generado: $BUILD_NUMBER${NC}"

# Actualizar Info.plist y el proyecto de Xcode
update_info_plist "$VERSION"
update_xcode_project "$VERSION" "$BUILD_NUMBER"

# Commitear cambios de versión si los hay
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${BLUE}📦 Commiteando actualización de versión...${NC}"
    # Usar -f para forzar la adición de archivos que pueden estar en .gitignore
    git add -f LiveWalls/Info.plist LiveWalls.xcodeproj/project.pbxproj
    git commit -m "🔖 chore: bump version to $VERSION"
fi

# Crear tag
echo -e "${BLUE}🏷️  Creando tag $TAG...${NC}"
git tag -a "$TAG" -m "🚀 Release $TAG

$(if [ -f CHANGELOG.md ]; then
    awk "/^## \[$VERSION\]/,/^## \[/{if(/^## \[/ && !/^## \[$VERSION\]/)exit;print}" CHANGELOG.md | head -n -1
else
    echo "✨ Nueva versión de LiveWalls"
fi)"

# Hacer push del tag
echo -e "${BLUE}📤 Haciendo push del tag...${NC}"
git push origin "$TAG"


echo ""
echo -e "${GREEN}🎉 ¡Release $TAG creado exitosamente!${NC}"
echo ""
echo -e "${BLUE}📋 Próximos pasos:${NC}"
echo "  1. 🔄 GitHub Actions compilará automáticamente la app"
echo "  2. 💿 Se creará el DMG y se subirá a GitHub Releases"
echo "  3. 🍺 Se actualizará automáticamente la fórmula de Homebrew"
echo "  4. 📬 Los usuarios podrán descargar desde:"
echo "     https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/releases/tag/$TAG"
echo ""
echo -e "${YELLOW}⏳ El proceso puede tomar 5-10 minutos...${NC}"
echo -e "${BLUE}🔗 Revisa el progreso en: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/actions${NC}"

