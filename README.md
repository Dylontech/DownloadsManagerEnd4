# 📥 Media Download Center

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Node](https://img.shields.io/badge/node-%3E%3D18.0.0-339933)

**Centro de descargas multimedia** para **Hyprland + QuickShell (Illogical-Impulse)**.
Soporta 8 plataformas: YouTube, Twitch, TikTok, Instagram, Twitter/X, Vimeo, SoundCloud y Bandcamp.

> ⚠️ **ADVERTENCIA**: Esta herramienta está diseñada para descargar contenido del que tengas los derechos necesarios o que esté explícitamente permitido para descarga.Respeta siempre los términos de servicio de cada plataforma y las leyes de propiedad intelectual de tu país.

---

## 📋 Tabla de Contenidos

- [Características](#-características)
- [Capturas](#-capturas)
- [Requisitos](#-requisitos)
- [Instalación Rápida](#-instalación-rápida)
- [Instalación Manual](#-instalación-manual)
- [Uso](#-uso)
- [Modos de Visualización](#-modos-de-visualización)
- [Proveedores Soportados](#-proveedores-soportados)
- [Solución de Problemas](#-solución-de-problemas)
- [Arquitectura](#-arquitectura)
- [Desarrollo](#-desarrollo)
- [Advertencias Legales](#️-advertencias-legales)

---

## ✨ Características

- 🎬 **Descarga videos** de 8 plataformas diferentes
- 🎵 **Extrae solo audio** (MP3, FLAC, AAC, OPUS, OGG, WAV)
- 📊 **Selector de calidad**: 144p hasta 2160p (4K)
- 📝 **Subtítulos**: descarga e incrustación automática
- 🖼️ **Miniaturas**: descarga e incrustación automática
- 📦 **Cola de descargas** con control de concurrencia
- ⏸️ **Pausar/Reanudar** descargas (vía SIGSTOP/SIGCONT)
- 🔄 **Reintentos automáticos** ante fallos
- 📜 **Historial** de descargas completo
- ⭐ **Favoritos** para marcar tus descargas importantes
- ⚙️ **Configuración** persistente (ruta, formato, calidad)
- 🖥️ **3 modos de visualización**: pestaña, panel lateral y ventana flotante

---

## 📸 Capturas

*(pendiente)*

---

## 📦 Requisitos

| Dependencia | Versión Mínima | Instalación |
|------------|---------------|-------------|
| **Node.js** | 18.0.0 | `sudo pacman -S nodejs` |
| **npm** | — | `sudo pacman -S npm` |
| **yt-dlp** | 2024.0+ | `sudo pacman -S yt-dlp` |
| **QuickShell** | última | [Illogical-Impulse/quickshell](https://github.com/Illogical-Impulse/Quickshell) |
| **TypeScript** | 5.0+ | `npm install -g typescript` (dev) |

> 💡 **Nota**: QuickShell (Illogical-Impulse) es un fork de [Quickshell](https://github.com/Quickshell/Quickshell). Los módulos QML están diseñados específicamente para este entorno.

---

## 🚀 Instalación Rápida

```bash
# 1. Clona el repositorio
git clone <url-del-repositorio> ~/Descargas/MediaDownloadCenter
cd ~/Descargas/MediaDownloadCenter

# 2. Da permisos de ejecución y ejecuta el instalador
chmod +x install.sh
./install.sh

# 3. Reinicia QuickShell
pkill quickshell && quickshell &
```

El script `install.sh` verificará las dependencias, instalará los paquetes npm,
compilará TypeScript y copiará los módulos QML desde `qml/` hacia la configuración de QuickShell.

---

## 🔧 Instalación Manual

### 1. Clonar e instalar dependencias

```bash
git clone <url-del-repositorio> ~/Descargas/MediaDownloadCenter
cd ~/Descargas/MediaDownloadCenter
npm install
```

### 2. Compilar TypeScript

```bash
npm run build
```

### 3. Verificar módulos QML

```bash
# Los QML vienen incluidos en el repositorio (carpeta qml/)
ls ~/Descargas/MediaDownloadCenter/qml/

# El script install.sh los copia automáticamente a:
# ~/.config/quickshell/ii/modules/ii/mediaDownloader/
```

Los archivos QML del frontend están empaquetados en `qml/` dentro del repositorio.
El script `install.sh` los copia automáticamente a la configuración de QuickShell.

### 4. Configurar QuickShell

Agrega el widget a tu configuración de QuickShell. Consulta la [documentación de QuickShell](https://github.com/Illogical-Impulse/Quickshell) para más detalles sobre cómo integrar módulos.

### 5. Reiniciar QuickShell

```bash
pkill quickshell && quickshell &
```

---

## 🎮 Uso

### Interfaz básica

1. **Abre el panel** desde el botón en la barra o atajo de teclado
2. **Pega un enlace** en el campo de URL (YouTube, Twitch, TikTok, etc.)
3. **Selecciona formato y calidad** en los menús desplegables
4. **Descarga** — el archivo se guardará en la carpeta configurada

### Panel de control

| Pestaña | Función |
|---------|---------|
| **Activo** | Descargas en progreso, pausadas y en cola |
| **Historial** | Lista de todas las descargas completadas |
| **Favoritos** | Descargas marcadas como favoritas |
| **Config** | Ruta de descarga, concurrencia, miniaturas, subtítulos |
| **Logs** | Registros de depuración y errores |

### Atajos

- `Ctrl+V` en el campo de URL para pegar desde el portapapeles
- `Escape` para limpiar el campo de URL
- Atajo configurable para toggle de ventana flotante

---

## 🖥️ Modos de Visualización

### Modo Pestaña (BottomWidgetGroup)
Diseñado para integrarse como una pestaña más en el grupo de widgets inferiores. Interfaz compacta con funcionalidades esenciales.

### Modo Panel (Sidebar)
Panel completo en la barra lateral derecha con acceso a historial, favoritos, configuración y logs.

### Modo Flotante (PanelWindow)
Ventana independiente que puede abrirse/cerrarse mediante un atajo de teclado global.

---

## 🔌 Proveedores Soportados

| Proveedor | Video | Audio | Playlist/Canales | Subtítulos | Miniaturas |
|-----------|:-----:|:-----:|:----------------:|:----------:|:----------:|
| **YouTube** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Twitch** | ✅ | ✅ | ❌ | ❌ | ✅ |
| **TikTok** | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Instagram** | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Twitter/X** | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Vimeo** | ✅ | ✅ | ❌ | ❌ | ✅ |
| **SoundCloud** | ❌ | ✅ | ❌ | ❌ | ✅ |
| **Bandcamp** | ❌ | ✅ | ❌ | ❌ | ✅ |

---

## 🔍 Solución de Problemas

### El backend no inicia
```bash
# Verifica que yt-dlp está instalado
yt-dlp --version

# Verifica Node.js
node --version

# Reconstruye el proyecto
cd ~/Descargas/MediaDownloadCenter
npm run build

# Prueba el backend directamente
node dist/index.js
```

### "Cannot read property 'write' of undefined"
Este error ocurría cuando `process.stdin` no estaba disponible en QuickShell. Asegúrate de tener la versión más reciente de los módulos QML con `stdinEnabled: true` y usando `process.write()` en lugar de `process.stdin.write()`.

**Solución**: Actualiza los archivos QML y reinicia QuickShell:
```bash
pkill quickshell && rm -rf ~/.cache/quickshell && quickshell &
```

### Las descargas fallan inmediatamente
```bash
# Verifica la versión de yt-dlp (debe ser 2024+)
yt-dlp --version

# Prueba con un video simple
yt-dlp -f "best[height<=720]" -o "/tmp/test.mp4" "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

### Error de base de datos
```bash
# Elimina la base de datos (se recreará automáticamente)
rm ~/.local/share/media-download-center/data.db
```

### Los módulos QML no se cargan
```bash
# Limpia la caché de QML y reinicia
rm -rf ~/.cache/quickshell/
pkill quickshell && quickshell &
```

### Ver logs de depuración
Revisa la pestaña **Logs** en el panel o ejecuta el backend en terminal:
```bash
cd ~/Descargas/MediaDownloadCenter
node dist/index.js
```

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────┐
│                    QuickShell (QML)                      │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ MediaWidget  │  │ MediaPanel   │  │ MediaFloating  │  │
│  └──────┬──────┘  └──────┬───────┘  └───────┬────────┘  │
│         │                │                  │            │
│         └────────────────┼──────────────────┘            │
│                    ┌─────┴──────┐                        │
│                    │  IPC (QML) │ ← stdin / stderr →     │
│                    └─────┬──────┘                        │
└──────────────────────────┼──────────────────────────────┘
                           │ JSON-RPC 2.0
┌──────────────────────────┼──────────────────────────────┐
│                    ┌─────┴──────┐                        │
│                    │  Node.js   │ ← backend process      │
│                    │  Backend   │                        │
│                    └─────┬──────┘                        │
│                          │                               │
│              ┌───────────┼───────────┐                   │
│              │           │           │                   │
│         ┌────┴────┐ ┌───┴───┐ ┌─────┴──────┐            │
│         │ Provider│ │Queue  │ │   SQLite    │            │
│         │ Manager │ │       │ │   (better-  │            │
│         │         │ │       │ │   sqlite3)  │            │
│         └─────────┘ └───┬───┘ └────────────┘            │
│                         │                                │
│                    ┌────┴─────┐                          │
│                    │ yt-dlp   │ ← child process           │
│                    │ adapter  │                          │
│                    └──────────┘                          │
└──────────────────────────────────────────────────────────┘
```

### Componentes Principales

| Componente | Descripción |
|------------|-------------|
| **Backend (Node.js)** | Procesa solicitudes JSON-RPC, orquesta descargas |
| **JsonRpcServer** | Servidor IPC vía stdin/stdout |
| **DownloadManager** | Fachada principal que orquesta todo el backend |
| **DownloadQueue** | Cola con control de concurrencia, reintentos, pausa |
| **ProviderManager** | Registro y detección de proveedores |
| **YtDlpAdapter** | Adaptador sobre yt-dlp (info, descarga, progreso) |
| **Providers** | 8 implementaciones específicas por plataforma |
| **SQLite DB** | Historial, configuración y favoritos persistentes |
| **QML UI** | 3 modos: widget compacto, panel completo, flotante |

### Flujo de una Descarga

```
Usuario pega URL → QML detecta provider → sendRequest("media.info")
  → Backend extrae info con yt-dlp -J → QML muestra preview
Usuario selecciona formato/calidad → Download
  → Encola tarea → DownloadQueue.processNext()
  → spawn(yt-dlp, args) → pipe stdout/stderr
  → QML recibe progreso vía notificaciones stderr
  → Al completar: registrar en historial + notificar a QML
```

---

## 💻 Desarrollo

### Comandos

```bash
npm run build    # Compilar TypeScript
npm run start    # Iniciar backend
npm run dev      # Modo desarrollo con hot-reload (tsx watch)
npm run clean    # Limpiar carpeta dist
```

### Estructura del Proyecto

```
src/
├── index.ts                 # Punto de entrada
├── adapters/
│   └── YtDlpAdapter.ts      # Capa sobre yt-dlp
├── core/
│   ├── DownloadManager.ts    # Orquestador principal
│   ├── DownloadQueue.ts      # Cola de descargas
│   └── ProviderManager.ts    # Registro de providers
├── db/
│   ├── Database.ts           # SQLite conexión/migraciones
│   ├── ConfigRepository.ts   # CRUD configuración
│   └── HistoryRepository.ts  # CRUD historial
├── ipc/
│   ├── JsonRpcProtocol.ts    # Tipos/serialización JSON-RPC
│   └── JsonRpcServer.ts      # Servidor IPC
├── providers/
│   ├── index.ts              # Factory de providers
│   ├── IProvider.ts          # Interfaz
│   ├── BaseProvider.ts       # Clase base
│   ├── YouTubeProvider.ts
│   ├── TwitchProvider.ts
│   ├── TikTokProvider.ts
│   ├── InstagramProvider.ts
│   ├── TwitterProvider.ts
│   ├── VimeoProvider.ts
│   ├── SoundCloudProvider.ts
│   └── BandcampProvider.ts
├── services/
│   ├── ConfigService.ts      # Lógica de configuración
│   └── HistoryService.ts     # Lógica de historial
├── types/
│   └── index.ts              # Tipos compartidos
└── utils/
    └── UrlValidator.ts       # Validación de URLs
```

---

## ⚠️ Advertencias Legales

> **LEE ESTO ATENTAMENTE**

1. **Propósito educativo**: Esta herramienta se proporciona con fines educativos y de investigación.

2. **Contenido autorizado**: Solo debes descargar contenido del cual tengas los derechos necesarios o que esté explícitamente permitido para descarga por el titular de los derechos.

3. **Términos de servicio**: El uso de esta herramienta para descargar contenido de plataformas como YouTube, Twitch, TikTok, etc., puede violar los Términos de Servicio de dichas plataformas. Eres responsable de conocer y cumplir con esos términos.

4. **Uso responsable**: No utilices esta herramienta para:
   - Infringir derechos de autor
   - Descargar contenido protegido sin autorización
   - Eludir medidas tecnológicas de protección
   - Acumular contenido de forma masiva o automatizada que pueda sobrecargar servidores

5. **Sin garantía**: Este software se proporciona "tal cual", sin garantía de ningún tipo. El autor no se hace responsable del uso que puedas darle.

6. **Responsabilidad del usuario**: **ERES EL ÚNICO RESPONSABLE** del uso que hagas de esta herramienta. Infórmate sobre las leyes aplicables en tu país antes de usarla.

---

## 📄 Licencia

MIT License — ver el archivo [LICENSE](LICENSE) para más detalles.

---

<p align="center">
  Hecho con ❤️ para la comunidad de Hyprland/QuickShell
  <br>
  <a href="#-media-download-center">Volver arriba ↑</a>
</p>
