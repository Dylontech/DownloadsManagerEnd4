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
#   chmod +x install.sh && ./install.sh                # instalación completa
#   ./install.sh --no-integrate                        # sin tocar la config ii
#   ./install.sh --uninstall                            # deshacer integración
#
# Pipeline:
#   1/7  Dependencias del sistema (node, npm, yt-dlp)
#   2/7  Dependencias de Node.js (npm ci / npm install)
#   3/7  Compilación TypeScript (dist/)
#   4/7  Copia de módulos QML
#   5/7  Integración con la config QuickShell "ii" (GlobalStates,
#        IllogicalImpulseFamily, IpcHandler en shell.qml, pestaña lateral)
#   6/7  Demonio systemd --user + atajo de Hyprland
#   7/7  Smoke test del backend (ping JSON-RPC)
#
# Arquitectura desde la v1.1: el backend NO es un proceso hijo de QuickShell,
# sino un demonio escuchando en un socket Unix. Por eso cerrar la barra lateral
# (o el panel flotante) ya no interrumpe las descargas en curso.
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
QS_CONFIG_DIR="${HOME}/.config/quickshell/ii"
NODE_MIN_VERSION="18.0.0"
BACKUP_SUFFIX=".mdc-backup"
INTEGRATE=true

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

# Backup único de un archivo de configuración (no sobreescribe backups previos)
backup_once() {
    local file="$1"
    if [ -f "$file" ] && [ ! -f "${file}${BACKUP_SUFFIX}" ]; then
        cp "$file" "${file}${BACKUP_SUFFIX}"
        log_info "Backup: ${file} → ${file}${BACKUP_SUFFIX}"
    fi
}

# Inserta un bloque de texto antes de la última línea "}" (cierre del root QML)
insert_before_last_brace() {
    local file="$1" block_file="$2"
    awk -v block="$(cat "$block_file")" '
        { lines[NR] = $0 }
        END {
            last = 0
            for (i = NR; i >= 1; i--) { if (lines[i] ~ /^}/) { last = i; break } }
            for (i = 1; i <= NR; i++) {
                if (i == last) print block
                print lines[i]
            }
        }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# ─── Desinstalación ─────────────────────────────────────────────────────────
do_uninstall() {
    log_step "Desinstalando Media Download Center"

    rm -rf "$QML_DEST"
    log_ok "Módulos QML eliminados (${QML_DEST})"

    local f
    for f in GlobalStates.qml panelFamilies/IllogicalImpulseFamily.qml shell.qml modules/ii/sidebarRight/BottomWidgetGroup.qml; do
        local full="${QS_CONFIG_DIR}/${f}"
        if [ -f "${full}${BACKUP_SUFFIX}" ]; then
            cp "${full}${BACKUP_SUFFIX}" "$full"
            log_ok "Restaurado: ${full} (desde backup)"
        elif [ -f "$full" ]; then
            sed -i '/[Mm]edia[Dd]ownloader/d' "$full"
            log_warn "Sin backup — líneas de mediaDownloader eliminadas de ${full}"
        fi
    done

    # ── Demonio systemd ──
    local unit="${HOME}/.config/systemd/user/media-download-center.service"
    if command -v systemctl &>/dev/null; then
        systemctl --user disable --now media-download-center.service &>/dev/null || true
        log_ok "Servicio systemd detenido y deshabilitado"
    fi
    if [ -f "$unit" ]; then
        rm -f "$unit"
        command -v systemctl &>/dev/null && systemctl --user daemon-reload &>/dev/null || true
        log_ok "Unidad systemd eliminada (${unit})"
    fi
    rm -f "${XDG_RUNTIME_DIR:-/tmp}/media-download-center.sock"
    log_ok "Socket del demonio eliminado"

    # ── Atajo de Hyprland (bloque delimitado en custom/keybinds.lua) ──
    local keybinds="${HOME}/.config/hypr/custom/keybinds.lua"
    if [ -f "$keybinds" ] && grep -q '>>> Media Download Center >>>' "$keybinds"; then
        sed -i '/>>> Media Download Center >>>/,/<<< Media Download Center <<</d' "$keybinds"
        log_ok "Atajo de Hyprland eliminado de ${keybinds}"
    fi

    echo ""
    log_warn "Reinicia QuickShell para aplicar los cambios:"
    echo -e "     ${BLUE}pkill -f 'qs -c ii' && qs -c ii &${NC}"
    exit 0
}

# ─── Parseo de argumentos ───────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --no-integrate) INTEGRATE=false ;;
        --uninstall)    do_uninstall ;;
        *) log_warn "Argumento desconocido: $arg (ignorado)" ;;
    esac
