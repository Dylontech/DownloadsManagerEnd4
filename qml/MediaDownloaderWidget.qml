// ============================================================================
// MediaDownloaderWidget — Widget compacto (modo pestaña)
// ============================================================================
// Diseñado para integrarse en BottomWidgetGroup como una pestaña más.
// Muestra: input URL → preview → selector formato → descargar → mini cola
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

    // ─── IPC ──────────────────────────────────────────────────────────────

    MediaDownloaderIPC {
        id: ipc
        onBackendReadyChanged: {
            if (ipc.backendReady) {
                console.log("[MediaDownloader] Backend ready");
                root.refreshDownloads();
                root.backendRetryTimer.stop();
            }
        }

        onServerReady: {
            console.log("[MediaDownloader] Server signaled ready");
        }

        onDownloadProgress: (taskId, progress) => {
            root.updateTaskProgress(taskId, progress);
        }

        onDownloadStatus: (taskId, status, previous) => {
            root.handleStatusChange(taskId, status, previous);
        }

        onDownloadCompleted: (taskId, info) => {
            console.log("[MediaDownloader] Download completed:", taskId, info?.title);
        }

        onDownloadFailed: (taskId, error) => {
            console.warn("[MediaDownloader] Download failed:", taskId, error);
        }
    }

    // ─── Estado ───────────────────────────────────────────────────────────

    property var activeTasks: ({})
    property var activeTaskIds: []
    property bool loading: false
    property string lastError: ""
    property string lastUrl: ""

    property var currentMediaInfo: null
    property var currentFormats: []
    property bool hasMediaInfo: currentMediaInfo !== null

    // Reintentar conexión al backend cada 2s hasta que responda
    Timer {
        id: backendRetryTimer
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (ipc.backendReady) {
                stop();
            } else {
                ipc.ping().then(() => {}).catch(() => {});
            }
        }
    }

    // ─── Keys ─────────────────────────────────────────────────────────────

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            urlInput.url = "";
            urlInput.focus = false;
        }
    }

    // ─── Layout ───────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ─── Input URL ────────────────────────────────────────────────────

        UrlInput {
            id: urlInput
            Layout.fillWidth: true
            detecting: root.loading

            onSubmit: (url) => {
                root.analyzeUrl(url);
            }
        }

        // ─── Loading indicator ────────────────────────────────────────────

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: root.loading
        }

        // ─── Error ────────────────────────────────────────────────────────

        StyledText {
            Layout.fillWidth: true
            text: root.lastError
            color: "#FF5252"
            font.pixelSize: Appearance.font.pixelSize.small
            visible: root.lastError.length > 0
            wrapMode: Text.WordWrap
        }

        // ─── Preview ──────────────────────────────────────────────────────

        MediaPreview {
            id: mediaPreview
            Layout.fillWidth: true
            mediaInfo: root.currentMediaInfo
            loading: root.loading
        }

        // ─── Format Selector ──────────────────────────────────────────────

        FormatSelector {
            id: formatSelector
            Layout.fillWidth: true
            visible: root.hasMediaInfo
            formats: root.currentFormats
        }

        // ─── Download Button ──────────────────────────────────────────────

        RippleButton {
            id: downloadBtn
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            buttonRadius: Appearance.rounding.normal
            buttonColor: Appearance.colors.colPrimary
            enabled: root.hasMediaInfo && !root.loading
            visible: root.hasMediaInfo

            StyledText {
                anchors.centerIn: parent
                text: Translation.tr("Download")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: "#FFF"
            }

            onClicked: {
                root.startDownload();
            }
        }

        // ─── Active Downloads ─────────────────────────────────────────────

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            height: 10
            visible: root.activeTaskIds.length > 0

            StyledText {
                anchors.top: parent.top
                anchors.left: parent.left
                text: Translation.tr("Active Downloads")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
                opacity: 0.7
            }

            ListView {
                anchors.top: parent.top
                anchors.topMargin: 20
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 8
                clip: true

                model: root.activeTaskIds
                delegate: DownloadProgressCard {
                    width: ListView.view.width
                    task: root.activeTasks[modelData]

                    onCancelClicked: (taskId) => { ipc.cancelDownload(taskId); }
                    onPauseClicked: (taskId) => { ipc.pauseDownload(taskId); }
                    onResumeClicked: (taskId) => { ipc.resumeDownload(taskId); }
                    onRemoveClicked: (taskId) => { ipc.removeDownload(taskId); }
                }
            }
        }

        // ─── Empty state ──────────────────────────────────────────────────

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.hasMediaInfo && root.activeTaskIds.length === 0 && !root.loading

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "download_for_offline"
                    iconSize: 48
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.3
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Paste a link to start downloading")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.4
                }
            }
        }
    }

    // ─── Funciones ────────────────────────────────────────────────────────

    function analyzeUrl(url) {
        if (!ipc.backendReady) {
            root.lastError = Translation.tr("Backend not ready. Please wait...");
            return;
        }

        root.lastError = "";
        root.loading = true;
        root.currentMediaInfo = null;
        root.lastUrl = url;

        ipc.getMediaInfo(url)
            .then((info) => {
                root.currentMediaInfo = info;
                root.currentFormats = info.formats ?? [];
                root.loading = false;
            })
            .catch((err) => {
                root.lastError = err.message || Translation.tr("Failed to analyze URL");
                root.loading = false;
            });
    }

    function startDownload() {
        if (!root.currentMediaInfo) return;

        const config = {
            url: root.lastUrl,
            format: formatSelector.selectedFormat,
            quality: formatSelector.selectedQuality,
            extractAudio: formatSelector.extractAudio,
            downloadThumbnail: true,
            embedThumbnail: true,
            embedMetadata: true,
        };

        if (formatSelector.selectedQuality === "custom" && formatSelector.customFormat.length > 0) {
            config.customFormat = formatSelector.customFormat;
        }

        ipc.startDownload(config)
            .then((result) => {
                console.log("[MediaDownloader] Download started:", result.taskId);
                // Añadir a la lista de activas
                root.addTaskToList(result);
                // Limpiar URL
                urlInput.clear();
                root.currentMediaInfo = null;
            })
            .catch((err) => {
                root.lastError = err.message || Translation.tr("Failed to start download");
            });
    }

    function addTaskToList(result) {
        const task = {
            id: result.taskId,
            status: "queued",
            mediaInfo: result.mediaInfo,
            options: {
                url: root.lastUrl,
                format: formatSelector.selectedFormat,
                quality: formatSelector.selectedQuality,
                extractAudio: formatSelector.extractAudio,
            },
            progress: {
                percent: 0,
                speed: 0,
                eta: 0,
                downloadedBytes: 0,
                totalBytes: 0,
                speedFormatted: "",
                etaFormatted: "",
                downloadedFormatted: "",
                totalFormatted: "",
            },
            createdAt: Date.now(),
        };

        root.activeTasks[result.taskId] = task;
        root.activeTaskIds = Object.keys(root.activeTasks);
    }

    function updateTaskProgress(taskId, progress) {
        if (root.activeTasks[taskId]) {
            root.activeTasks[taskId].progress = progress;
            root.activeTaskIds = Object.keys(root.activeTasks); // Trigger refresh
        }
    }

    function handleStatusChange(taskId, status, previous) {
        if (root.activeTasks[taskId]) {
            root.activeTasks[taskId].status = status;
            root.activeTaskIds = Object.keys(root.activeTasks);
        }

        if (status === "completed" || status === "failed" || status === "cancelled") {
            // Eliminar de activas después de un momento
            Qt.callLater(() => {
                delete root.activeTasks[taskId];
                root.activeTaskIds = Object.keys(root.activeTasks);
            });
        }
    }

    function refreshDownloads() {
        if (!ipc.backendReady) return;
        ipc.listDownloads()
            .then((tasks) => {
                for (const t of tasks) {
                    if (t.status === "running" || t.status === "paused" || t.status === "queued") {
                        root.activeTasks[t.id] = t;
                    }
                }
                root.activeTaskIds = Object.keys(root.activeTasks);
            })
            .catch(() => {});
    }
}
