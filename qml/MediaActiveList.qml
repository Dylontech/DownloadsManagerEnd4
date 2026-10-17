// ============================================================================
// MediaActiveList — Manejador de descargas activas (compartido)
// ============================================================================
// Lo usan la pestaña "Descargas" del sidebar y el panel flotante, así que ambos
// muestran SIEMPRE la misma cola (hay un solo demonio detrás).
//
// Es autónomo a propósito: pide la lista al demonio y se mantiene al día con
// las notificaciones `download.progress` / `download.status`. Como el demonio
// sobrevive a la UI, al montarse o al reconectarse basta con volver a pedir el
// estado: no hay nada que conservar en QML.
// ============================================================================

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.modules.ii.mediaDownloader

Item {
    id: root

    property var activeTasks: ({})
    property var activeTaskIds: []
    readonly property int count: root.activeTaskIds.length

    property string emptyText: Translation.tr("No active downloads")

    /** Vuelve a pedir la lista de descargas al demonio. */
    function refresh() {
        if (!MediaDownloaderIPC.backendReady) return;

        MediaDownloaderIPC.listDownloads()
            .then((tasks) => {
                const map = {};
                for (const t of tasks) {
                    // El historial y las tarjetas se ocupan de los estados
                    // terminales: aquí solo interesa lo que sigue vivo.
                    if (["running", "paused", "queued"].includes(t.status)) {
                        map[t.id] = t;
                    }
                }
                root.activeTasks = map;
                root.activeTaskIds = Object.keys(map);
            })
            .catch(() => {});
    }

    function updateProgress(taskId, progress) {
        const task = root.activeTasks[taskId];
        if (!task) return;
        task.progress = progress;
        // Se reemplaza el mapa entero: mutar una propiedad `var` no notifica.
        root.activeTasks = Object.assign({}, root.activeTasks);
    }

    function updateStatus(taskId, status) {
        const task = root.activeTasks[taskId];

        if (status === "completed" || status === "failed" || status === "cancelled") {
            // Se deja pasar el ciclo actual para que la tarjeta pueda pintar su
            // estado final antes de desaparecer.
            Qt.callLater(() => {
                const map = Object.assign({}, root.activeTasks);
                delete map[taskId];
                root.activeTasks = map;
                root.activeTaskIds = Object.keys(map);
            });
            return;
        }

        if (task) {
            task.status = status;
            root.activeTasks = Object.assign({}, root.activeTasks);
        }
    }

    Connections {
        target: MediaDownloaderIPC

        function onBackendReadyChanged() {
            // Se cumple también en cada reconexión, que es justo cuando hay que
            // reponer la vista.
            if (MediaDownloaderIPC.backendReady) root.refresh();
        }

        function onDownloadProgress(taskId, progress) {
            root.updateProgress(taskId, progress);
        }

        function onDownloadStatus(taskId, status) {
            root.updateStatus(taskId, status);
        }

        function onQueueDrained() {
            root.refresh();
        }
    }

    ListView {
        anchors.fill: parent
        spacing: 6
        clip: true

        model: root.activeTaskIds
        delegate: DownloadProgressCard {
            width: ListView.view.width
            task: root.activeTasks[modelData]

            onCancelClicked: (taskId) => { MediaDownloaderIPC.cancelDownload(taskId); }
            onPauseClicked: (taskId) => { MediaDownloaderIPC.pauseDownload(taskId); }
            onResumeClicked: (taskId) => { MediaDownloaderIPC.resumeDownload(taskId); }
            onRemoveClicked: (taskId) => { MediaDownloaderIPC.removeDownload(taskId); }
        }

        StyledText {
            anchors.centerIn: parent
            text: root.emptyText
            color: Appearance.colors.colOnLayer0
            opacity: 0.4
            visible: parent.count === 0
        }
    }
}
