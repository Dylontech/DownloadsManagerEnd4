#!/usr/bin/env bash
# =============================================================================
# Media Download Center v1.0 — Script de instalación
# =============================================================================
# Centro de descargas multimedia para Hyprland + QuickShell (Illogical-Impulse)
#
# Plataformas: YouTube · Twitch · TikTok · Instagram · Twitter/X · Vimeo
#              SoundCloud · Bandcamp
#
# Uso:
#   chmod +x install.sh && ./install.sh
#
# =============================================================================

set -euo pipefail

# ─── Colores ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Configuración ──────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QML_DEST="${HOME}/.config/quickshell/ii/modules/ii/mediaDownloader"
NODE_MIN_VERSION="18.0.0"

# ─── Funciones auxiliares ───────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 no está instalado. Instálalo con: $2"
        return 1
    fi
    log_ok "$1 → $($1 --version 2>&1 | head -1)"
    return 0
}

version_ge() {
    local v1="${1#v}" v2="${2#v}"
    [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -1)" = "$v2" ]
}

# ═════════════════════════════════════════════════════════════════════════════
# BANNER
# ═════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║         Media Download Center — v1.0             ║"
echo "  ║          Instalación / Actualización             ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 1 — Dependencias del sistema
# ═════════════════════════════════════════════════════════════════════════════
log_step "1/4 — Dependencias del sistema"

HAS_ERRORS=false
check_cmd "node"   "sudo pacman -S nodejs  |  brew install node  |  winget install OpenJS.NodeJS"  || HAS_ERRORS=true
check_cmd "npm"    "sudo pacman -S npm     |  brew install npm   |  winget install OpenJS.NodeJS"  || HAS_ERRORS=true
check_cmd "yt-dlp" "sudo pacman -S yt-dlp  |  pip install yt-dlp |  brew install yt-dlp"          || HAS_ERRORS=true

if command -v node &>/dev/null; then
    NODE_VER=$(node --version)
    if ! version_ge "$NODE_VER" "$NODE_MIN_VERSION"; then
        log_warn "Node.js $NODE_VER detectado (mínimo: v${NODE_MIN_VERSION}+)"
        log_warn "Actualiza Node.js para evitar problemas."
    fi
fi

if [ "$HAS_ERRORS" = true ]; then
    echo ""
    log_error "Instala las dependencias faltantes y vuelve a ejecutar el script."
    exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# PASO 2 — Dependencias de Node.js
# ═════════════════════════════════════════════════════════════════════════════
log_step "2/4 — Dependencias de Node.js (npm install)"

cd "$REPO_DIR"

if [ -f package-lock.json ]; then
    npm ci --silent 2>&1 | tail -1 || true
else
    npm install --silent 2>&1 | tail -1 || true
fi

log_ok "Paquetes npm instalados correctamente"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 3 — Compilar TypeScript
# ═════════════════════════════════════════════════════════════════════════════
log_step "3/4 — Compilando TypeScript (npm run build)"

npm run build 2>&1

if [ ! -f dist/index.js ]; then
    log_error "Compilación fallida — no se generó dist/index.js"
    log_error "Revisa los errores de TypeScript e intenta de nuevo."
    exit 1
fi

log_ok "TypeScript compilado → dist/"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 4 — Instalar módulos QML en QuickShell
# ═════════════════════════════════════════════════════════════════════════════
log_step "4/4 — Instalando módulos QML en QuickShell"

QML_REQUIRED=(
    "MediaDownloaderIPC.qml"
    "MediaDownloaderPanel.qml"
    "MediaDownloaderWidget.qml"
    "MediaDownloaderFloating.qml"
    "FormatSelector.qml"
    "MediaPreview.qml"
    "UrlInput.qml"
    "DownloadProgressCard.qml"
)

QML_SRC="${REPO_DIR}/qml"

if [ -d "$QML_SRC" ]; then
    log_info "Copiando desde ${QML_SRC} → ${QML_DEST}"
    mkdir -p "$QML_DEST"
    COPIED=0
    for f in "${QML_REQUIRED[@]}"; do
        if [ -f "${QML_SRC}/${f}" ]; then
            cp "${QML_SRC}/${f}" "${QML_DEST}/${f}"
            log_ok "  ✓ ${f}"
            COPIED=$((COPIED + 1))
        else
            log_warn "  ✗ ${f} — no encontrado en qml/"
        fi
    done
    log_ok "${COPIED}/${#QML_REQUIRED[@]} módulos QML instalados en ${QML_DEST}"
elif [ -d "$QML_DEST" ]; then
    log_info "Módulos QML ya existen en ${QML_DEST} (verificando...)"
    MISSING=0
    for f in "${QML_REQUIRED[@]}"; do
        if [ -f "${QML_DEST}/${f}" ]; then
            log_ok "  ✓ ${f}"
        else
            log_warn "  ✗ ${f} — no encontrado"
            MISSING=$((MISSING + 1))
        fi
    done
    if [ "$MISSING" -gt 0 ]; then
        echo ""
        log_warn "Faltan ${MISSING} archivo(s). Copia los .qml desde el repositorio:"
        echo "   cp ${REPO_DIR}/qml/*.qml ${QML_DEST}/"
    fi
else
    log_warn "No se encontraron módulos QML."
    log_warn "Crea la carpeta qml/ en el repositorio con los archivos .qml"
    echo "   mkdir -p ${QML_DEST}"
    echo "   # o ejecuta este script desde el directorio del repositorio"
fi

# ═════════════════════════════════════════════════════════════════════════════
# FIN
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Instalación / Actualización completada      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠  IMPORTANTE:${NC}"
echo "   • Los cambios en archivos .qml requieren reiniciar QuickShell:"
echo -e "     ${BLUE}pkill quickshell && quickshell &${NC}"
echo ""
echo "   • Si hay errores de QML, limpia la caché:"
echo -e "     ${BLUE}rm -rf ~/.cache/quickshell/${NC}"
echo ""
echo "   • yt-dlp se actualiza por separado:"
echo -e "     ${BLUE}sudo pacman -Syu yt-dlp${NC}"
echo ""
echo -e "${CYAN}📋  PRÓXIMOS PASOS:${NC}"
echo "   1. Agrega el widget a tu configuración de QuickShell"
echo "   2. Reinicia QuickShell"
echo "   3. Abre el panel, pega un enlace y descarga 🎬"
echo ""
echo -e "${GREEN}¡Gracias por usar Media Download Center!${NC}"
