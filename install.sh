#!/usr/bin/env bash
# =============================================================================
# Media Download Center — Install Script
# =============================================================================
# Centro de descargas multimedia para Hyprland/QuickShell
# Soporta: YouTube, Twitch, TikTok, Instagram, Twitter/X, Vimeo, SoundCloud, Bandcamp
# =============================================================================

set -euo pipefail

# ─── Colores ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─── Configuración ──────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUICKSHELL_MODULES_DIR="${HOME}/.config/quickshell/ii/modules/ii/mediaDownloader"
NODE_MIN_VERSION="18.0.0"

# ─── Funciones ──────────────────────────────────────────────────────────────

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

check_dependency() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 no está instalado. Instálalo con: $2"
        return 1
    fi
    log_ok "$1 encontrado: $($1 --version 2>&1 | head -1)"
    return 0
}

version_ge() {
    # Compara versiones semver: version_ge "v18.2.0" "18.0.0" → true
    local v1="${1#v}" v2="${2#v}"
    [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -1)" = "$v2" ]
}

# ─── Banner ─────────────────────────────────────────────────────────────────

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║         Media Download Center — Install          ║"
echo "  ║     Centro de Descargas Multimedia v1.0.0        ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 1: Verificar dependencias del sistema
# ═════════════════════════════════════════════════════════════════════════════

log_step "Paso 1/5 — Verificando dependencias del sistema"

HAS_ERRORS=false

check_dependency "node"  "sudo pacman -S nodejs   # o: winget install OpenJS.NodeJS / brew install node"        || HAS_ERRORS=true
check_dependency "npm"   "sudo pacman -S npm      # o: winget install OpenJS.NodeJS / brew install npm"         || HAS_ERRORS=true
check_dependency "yt-dlp" "sudo pacman -S yt-dlp  # o: pip install yt-dlp / brew install yt-dlp"               || HAS_ERRORS=true

# Verificar versión de Node
if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version)
    if ! version_ge "$NODE_VERSION" "$NODE_MIN_VERSION"; then
        log_warn "Node.js $NODE_VERSION detectado. Se requiere v${NODE_MIN_VERSION}+"
        log_warn "Actualiza Node.js para evitar problemas de compatibilidad."
    fi
fi

if [ "$HAS_ERRORS" = true ]; then
    log_error "Corrige las dependencias faltantes y vuelve a ejecutar este script."
    exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# PASO 2: Verificar QuickShell
# ═════════════════════════════════════════════════════════════════════════════

log_step "Paso 2/5 — Verificando QuickShell"

if ! command -v quickshell &>/dev/null; then
    log_warn "quickshell no está en PATH."
    log_warn "Este proyecto está diseñado para ejecutarse dentro de QuickShell (Illogical-Impulse)."
    log_warn "El backend Node.js puede ejecutarse de forma independiente, pero la interfaz QML"
    log_warn "requiere QuickShell (https://github.com/Quickshell/Quickshell)."
    echo ""
    read -rp "¿Continuar de todas formas? [s/N] " CONTINUE
    if [ "${CONTINUE:-n}" != "s" ] && [ "${CONTINUE:-n}" != "S" ]; then
        log_info "Instalación cancelada."
        exit 0
    fi
else
    log_ok "quickshell encontrado"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PASO 3: Instalar dependencias de Node.js
# ═════════════════════════════════════════════════════════════════════════════

log_step "Paso 3/5 — Instalando dependencias de Node.js"

cd "$REPO_DIR"

if [ ! -f package.json ]; then
    log_error "package.json no encontrado en $REPO_DIR"
    exit 1
fi

if [ -d node_modules ]; then
    log_info "node_modules ya existe. Actualizando dependencias..."
    npm install --silent 2>&1 | tail -1 || true
else
    log_info "Instalando dependencias..."
    npm install
fi

log_ok "Dependencias instaladas correctamente"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 4: Compilar TypeScript
# ═════════════════════════════════════════════════════════════════════════════

log_step "Paso 4/5 — Compilando TypeScript"

npm run build

if [ ! -f dist/index.js ]; then
    log_error "La compilación falló — dist/index.js no encontrado"
    exit 1
fi

log_ok "Código compilado correctamente"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 5: Copiar módulos QML a QuickShell
# ═════════════════════════════════════════════════════════════════════════════

log_step "Paso 5/5 — Instalando módulos QML para QuickShell"

if [ -d "$QUICKSHELL_MODULES_DIR" ]; then
    log_info "Respaldo de módulos existentes..."
    BACKUP_DIR="${QUICKSHELL_MODULES_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    cp -r "$QUICKSHELL_MODULES_DIR" "$BACKUP_DIR"
    log_info "Respaldo creado en: $BACKUP_DIR"
fi

mkdir -p "$QUICKSHELL_MODULES_DIR"

# Copiar archivos QML
# Los QML están en el directorio de configuración de QuickShell
QML_SRC_DIR="${HOME}/.config/quickshell/ii/modules/ii/mediaDownloader"

QML_FILES=(
    "DownloadProgressCard.qml"
    "FormatSelector.qml"
    "MediaDownloaderFloating.qml"
    "MediaDownloaderIPC.qml"
    "MediaDownloaderPanel.qml"
    "MediaDownloaderWidget.qml"
    "MediaPreview.qml"
    "UrlInput.qml"
)

if [ -d "$QML_SRC_DIR" ]; then
    for file in "${QML_FILES[@]}"; do
        SRC="${QML_SRC_DIR}/${file}"
        if [ -f "$SRC" ]; then
            cp "$SRC" "${QUICKSHELL_MODULES_DIR}/${file}"
            log_ok "  ✓ ${file}"
        else
            log_warn "No se encontró ${file}, se saltará"
        fi
    done
    log_ok "Módulos QML instalados en ${QUICKSHELL_MODULES_DIR}"
else
    log_warn "No se encontró el directorio QML de origen: ${QML_SRC_DIR}"
    log_warn "Los módulos QML deben estar ubicados en ~/.config/quickshell/ii/modules/ii/mediaDownloader/"
    log_warn "Asegúrate de que QuickShell esté configurado antes de ejecutar este script."
fi

# ═════════════════════════════════════════════════════════════════════════════
# FINALIZAR
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Instalación completada exitosamente       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠  ADVERTENCIAS IMPORTANTES:${NC}"
echo "   • Asegúrate de tener yt-dlp actualizado: sudo pacman -Syu yt-dlp"
echo "   • Los módulos QML requieren QuickShell (Illogical-Impulse fork)"
echo "   • Si usas Hyprland, verifica la configuración de layershell"
echo ""
echo -e "${CYAN}📋  PRÓXIMOS PASOS:${NC}"
echo "   1. Agrega el widget a tu configuración de QuickShell:"
echo "      - Modo pestaña (BottomWidgetGroup): agrega MediaDownloaderWidget"
echo "      - Modo panel (sidebar): agrega MediaDownloaderPanel"
echo "      - Modo flotante: usa el GlobalShortcut 'mediaDownloaderFloatingToggle'"
echo ""
echo "   2. Reinicia QuickShell para que los cambios surtan efecto:"
echo -e "      ${BLUE}pkill quickshell && quickshell &${NC}"
echo ""
echo "   3. Si hay errores, revisa la pestaña 'Logs' en el panel o ejecuta:"
echo -e "      ${BLUE}cd ${REPO_DIR} && npm run build${NC}"
echo ""
echo -e "${GREEN}¡Disfruta del Media Download Center! 🎬${NC}"
