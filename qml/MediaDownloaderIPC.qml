pragma Singleton
pragma ComponentBehavior: Bound

// ============================================================================
// MediaDownloaderIPC — Puente JSON-RPC entre QuickShell y el demonio Node.js
// ============================================================================
//
// ⚠️ Los `pragma` van en la PRIMERA línea a propósito: el registro de módulos
// solo los detecta ahí. Si `pragma Singleton` queda debajo de comentarios o
// imports, el tipo se registra como componente normal y `MediaDownloaderIPC`
// se convierte en un objeto vacío (sin propiedades ni métodos) en vez del
// singleton.
//
// Es un SINGLETON a propósito. El backend es un demonio independiente que
// escucha en un socket Unix, y este objeto es el único cliente del shell.
//
// Antes cada UI (panel flotante y widget del sidebar) instanciaba su propio
// `MediaDownloaderIPC`, y dentro había un `Process` hijo del componente: al
// cerrar el sidebar o cambiar de pestaña QuickShell destruía el componente y
// mataba el proceso Node, que a su vez mataba los yt-dlp en curso. Ahora aquí
// no se lanza ningún proceso: solo se abre (y se reabre) el socket.
//
// Uso desde cualquier componente, sin instanciarlo:
//   Connections { target: MediaDownloaderIPC
//       function onDownloadProgress(taskId, progress) { ... } }
//   MediaDownloaderIPC.startDownload({ url: ... })
//
// ============================================================================