done

# ═════════════════════════════════════════════════════════════════════════════
# BANNER
# ═════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║         Media Download Center — v1.1             ║"
echo "  ║          Instalación / Actualización             ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 1 — Dependencias del sistema
# ═════════════════════════════════════════════════════════════════════════════
log_step "1/7 — Dependencias del sistema"

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
log_step "2/7 — Dependencias de Node.js (npm install)"

cd "$REPO_DIR"

if [ -f package-lock.json ]; then
    npm ci --silent --no-audit --no-fund 2>&1 | tail -1
else
    npm install --silent --no-audit --no-fund 2>&1 | tail -1
fi

# npm >= 11 omite los scripts de build nativos en modo no interactivo:
# reconstruir better-sqlite3 explícitamente, con fallback directo.
SQLITE3_BIN="$(find node_modules/better-sqlite3 -name 'better_sqlite3.node' 2>/dev/null | head -1 || true)"
if [ -z "$SQLITE3_BIN" ]; then
    npm rebuild better-sqlite3 --silent --no-audit --no-fund 2>&1 | tail -1
fi
SQLITE3_BIN="$(find node_modules/better-sqlite3 -name 'better_sqlite3.node' 2>/dev/null | head -1 || true)"
if [ -z "$SQLITE3_BIN" ]; then
    log_info "npm rebuild no compiló el nativo — ejecutando el script del paquete..."
    (cd node_modules/better-sqlite3 && npm run install --silent --no-audit --no-fund) 2>&1 | tail -1
fi
SQLITE3_BIN="$(find node_modules/better-sqlite3 -name 'better_sqlite3.node' 2>/dev/null | head -1 || true)"
if [ -z "$SQLITE3_BIN" ]; then
    log_error "El binario nativo de better-sqlite3 no se compiló."
    log_error "Intenta manualmente: cd node_modules/better-sqlite3 && npm run install"
    exit 1
fi

log_ok "Paquetes npm instalados correctamente"
log_ok "better-sqlite3 nativo compilado ✓"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 3 — Compilar TypeScript
# ═════════════════════════════════════════════════════════════════════════════
log_step "3/7 — Compilando TypeScript (npm run build)"

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
log_step "4/7 — Instalando módulos QML en QuickShell"

