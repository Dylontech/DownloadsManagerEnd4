// ============================================================================
// MediaDownloaderPanel — Panel completo (modo sidebar)
// ============================================================================
// Diseñado para ocupar todo el espacio de la sidebar derecha.
// Incluye: descargas activas, historial, favoritos, configuración.
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
                root.loadHistory();
                root.refreshActive();
                root.loadConfig();
            }
        }

        onDownloadProgress: (taskId, progress) => {
            root.updateTaskProgress(taskId, progress);
        }

        onDownloadStatus: (taskId, status, previous) => {
            root.handleStatusChange(taskId, status, previous);
        }
    }

    // ─── Estado ───────────────────────────────────────────────────────────

    property var activeTasks: ({})
    property var activeTaskIds: []
    property var historyEntries: []
    property var favoriteEntries: []
    property var currentMediaInfo: null
    property var currentFormats: []

    property bool loading: false
    property string lastError: ""
    property string lastUrl: ""
    property string currentTab: "download"

    property int sidebarPadding: 10

    // Reintentar conexión al backend
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

    // ─── Config ───────────────────────────────────────────────────────────

    property string defaultPath: "~/Descargas/MediaDownloadCenter"
    property int maxConcurrent: 3
    property bool autoThumbnail: true
    property bool autoSubtitles: false

    // ─── Layout principal ─────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: sidebarPadding
        spacing: sidebarPadding

        // ─── Header ───────────────────────────────────────────────────────

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "download"
                iconSize: 24
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                text: Translation.tr("Media Download Center")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
                Layout.fillWidth: true
            }
        }

        // ─── URL Input Bar ────────────────────────────────────────────────

        UrlInput {
            id: urlInput
            Layout.fillWidth: true
            detecting: root.loading

            onSubmit: (url) => {
                root.analyzeUrl(url);
            }
        }

        // ─── Loading / Error ──────────────────────────────────────────────

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: root.loading
        }

        StyledText {
            Layout.fillWidth: true
            text: root.lastError
            color: "#FF5252"
            font.pixelSize: Appearance.font.pixelSize.small
            visible: root.lastError.length > 0
            wrapMode: Text.WordWrap
        }

        // ─── Preview + Download (when media detected) ─────────────────────

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.currentMediaInfo !== null

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

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                buttonRadius: Appearance.rounding.normal
                buttonColor: Appearance.colors.colPrimary
                enabled: !root.loading

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Download")
                    font.weight: Font.Medium
                    color: "#FFF"
                }

                onClicked: {
                    root.startDownload();
                }
            }
        }

        // ─── Tab Bar ──────────────────────────────────────────────────────

        SecondaryTabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: ["download", "history", "favorites", "config", "logs"].indexOf(root.currentTab)

            Repeater {
                model: [
                    { icon: "downloading", name: Translation.tr("Active") },
                    { icon: "history", name: Translation.tr("History") },
                    { icon: "favorite", name: Translation.tr("Favorites") },
                    { icon: "settings", name: Translation.tr("Config") },
                    { icon: "bug_report", name: Translation.tr("Logs") },
                ]

                delegate: SecondaryTabButton {
                    buttonIcon: modelData.icon
                    buttonText: modelData.name
                    onClicked: {
                        const tabs = ["download", "history", "favorites", "config", "logs"];
                        root.currentTab = tabs[index];
                        // Cargar datos al cambiar de pestaña
                        if (tabs[index] === "favorites") root.loadFavorites();
                        if (tabs[index] === "history") root.loadHistory();
                    }
                }
            }
        }

        // ─── Content Area ─────────────────────────────────────────────────

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            clip: true

            SwipeView {
                id: swipeView
                anchors.fill: parent
                currentIndex: tabBar.currentIndex
                interactive: false

                // ─── Tab: Active Downloads ────────────────────────────────
                Item {
                    ListView {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
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

                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("No active downloads")
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.4
                            visible: parent.count === 0
                        }
                    }
                }

                // ─── Tab: History ─────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        MaterialTextField {
                            id: historySearch
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Search history...")
                            onTextChanged: {
                                if (text.length > 2) {
                                    root.searchHistory(text);
                                } else if (text.length === 0) {
                                    root.loadHistory();
                                }
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4
                            clip: true

                            model: root.historyEntries
                            delegate: HistoryItem {
                                width: ListView.view.width
                                entry: modelData
                                handleDelete: function(entryId) {
                                    ipc.deleteHistory(entryId).then(() => root.loadHistory());
                                }
                                handleFavorite: function(entryId) {
                                    ipc.toggleFavorite(entryId).then(() => root.loadHistory());
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: Translation.tr("No history yet")
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.4
                                visible: parent.count === 0
                            }
                        }
                    }
                }

                // ─── Tab: Favorites ───────────────────────────────────────
                Item {
                    ListView {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        clip: true

                        model: root.favoriteEntries
                        delegate: HistoryItem {
                            width: ListView.view.width
                            entry: modelData
                            handleDelete: function(entryId) {
                                ipc.deleteHistory(entryId).then(() => root.loadFavorites());
                            }
                            handleFavorite: function(entryId) {
                                ipc.toggleFavorite(entryId).then(() => root.loadFavorites());
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("No favorites yet")
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.4
                            visible: parent.count === 0
                        }
                    }
                }

                // ─── Tab: Config ──────────────────────────────────────────
                Item {
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 8
                        contentHeight: configColumn.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: configColumn
                            width: parent.width
                            spacing: 10

                            // Download path
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    text: Translation.tr("Download Path")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer0
                                }

                                MaterialTextField {
                                    id: pathField
                                    Layout.fillWidth: true
                                    text: root.defaultPath
                                    onEditingFinished: {
                                        ipc.setConfig("default_download_path", text);
                                    }
                                }
                            }

                            // Max concurrent
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                StyledText {
                                    text: Translation.tr("Max Concurrent")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer0
                                }

                                StyledSpinBox {
                                    id: concurrentSpin
                                    from: 1
                                    to: 10
                                    value: root.maxConcurrent
                                    onValueModified: {
                                        ipc.setConfig("max_concurrent_downloads", String(value));
                                    }
                                }
                            }

                            // Toggles
                            ConfigSwitch {
                                text: Translation.tr("Auto-download thumbnails")
                                checked: root.autoThumbnail
                                onCheckedChanged: {
                                    ipc.setConfig("auto_download_thumbnail", checked ? "true" : "false");
                                }
                            }

                            ConfigSwitch {
                                text: Translation.tr("Auto-download subtitles")
                                checked: root.autoSubtitles
                                onCheckedChanged: {
                                    ipc.setConfig("auto_download_subtitles", checked ? "true" : "false");
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // ─── Tab: Logs ────────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Connection Logs")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer0
                            }

                            RippleButton {
                                buttonRadius: Appearance.rounding.small
                                buttonColor: Appearance.colors.colLayer2
                                implicitWidth: 60
                                implicitHeight: 24

                                StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Copy")
                                    font.pixelSize: 10
                                    color: Appearance.colors.colOnLayer0
                                }

                                onClicked: {
                                    const texts = [];
                                    for (const entry of ipc.logBuffer) {
                                        texts.push(entry.time + " " + entry.message);
                                    }
                                    Quickshell.clipboardText = texts.join("\n");
                                    ipc.addLog("Logs copied to clipboard", "ok");
                                }
                            }

                            RippleButton {
                                buttonRadius: Appearance.rounding.small
                                buttonColor: Appearance.colors.colLayer2
                                implicitWidth: 60
                                implicitHeight: 24

                                StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Clear")
                                    font.pixelSize: 10
                                    color: Appearance.colors.colOnLayer0
                                }

                                onClicked: {
                                    ipc.logBuffer = [];
                                }
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 1
                            clip: true

                            model: ipc.logBuffer
                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 18
                                color: modelData.type === "error" ? "#3D0000" :
                                        modelData.type === "warn" ? "#3D3D00" :
                                        modelData.type === "ok" ? "#003D00" :
                                        "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    spacing: 6

                                    StyledText {
                                        text: modelData.time
                                        font.pixelSize: 9
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.5
                                        font.family: "monospace"
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.message
                                        font.pixelSize: 10
                                        color: modelData.type === "error" ? "#FF6B6B" :
                                               modelData.type === "warn" ? "#FFD93D" :
                                               modelData.type === "ok" ? "#6BCB77" :
                                               Appearance.colors.colOnLayer0
                                        font.family: "monospace"
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: Translation.tr("No logs yet")
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.3
                                visible: parent.count === 0
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── Funciones ────────────────────────────────────────────────────────

    function analyzeUrl(url) {
        if (!ipc.backendReady) {
            root.lastError = Translation.tr("Backend not ready");
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
                root.lastError = err.message;
                root.loading = false;
            });
    }

    function startDownload() {
        if (!root.currentMediaInfo) return;

        const params = {
            url: root.lastUrl,
            format: formatSelector.selectedFormat,
            quality: formatSelector.selectedQuality,
            extractAudio: formatSelector.extractAudio,
            downloadThumbnail: root.autoThumbnail,
            embedThumbnail: true,
            embedMetadata: true,
        };

        if (formatSelector.selectedQuality === "custom" && formatSelector.customFormat.length > 0) {
            params.customFormat = formatSelector.customFormat;
        }

        ipc.startDownload(params)
            .then((result) => {
                const task = {
                    id: result.taskId,
                    status: "queued",
                    mediaInfo: result.mediaInfo,
                    options: params,
                    progress: { percent: 0, speed: 0, eta: 0, downloadedBytes: 0, totalBytes: 0, speedFormatted: "", etaFormatted: "", downloadedFormatted: "", totalFormatted: "" },
                    createdAt: Date.now(),
                };
                root.activeTasks[result.taskId] = task;
                root.activeTaskIds = Object.keys(root.activeTasks);
                root.currentMediaInfo = null;
                urlInput.clear();
            })
            .catch((err) => {
                root.lastError = err.message;
            });
    }

    function updateTaskProgress(taskId, progress) {
        if (root.activeTasks[taskId]) {
            root.activeTasks[taskId].progress = progress;
            root.activeTaskIds = Object.keys(root.activeTasks);
        }
    }

    function handleStatusChange(taskId, status, previous) {
        if (root.activeTasks[taskId]) {
            root.activeTasks[taskId].status = status;
            root.activeTaskIds = Object.keys(root.activeTasks);
        }

        if (status === "completed" || status === "failed" || status === "cancelled") {
            Qt.callLater(() => {
                delete root.activeTasks[taskId];
                root.activeTaskIds = Object.keys(root.activeTasks);
                root.loadHistory();
            });
        }
    }

    function refreshActive() {
        ipc.listDownloads()
            .then((tasks) => {
                for (const t of tasks) {
                    if (["running", "paused", "queued"].includes(t.status)) {
                        root.activeTasks[t.id] = t;
                    }
                }
                root.activeTaskIds = Object.keys(root.activeTasks);
            })
            .catch(() => {});
    }

    function loadHistory() {
        ipc.listHistory(100)
            .then((entries) => { root.historyEntries = entries; })
            .catch(() => {});
    }

    function loadFavorites() {
        ipc.listFavorites(100)
            .then((entries) => { root.favoriteEntries = entries; })
            .catch(() => {});
    }

    function searchHistory(query) {
        ipc.searchHistory(query)
            .then((entries) => { root.historyEntries = entries; })
            .catch(() => {});
    }

    function loadConfig() {
        ipc.getConfig()
            .then((config) => {
                if (config) {
                    root.defaultPath = config.defaultDownloadPath || root.defaultPath;
                    root.maxConcurrent = config.maxConcurrentDownloads || 3;
                    root.autoThumbnail = config.autoDownloadThumbnail !== false;
                    root.autoSubtitles = config.autoDownloadSubtitles === true;
                }
            })
            .catch(() => {});
    }

    // ─── Componente interno para items del historial ──────────────────────

    component HistoryItem: Rectangle {
        id: root
        property var entry: null
        property var handleDelete: null
        property var handleFavorite: null

        height: 50
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            StyledImage {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                source: entry?.thumbnail ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: (entry?.thumbnail ?? "").length > 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: entry?.title ?? "Unknown"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                StyledText {
                    text: `${entry?.provider ?? ""} · ${entry?.format?.toUpperCase() ?? ""}${entry?.quality ? " · " + entry.quality : ""}`
                    font.pixelSize: 10
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.5
                }
            }

            RippleButton {
                id: favBtn
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                buttonRadius: height / 2
                buttonColor: "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.entry?.isFavorite ? "star" : "star_border"
                    iconSize: 16
                    color: root.entry?.isFavorite ? "#FFC107" : Appearance.colors.colOnLayer0
                }

                onClicked: {
                    if (root.handleFavorite && root.entry) {
                        root.handleFavorite(root.entry.id);
                    }
                }
            }

            RippleButton {
                id: delBtn
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                buttonRadius: height / 2
                buttonColor: "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.6
                }

                onClicked: {
                    if (root.handleDelete && root.entry) {
                        root.handleDelete(root.entry.id);
                    }
                }
            }
        }
    }
}
