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

# Función para actualizar Info.plist
update_info_plist() {
    local version=$1
    local plist_path="LiveWalls/Info.plist"
    
    if [ ! -f "$plist_path" ]; then
        echo -e "${YELLOW}⚠️  Info.plist no encontrado, saltando actualización...${NC}"
        return
    fi
    
    echo -e "${BLUE}📝 Actualizando Info.plist...${NC}"
    
    # Actualizar CFBundleShortVersionString
    plutil -replace CFBundleShortVersionString -string "$version" "$plist_path"
    
    # Actualizar CFBundleVersion (usar timestamp para build number)
    local build_number=$(date +%Y%m%d%H%M)
    plutil -replace CFBundleVersion -string "$build_number" "$plist_path"
    
    echo -e "${GREEN}✅ Version actualizada a $version (build: $build_number)${NC}"
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

# Verificar que el working tree esté limpio
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${RED}❌ Error: Hay cambios sin commitear${NC}"
    echo "   Commit todos los cambios antes de crear un release"
    git status --short
    exit 1
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

TAG="v$VERSION"

# Verificar que el tag no exista
if git tag -l | grep -q "^$TAG$"; then
    echo -e "${RED}❌ Error: El tag $TAG ya existe${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 Creando release $TAG${NC}"

# Actualizar Info.plist
update_info_plist "$VERSION"

# Commitear cambios en Info.plist si hay
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${BLUE}📦 Commiteando actualización de versión...${NC}"
    git add LiveWalls/Info.plist
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
echo "  3. 📬 Los usuarios podrán descargar desde:"
echo "     https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/releases/tag/$TAG"
echo ""
echo -e "${YELLOW}⏳ El proceso puede tomar 5-10 minutos...${NC}"
echo -e "${BLUE}🔗 Revisa el progreso en: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/actions${NC}"