QML_REQUIRED=(
    "MediaDownloaderIPC.qml"
    "MediaDownloaderPanel.qml"
    "MediaDownloaderWidget.qml"
    "MediaDownloaderFloating.qml"
    "MediaActiveList.qml"
    "MediaHistoryList.qml"
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
else
    log_error "No se encontró la carpeta qml/ en ${REPO_DIR}"
    exit 1
fi

# ── Verificación del puente QML ────────────────────────────────────────────
# Desde la v1.1 el QML ya NO lanza el backend: se conecta por socket al demonio
# de systemd. Si el fichero instalado todavía crea un `Process`, es una versión
# antigua y volveríamos a matar las descargas al cerrar la barra lateral.
IPC_FILE="${QML_DEST}/MediaDownloaderIPC.qml"

if [ ! -f "$IPC_FILE" ]; then
    log_error "No se encontró ${IPC_FILE}"
    exit 1
fi

if grep -q '__BACKEND_DIR__' "$IPC_FILE" || grep -q 'Process {' "$IPC_FILE"; then
    log_error "El MediaDownloaderIPC.qml instalado es de una versión antigua (lanza un proceso en vez de usar el socket)."
    exit 1
fi

if ! grep -q 'Socket {' "$IPC_FILE"; then
    log_error "El MediaDownloaderIPC.qml instalado no contiene un Socket — copia incompleta."
    exit 1
fi

log_ok "Puente QML verificado: usa Socket (ya no hay proceso hijo)"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 5 — Integración con la config QuickShell "ii"
# ═════════════════════════════════════════════════════════════════════════════
log_step "5/7 — Integración con QuickShell (${QS_CONFIG_DIR})"

if [ "$INTEGRATE" = false ]; then
    log_warn "Integración omitida (--no-integrate)"
elif [ ! -f "${QS_CONFIG_DIR}/shell.qml" ]; then
    log_warn "No se encontró ${QS_CONFIG_DIR}/shell.qml"
    log_warn "Integración omitida — copia los widgets manualmente a tu config."
else
    GLOBAL_STATES="${QS_CONFIG_DIR}/GlobalStates.qml"
    FAMILY="${QS_CONFIG_DIR}/panelFamilies/IllogicalImpulseFamily.qml"
    SHELL="${QS_CONFIG_DIR}/shell.qml"

    backup_once "$GLOBAL_STATES"
    backup_once "$FAMILY"
    backup_once "$SHELL"

    # 5a — Propiedad de estado en GlobalStates.qml
    if grep -q "mediaDownloaderFloatingOpen" "$GLOBAL_STATES"; then
        log_ok "GlobalStates.qml ya contiene mediaDownloaderFloatingOpen"
    else
        sed -i '/property bool mediaControlsOpen: false/a\    property bool mediaDownloaderFloatingOpen: false' "$GLOBAL_STATES"
        log_ok "GlobalStates.qml → property mediaDownloaderFloatingOpen añadida"
    fi

    # 5b — Import + PanelLoader en IllogicalImpulseFamily.qml
    if grep -q "qs.modules.ii.mediaDownloader" "$FAMILY"; then
        log_ok "IllogicalImpulseFamily.qml ya importa el módulo"
    else
        sed -i '/import qs.modules.ii.mediaControls/a\import qs.modules.ii.mediaDownloader' "$FAMILY"
        log_ok "IllogicalImpulseFamily.qml → import añadido"
    fi

    if grep -q "MediaDownloaderFloating" "$FAMILY"; then
        log_ok "IllogicalImpulseFamily.qml ya registra MediaDownloaderFloating"
    else
        sed -i '/PanelLoader { component: MediaControls {} }/a\    PanelLoader { component: MediaDownloaderFloating {} }' "$FAMILY"
        log_ok "IllogicalImpulseFamily.qml → PanelLoader añadido"
    fi

    # 5c — IpcHandler en shell.qml (qs -c ii ipc call mediaDownloader toggle)
    if grep -q 'target: "mediaDownloader"' "$SHELL"; then
        log_ok "shell.qml ya contiene el IpcHandler mediaDownloader"
    else
        IPC_BLOCK_FILE="$(mktemp)"
        cat > "$IPC_BLOCK_FILE" <<'EOF'
    // ── Media Download Center (añadido por install.sh) ──
    IpcHandler {
        target: "mediaDownloader"

        function toggle(): void {
            GlobalStates.mediaDownloaderFloatingOpen = !GlobalStates.mediaDownloaderFloatingOpen
        }

        function show(): void {
            GlobalStates.mediaDownloaderFloatingOpen = true
        }

        function hide(): void {
            GlobalStates.mediaDownloaderFloatingOpen = false
        }
    }
EOF
        insert_before_last_brace "$SHELL" "$IPC_BLOCK_FILE"
        rm -f "$IPC_BLOCK_FILE"
        log_ok "shell.qml → IpcHandler mediaDownloader añadido"
    fi

    # 5d — Pestaña "Descargas" en el BottomWidgetGroup del sidebar derecho
    BOTTOM_WIDGET="${QS_CONFIG_DIR}/modules/ii/sidebarRight/BottomWidgetGroup.qml"
    if [ -f "$BOTTOM_WIDGET" ]; then
        backup_once "$BOTTOM_WIDGET"
        if grep -q "mediaDownloader" "$BOTTOM_WIDGET"; then
            log_ok "BottomWidgetGroup.qml ya contiene la pestaña de descargas"
        else
            sed -i '/"widget": "pomodoro\/PomodoroWidget.qml"/{n;s|},|},\n        {\n            "type": "mediaDownloader",\n            "name": Translation.tr("Downloads"),\n            "icon": "download",\n            "widget": "../mediaDownloader/MediaDownloaderWidget.qml"\n        },|}' "$BOTTOM_WIDGET"
            if grep -q "mediaDownloader" "$BOTTOM_WIDGET"; then
                log_ok "BottomWidgetGroup.qml → pestaña Descargas añadida"
            else
                log_error "No se pudo añadir la pestaña al BottomWidgetGroup (patrón no encontrado)"
                exit 1
            fi
        fi
    else
        log_warn "No se encontró BottomWidgetGroup.qml — la pestaña del sidebar no se añadió"
    fi

    # 5e — Traducciones en español (claves por defecto + merge sin pisar al usuario)
    TRANSLATIONS_DIR="${HOME}/.config/illogical-impulse/translations"
    TRANSLATIONS_FILE="${TRANSLATIONS_DIR}/es_MX.json"
    TRANSLATIONS_DEFAULTS="$(mktemp)"
    cat > "$TRANSLATIONS_DEFAULTS" <<'EOF'
{
  "Media Download Center": "Centro de Descargas",
  "Downloads": "Descargas",
  "Download": "Descargar",
  "Active": "Activas",
  "Active Downloads": "Descargas activas",
  "History": "Historial",
  "Favorites": "Favoritos",
  "Config": "Configuración",
  "Logs": "Registros",
  "No active downloads": "No hay descargas activas",
  "Paste a link to download...": "Pega un enlace para descargar...",
  "Paste a link to start downloading": "Pega un enlace para empezar a descargar",
  "Search history...": "Buscar en historial...",
  "Backend not ready. Please wait...": "Backend no listo. Espera...",
  "Failed to analyze URL": "No se pudo analizar el enlace",
  "Failed to start download": "No se pudo iniciar la descarga",
  "Analyzing link...": "Analizando enlace...",
  "The link returned no information": "El enlace no devolvió información",
  "Download Path": "Ruta de descarga",
  "Max Concurrent": "Descargas simultáneas",
  "Auto-download thumbnails": "Descargar miniaturas",
  "Auto-download subtitles": "Descargar subtítulos",
  "Cookies (anti-bot)": "Cookies (anti-bot)",
  "Some services ask for a logged-in session. Import the cookies from your browser.": "Algunos servicios piden una sesión iniciada. Importa las cookies de tu navegador.",
  "Disabled": "Desactivado",
  "...or path to cookies.txt": "…o ruta a cookies.txt",
  "Tip: import cookies from your browser in the Config tab.": "Consejo: importa las cookies de tu navegador en la pestaña Configuración."
}
EOF

    if [ -f "$TRANSLATIONS_FILE" ]; then
        # Merge idempotente: añade solo las claves que falten
        if node -e '
            const fs = require("fs");
            const [targetFile, defaultsFile] = process.argv.slice(1);
            const target = JSON.parse(fs.readFileSync(targetFile, "utf8"));
            const defaults = JSON.parse(fs.readFileSync(defaultsFile, "utf8"));
            let added = 0;
            for (const [key, value] of Object.entries(defaults)) {
                if (!(key in target)) { target[key] = value; added++; }
            }
            if (added > 0) fs.writeFileSync(targetFile, JSON.stringify(target, null, 2) + "\n");
            console.log(added);
        ' "$TRANSLATIONS_FILE" "$TRANSLATIONS_DEFAULTS" >/dev/null 2>&1; then
            log_ok "Traducciones ES actualizadas (se respetaron las tuyas): ${TRANSLATIONS_FILE}"
        else
            log_warn "No se pudieron fusionar las traducciones en ${TRANSLATIONS_FILE}"
        fi
    else
        mkdir -p "$TRANSLATIONS_DIR"
        cp "$TRANSLATIONS_DEFAULTS" "$TRANSLATIONS_FILE"
        log_ok "Traducciones ES creadas → ${TRANSLATIONS_FILE}"
    fi
    rm -f "$TRANSLATIONS_DEFAULTS"

    log_ok "Integración completada. Accesos:"
    echo -e "     ${BLUE}Sidebar derecho → pestaña «Descargas»${NC}"
    echo -e "     ${BLUE}qs -c ii ipc call mediaDownloader toggle${NC} (ventana flotante)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PASO 6 — Demonio systemd --user + atajo de Hyprland
# ═════════════════════════════════════════════════════════════════════════
log_step "6/7 — Demonio systemd --user"

NODE_BIN="$(command -v node)"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
UNIT_NAME="media-download-center.service"
UNIT_FILE="${SYSTEMD_USER_DIR}/${UNIT_NAME}"
SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/media-download-center.sock"
SERVICE_TEMPLATE="${REPO_DIR}/packaging/media-download-center.service"

if ! command -v systemctl &>/dev/null; then
    log_warn "systemctl no disponible. Arranca el demonio a mano:"
    log_warn "  ${NODE_BIN} ${REPO_DIR}/dist/index.js --daemon &"
elif [ ! -f "$SERVICE_TEMPLATE" ]; then
    log_error "No se encontró ${SERVICE_TEMPLATE} — no se puede instalar el servicio"
    exit 1
else
    mkdir -p "$SYSTEMD_USER_DIR"
    backup_once "$UNIT_FILE"

    sed -e "s|__NODE_BIN__|${NODE_BIN}|g" \
        -e "s|__BACKEND_DIR__|${REPO_DIR}|g" \
        "$SERVICE_TEMPLATE" > "$UNIT_FILE"
    log_ok "Unidad instalada → ${UNIT_FILE}"

    systemctl --user daemon-reload
    if systemctl --user enable --now "$UNIT_NAME" 2>/dev/null; then
        log_ok "Servicio habilitado y arrancado (${UNIT_NAME})"
    else
        log_warn "No se pudo activar el servicio. ¿Existe una sesión systemd de usuario?"
        log_warn "Prueba a mano: systemctl --user enable --now ${UNIT_NAME}"
    fi

    if [ -S "$SOCKET_PATH" ]; then
        log_ok "Socket del demonio activo → ${SOCKET_PATH}"
    else
        log_warn "El socket ${SOCKET_PATH} todavía no existe."
        log_warn "Revisa los logs: journalctl --user -u ${UNIT_NAME} -n 30"
    fi
fi

# ── Atajo de Hyprland ───────────────────────────────────────────────────────
# Hyprland está configurado con Lua: las personalizaciones van en
# custom/keybinds.lua, NO en hyprland.conf (que no existe en esa instalación).
# SUPER+D ya está ocupado por "Window: Maximize", de ahí CTRL+SUPER+D.
KEYBINDS_FILE="${HOME}/.config/hypr/custom/keybinds.lua"

if [ -f "$KEYBINDS_FILE" ]; then
    if grep -q '>>> Media Download Center >>>' "$KEYBINDS_FILE"; then
        log_ok "Atajo de Hyprland ya presente en custom/keybinds.lua"
    else
        cat >> "$KEYBINDS_FILE" <<'EOF'

-- >>> Media Download Center >>>
-- Panel flotante del gestor de descargas (activas + historial).
-- No se usa SUPER+D: Hyprland ya lo tiene para "Window: Maximize".
hl.bind("CTRL + SUPER + D", hl.dsp.global("quickshell:mediaDownloaderFloatingToggle"),
    { description = "Shell: Toggle media downloader" })
-- <<< Media Download Center <<<
EOF
        log_ok "Atajo CTRL+SUPER+D añadido → ${KEYBINDS_FILE}"
        log_warn "Recarga Hyprland para que el atajo surta efecto: hyprctl reload"
    fi
else
    log_warn "No se encontró ${KEYBINDS_FILE}"
    log_warn "Añade a mano: hl.bind(\"CTRL + SUPER + D\", hl.dsp.global(\"quickshell:mediaDownloaderFloatingToggle\"))"
fi

# ═════════════════════════════════════════════════════════════════════════
# PASO 7 — Smoke test del backend (modo stdio, sin tocar el demonio)
# ═════════════════════════════════════════════════════════════════════════
log_step "7/7 — Smoke test del backend (ping JSON-RPC)"

SMOKE_OUTPUT="$(printf '{"jsonrpc":"2.0","id":1,"method":"ping"}\n' | node "${REPO_DIR}/dist/index.js" 2>&1 >/dev/null || true)"

if echo "$SMOKE_OUTPUT" | grep -q '"id":1' && echo "$SMOKE_OUTPUT" | grep -q '"status":"ok"'; then
    YTDLP_VER_SMOKED="$(echo "$SMOKE_OUTPUT" | grep -o '"ytDlpVersion":"[^"]*"' | head -1)"
    log_ok "Backend responde por stdin/stderr ✓  (${YTDLP_VER_SMOKED})"
    log_ok "server.ready ✓ · ping ✓ · server.shutdown ✓"
else
    log_error "El backend no respondió correctamente al ping JSON-RPC:"
    echo "$SMOKE_OUTPUT" | head -10
    exit 1
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
echo "   • Preferible: dejar que QuickShell recargue solo (vigila los archivos)."
echo "   • Si reinicias manualmente, NUNCA lo hagas con la pantalla bloqueada:"
echo "     matarías la pantalla de bloqueo (recuperación: hyprlock)."
echo -e "     ${BLUE}pkill -x qs && qs -c ii &${NC}"
echo ""
echo -e "${CYAN}🎮  ABRIR EL PANEL FLOTANTE:${NC}"
echo -e "   ${BLUE}CTRL + SUPER + D${NC}  (atajo de Hyprland)"
echo -e "   ${BLUE}qs -c ii ipc call mediaDownloader toggle${NC}"
echo ""
echo -e "${CYAN}⬇️  GESTOR DE DESCARGAS:${NC}"
echo "   • Sidebar derecho → pestaña «Descargas» → Descargar / Activas / Historial"
echo "   • El historial y las descargas activas se ven en el sidebar y en el panel"
echo ""
echo -e "${CYAN}🔧  DEMONIO (sobrevive a cerrar la barra lateral):${NC}"
echo -e "   ${BLUE}systemctl --user status media-download-center${NC}"
echo -e "   ${BLUE}journalctl --user -u media-download-center -f${NC}"
echo ""
echo -e "${CYAN}📋  DESINSTALAR:${NC}"
echo -e "   ${BLUE}./install.sh --uninstall${NC}"
echo ""
echo -e "${GREEN}¡Gracias por usar Media Download Center!${NC}"
