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
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !urlInput.fieldFocused) {
            // Enter fuera del campo: descargar si ya hay enlace analizado
            event.accepted = true;
            if (root.hasMediaInfo) root.startDownload();
            else if (urlInput.url.length > 0) urlInput.submitCurrent();
        }
    }

    // ─── Layout ───────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 10

        // ─── Input URL ────────────────────────────────────────────────────

        UrlInput {
            id: urlInput
            Layout.fillWidth: true
            detecting: root.loading

            onSubmit: (url) => {
                root.submitUrl(url);
            }
        }

        // ─── Loading indicator ────────────────────────────────────────────

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            spacing: 8
            visible: root.loading

            MaterialLoadingIndicator {
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: Translation.tr("Analyzing link...")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                opacity: 0.7
            }
        }

        // ─── Error ────────────────────────────────────────────────────────

        ErrorBanner {
            message: root.lastError
            hint: root.errorHint(root.lastError)
        }

        // ─── Preview + formato (zona desplazable y acotada) ───────────────
        //
        // El alto disponible en la barra lateral es pequeño: si el preview y
        // los selectores crecieran sin límite, empujarían el botón de descarga
        // fuera de la pantalla. Se les da su alto natural como máximo y, si no
        // cabe, esta zona se vuelve desplazable.

        Flickable {
            id: mediaScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: mediaForm.implicitHeight
            Layout.minimumHeight: 52
            Layout.maximumHeight: Math.max(52, Math.min(mediaForm.implicitHeight, root.height * 0.6))
            visible: root.hasMediaInfo
            contentHeight: mediaForm.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ScrollBar.vertical: StyledScrollBar {}

            ColumnLayout {
                id: mediaForm
                width: mediaScroll.width
                spacing: 8

                MediaPreview {
                    id: mediaPreview
                    Layout.fillWidth: true
                    mediaInfo: root.currentMediaInfo
                    loading: root.loading
                }

                FormatSelector {
                    id: formatSelector
                    Layout.fillWidth: true
                    formats: root.currentFormats
                }
            }
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

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: "download"
                    iconSize: 18
                    color: "#FFF"
                }

                StyledText {
                    text: Translation.tr("Download")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: "#FFF"
                }
            }

            onClicked: {
                root.startDownload();
            }
        }

        // ─── Active Downloads ─────────────────────────────────────────────

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            visible: root.activeTaskIds.length > 0

            RowLayout {
                id: activeHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                MaterialSymbol {
                    text: "downloading"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.8
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Active Downloads")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.8
                }

                StyledText {
                    text: root.activeTaskIds.length
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.5
                }
            }

            ListView {
                anchors.top: activeHeader.bottom
                anchors.topMargin: 6
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
                width: parent.width * 0.9
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 76
                    Layout.preferredHeight: 76
                    radius: 38
                    color: Appearance.colors.colLayer1

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "download_for_offline"
                        iconSize: 38
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.75
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Paste a link to start downloading")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.8
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("YouTube · Twitch · TikTok · Instagram · X · Vimeo · SoundCloud · Bandcamp")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.45
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ─── Componente interno: aviso de error ───────────────────────────────

    component ErrorBanner: Rectangle {
        id: banner
        property string message: ""
        property string hint: ""

        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + 16
        radius: Appearance.rounding.small
        color: "#26FF5252"
        border.width: 1
        border.color: "#66FF5252"
        visible: banner.message.length > 0

        RowLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "error"
                iconSize: 18
                color: "#FF6B6B"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: banner.message
                    color: "#FF8A8A"
                    font.pixelSize: Appearance.font.pixelSize.small
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: banner.hint
                    visible: banner.hint.length > 0
                    color: "#FFC9C9"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    opacity: 0.9
                }
            }
        }
    }

    // ─── Funciones ────────────────────────────────────────────────────────

    /**
     * Enter en el campo: si el enlace ya está analizado se descarga; si no,
     * se analiza primero.
     */
    function submitUrl(url) {
        if (root.currentMediaInfo !== null && url === root.lastUrl) {
            root.startDownload();
        } else {
            root.analyzeUrl(url);
        }
    }

    /**
     * Pista adicional para los errores de servicios con verificación anti-bot.
     */
    function errorHint(message) {
        const text = String(message ?? "").toLowerCase();
        if (text.includes("not a bot") || text.includes("cookies") || text.includes("sign in")) {
            return Translation.tr("Tip: import cookies from your browser in the Config tab.");
        }
        return "";
    }

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
                if (!info) {
                    root.lastError = Translation.tr("The link returned no information");
                    root.loading = false;
                    return;
                }
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
