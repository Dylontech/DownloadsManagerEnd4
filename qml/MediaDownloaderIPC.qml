// ============================================================================
// MediaDownloaderIPC — Puente JSON-RPC entre QuickShell y Node.js backend
// ============================================================================
//
// Gestiona el proceso Node.js, envía requests JSON-RPC y recibe respuestas.
// Expone señales y métodos para que la UI los consuma.
//
// Uso:
//   MediaDownloaderIPC {
//     onMediaInfoReceived: (info) => { ... }
//     onDownloadProgress: (taskId, progress) => { ... }
//   }
//
// ============================================================================

import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

pragma ComponentBehavior: Bound

Scope {
    id: root

    // ─── Propiedades ──────────────────────────────────────────────────────

    property bool backendReady: false
    property string backendVersion: ""
    property string ytDlpVersion: ""

    // Buffer de requests pendientes
    property var pendingRequests: ({})
    property var requestIdCounter: 1

    // Estado de conexión
    property bool connected: process.running && root.backendReady

    // Buffer de logs accesible desde la UI
    property var logBuffer: []
    property int maxLogs: 200

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

    // ─── Proceso Node.js ──────────────────────────────────────────────────

    Process {
        id: process
        command: ["/bin/bash", "-c", "cd /home/DylontechArch/Descargas/DownLoadsManagerEnd4 && /usr/bin/node dist/index.js"]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                // stdout no se usa (SplitParser no funciona con stdout en esta versión)
            }
        }

        stderr: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (!text) return;

                // Los mensajes JSON-RPC empiezan con {, el resto son debug
                if (text.startsWith("{")) {
                    root.processLine(text);
                } else if (text.startsWith("STDERR_") || text === "HEARTBEAT") {
                    // Ignorar mensajes de debug interno
                } else {
                    root.addLog("[stderr] " + text, "error");
                }
            }
        }

        onRunningChanged: {
            if (running) {
                root.addLog("Backend process started", "info");
            } else {
                root.backendReady = false;
                root.addLog("Backend process stopped", "warn");
            }
        }
    }

    // Buffer de línea parcial
    property string lineBuffer: ""

    // ─── Procesamiento de líneas JSON desde stdout ──────────────────────

    function processLine(line) {
        if (!line) return;

        // Acumular en buffer (por si llegaron fragmentos)
        root.lineBuffer += line;

        // Intentar parsear como JSON
        try {
            const msg = JSON.parse(root.lineBuffer);
            root.lineBuffer = ""; // Limpiar buffer

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
        } catch (e) {
            // JSON incompleto, esperar más datos
            // El buffer se mantiene
        }
    }

    // ─── Envío de Requests ────────────────────────────────────────────────

    function sendRequest(method, params) {
        return new Promise((resolve, reject) => {
            if (!process.running) {
                reject(new Error("Backend not running"));
                return;
            }

            if (!process.stdinEnabled) {
                reject(new Error("Process stdin is not available"));
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

            // Timeout de 30s
            const timer = Qt.createQmlObject(
                "import QtQuick; Timer { interval: 30000; repeat: false; onTriggered: {}}",
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

            process.write(JSON.stringify(request) + "\n");
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
                root.backendReady = true;
                root.backendVersion = msg.params?.version || "";
                root.addLog("Backend ready (v" + root.backendVersion + ")", "ok");
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