import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ─── Propiedades ──────────────────────────────────────────────────────

    property bool backendReady: false
    property string backendVersion: ""
    property string ytDlpVersion: ""

    // Buffer de requests pendientes
    property var pendingRequests: ({})
    property var requestIdCounter: 1

    // ─── Conexión con el demonio ──────────────────────────────────────────

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") ?? ""
    readonly property string socketPath: root.runtimeDir
        ? `${root.runtimeDir}/media-download-center.sock`
        : ""
    readonly property string serviceUnit: "media-download-center.service"
    readonly property int reconnectInterval: 2000

    // Estado de conexión. `backendReady` solo se pone a true cuando el demonio
    // ha contestado por el socket, no por el mero hecho de abrirlo.
    property bool connecting: false
    property bool connected: socket.connected && root.backendReady

    // Buffer de logs accesible desde la UI
    property var logBuffer: []
    property int maxLogs: 200

    // Presupuesto de espera por request (yt-dlp puede tardar ~45s en analizar)
    property int requestTimeout: 75000

    function addLog(message, type) {
        const entry = {
            time: new Date().toLocaleTimeString(),
            message: String(message),
            type: type || "info"
        };
        root.logBuffer = [entry].concat(root.logBuffer).slice(0, root.maxLogs);
        console.log("[MediaDownloader]", message);
    }

    // ─── Señales ──────────────────────────────────────────────────────────

    signal serverReady()
    signal serverShutdown()

    // Media info
    signal mediaInfoReceived(string url, var info)
    signal mediaInfoError(string url, string error)

    // Download progress/status
    signal downloadProgress(string taskId, var progress)
    signal downloadStatus(string taskId, string status, string previous)
    signal downloadCompleted(string taskId, var info)
    signal downloadFailed(string taskId, string error)

    // Queue
    signal queueDrained()

    // Error general
    signal ipcError(string message)

    // ─── Cliente del socket del demonio ───────────────────────────────────

    Socket {
        id: socket
        path: root.socketPath
        connected: false

        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => root.processLine(line)
        }

        onConnectionStateChanged: {
            if (connected) {
                root.onSocketUp();
            } else {
                root.onSocketDown();
            }
        }

        onError: (error) => {
            root.connecting = false;
            root.backendReady = false;
            // Lo normal nada más arrancar la sesión: el demonio aún no está.
            // El error concreto de QLocalSocket no aporta nada al usuario.
            root.addLog("Socket no disponible (" + error + ")", "warn");
        }
    }

    // Reintento de conexión. Cerrar la barra lateral ya no interrumpe nada, así
    // que este temporizador solo cubre "el demonio todavía no escuchaba".
    Timer {
        id: reconnectTimer
        interval: root.reconnectInterval
        repeat: true
        running: true
        onTriggered: {
            if (!socket.connected && !root.connecting) {
                root.connectSocket();
            }
        }
    }

    // Si el socket no existe, se pide a systemd que levante el servicio.
    // `systemctl --user start` sobre una unidad ya activa no hace nada, así que
    // repetirlo es inofensivo.
    Timer {
        id: serviceStartTimer
        interval: 10000
        repeat: true
        running: true
        onTriggered: {
            if (!socket.connected) {
                Quickshell.execDetached(["systemctl", "--user", "start", root.serviceUnit]);
            }
        }
    }

    Component.onCompleted: root.connectSocket()

    // ─── Ciclo de vida de la conexión ─────────────────────────────────────

    function connectSocket() {
        if (!root.socketPath) return;
        if (socket.connected) return;
        root.connecting = true;
        socket.connected = true;
    }

    function onSocketUp() {
        root.connecting = false;
        root.addLog("Conectado al demonio (" + root.socketPath + ")", "ok");
    }

    function onSocketDown() {
        root.connecting = false;
        if (!root.backendReady) return;
        root.backendReady = false;
        root.addLog("Desconectado del demonio", "warn");
        root.serverShutdown();
    }

    /**
     * El demonio envía `server.ready` en CADA conexión nueva, así que es aquí
     * donde la UI se entera de que debe volver a pedir su estado (descargas
     * activas e historial): el modelo no se guarda en QML a propósito.
     */
    function handleServerReady(params) {
        root.backendReady = true;
        root.backendVersion = params?.version || "";
        root.addLog("Backend ready (v" + root.backendVersion + ")", "ok");
    }

    // ─── Procesamiento de las líneas que llegan por el socket ────────────

    function processLine(line) {
        if (!line) return;

        const text = line.trim();
        if (!text) return;

        // SplitParser ya entrega líneas completas, así que solo se procesa lo
        // que parece JSON-RPC; el resto (logs del demonio) se ignora.
        if (!text.startsWith("{")) return;

        let msg;
        try {
            msg = JSON.parse(text);
        } catch (e) {
            root.addLog("Mensaje IPC ilegible descartado: " + text.slice(0, 120), "warn");
            return;
        }

        if (msg.jsonrpc !== "2.0") return;

        if (msg.id !== undefined && msg.id !== null && "result" in msg) {
            // Es una respuesta a una request nuestra
            root.handleResponse(msg);
        } else if (msg.id !== undefined && msg.id !== null && "error" in msg) {
            // Es una respuesta con error
            root.handleErrorResponse(msg);
        } else if (msg.method) {
            // Es una notificación del servidor
            root.handleNotification(msg);
        }
    }

    // ─── Envío de Requests ────────────────────────────────────────────────

    function sendRequest(method, params) {
        return new Promise((resolve, reject) => {
            if (!socket.connected) {
                // No se pierde nada: la UI se resincroniza al reconectar, así
                // que es mejor fallar rápido que dejar la promesa colgada.
                root.connectSocket();
                reject(new Error("Sin conexión con el demonio de descargas"));
                return;
            }

            const id = root.requestIdCounter++;
            const request = {
                jsonrpc: "2.0",
                id: id,
                method: method,
                params: params,
            };

            root.pendingRequests[id] = { resolve, reject };

            // El backend puede tardar hasta 45s analizando un enlace con
            // yt-dlp; el cliente debe esperar más para recibir el error real
            // en vez de un "timed out" genérico.
            const timer = Qt.createQmlObject(
                `import QtQuick; Timer { interval: ${root.requestTimeout}; repeat: false; onTriggered: {}}`,
                root
            );
            timer.triggered.connect(() => {
                if (root.pendingRequests[id]) {
                    root.pendingRequests[id].reject(new Error(`Request "${method}" timed out`));
                    delete root.pendingRequests[id];
                }
                timer.destroy();
            });
            timer.start();

            socket.write(JSON.stringify(request) + "\n");
            socket.flush();
        });
    }

    // ─── Manejo de Respuestas ─────────────────────────────────────────────

    function handleResponse(msg) {
        const pending = root.pendingRequests[msg.id];
        if (pending) {
            pending.resolve(msg.result);
            delete root.pendingRequests[msg.id];
        }
    }

    function handleErrorResponse(msg) {
        const pending = root.pendingRequests[msg.id];
        if (pending) {
            pending.reject(new Error(msg.error?.message || "Unknown error"));
            delete root.pendingRequests[msg.id];
        }
    }

    // ─── Manejo de Notificaciones ─────────────────────────────────────────

    function handleNotification(msg) {
        switch (msg.method) {
            case "server.ready":
                root.handleServerReady(msg.params);
                root.serverReady();
                break;

            case "server.shutdown":
                root.backendReady = false;
                root.serverShutdown();
                break;

            case "download.progress":
                root.downloadProgress(msg.params.taskId, msg.params.progress);
                break;

            case "download.status":
                root.downloadStatus(msg.params.taskId, msg.params.status, msg.params.previous);
                break;

            case "download.completed":
                root.downloadCompleted(msg.params.taskId, msg.params);
                root.addLog("Download completed: " + (msg.params.title || ""), "ok");
                break;

            case "download.failed":
                root.downloadFailed(msg.params.taskId, msg.params.error);
                root.addLog("Download failed: " + msg.params.error, "error");
                break;

            case "queue.drained":
                root.queueDrained();
                break;

            default:
                console.log("[MediaDownloader] Unhandled notification:", msg.method);
        }
    }

    // ─── API Pública ──────────────────────────────────────────────────────

    function ping() {
        return root.sendRequest("ping");
    }

    function listProviders() {
        return root.sendRequest("providers.list");
    }

    function detectProvider(url) {
        return root.sendRequest("providers.detect", { url });
    }

    function getMediaInfo(url) {
        return root.sendRequest("media.info", { url })
            .then((info) => {
                root.mediaInfoReceived(url, info);
                return info;
            })
            .catch((err) => {
                root.mediaInfoError(url, err.message);
                throw err;
            });
    }

    function getFormats(url) {
        return root.sendRequest("media.formats", { url });
    }

    function getSubtitles(url) {
        return root.sendRequest("media.subtitles", { url });
    }

    function startDownload(params) {
        return root.sendRequest("download.start", params);
    }

    function pauseDownload(taskId) {
        return root.sendRequest("download.pause", { taskId });
    }

    function resumeDownload(taskId) {
        return root.sendRequest("download.resume", { taskId });
    }

    function cancelDownload(taskId) {
        return root.sendRequest("download.cancel", { taskId });
    }

    function removeDownload(taskId) {
        return root.sendRequest("download.remove", { taskId });
    }

    function listDownloads(status) {
        return root.sendRequest("download.list", status ? { status } : {});
    }

    function getDownload(taskId) {
        return root.sendRequest("download.get", { taskId });
    }

    function listHistory(limit, offset) {
        return root.sendRequest("history.list", { limit, offset });
    }

    function listFavorites(limit, offset) {
        return root.sendRequest("history.favorites", { limit, offset });
    }

    function searchHistory(query) {
        return root.sendRequest("history.search", { query });
    }

    function toggleFavorite(entryId) {
        return root.sendRequest("history.toggleFavorite", { id: entryId });
    }

    function deleteHistory(entryId) {
        return root.sendRequest("history.delete", { id: entryId });
    }

    function clearHistory() {
        return root.sendRequest("history.clear");
    }

    function getConfig(key) {
        return root.sendRequest("config.get", key ? { key } : {});
    }

    function setConfig(key, value) {
        return root.sendRequest("config.set", { key, value });
    }

    function getSystemStatus() {
        return root.sendRequest("system.status");
    }

    function clearCompleted() {
        return root.sendRequest("system.clearCompleted");
    }
}
