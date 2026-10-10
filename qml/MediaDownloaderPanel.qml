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
    property string cookiesFromBrowser: ""
    property string cookiesFile: ""

    // ─── Keys ─────────────────────────────────────────────────────────────

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !urlInput.fieldFocused) {
            // Enter fuera del campo: descargar si ya hay enlace analizado
            event.accepted = true;
            if (root.currentMediaInfo !== null) root.startDownload();
            else if (urlInput.url.length > 0) urlInput.submitCurrent();
        }
    }

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
                root.submitUrl(url);
            }
        }

        // ─── Loading / Error ──────────────────────────────────────────────

        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: root.loading
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Analyzing link...")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            opacity: 0.7
            visible: root.loading
        }

        ErrorBanner {
            message: root.lastError
            hint: root.errorHint(root.lastError)
        }

        // ─── Preview + formato (zona desplazable y acotada) ───────────────

        Flickable {
            id: mediaScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: mediaForm.implicitHeight
            Layout.minimumHeight: 80
            Layout.maximumHeight: Math.max(80, Math.min(mediaForm.implicitHeight, root.height * 0.55))
            visible: root.currentMediaInfo !== null
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

        // ─── Download (siempre visible, fuera de la zona desplazable) ─────

        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 38
            buttonRadius: Appearance.rounding.normal
            buttonColor: Appearance.colors.colPrimary
            enabled: !root.loading
            visible: root.currentMediaInfo !== null

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
                    font.weight: Font.Medium
                    color: "#FFF"
                }
            }

            onClicked: {
                root.startDownload();
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

                            // ─── Descargas ────────────────────────────
                            ConfigSection {
                                title: Translation.tr("Downloads")

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Download Path")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer0
                                    opacity: 0.8
                                }

                                MaterialTextField {
                                    id: pathField
                                    Layout.fillWidth: true
                                    text: root.defaultPath
                                    onEditingFinished: {
                                        ipc.setConfig("default_download_path", text);
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Max Concurrent")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.8
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

                                ConfigSwitch {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Auto-download thumbnails")
                                    checked: root.autoThumbnail
                                    onCheckedChanged: {
                                        ipc.setConfig("auto_download_thumbnail", checked ? "true" : "false");
                                    }
                                }

                                ConfigSwitch {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Auto-download subtitles")
                                    checked: root.autoSubtitles
                                    onCheckedChanged: {
                                        ipc.setConfig("auto_download_subtitles", checked ? "true" : "false");
                                    }
                                }
                            }

                            // ─── Cookies ──────────────────────────────
                            ConfigSection {
                                title: Translation.tr("Cookies (anti-bot)")

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Some services ask for a logged-in session. Import the cookies from your browser.")
                                    font.pixelSize: 10
                                    color: Appearance.colors.colOnLayer0
                                    opacity: 0.6
                                    wrapMode: Text.WordWrap
                                }

                                StyledComboBox {
                                    id: cookiesBrowserCombo
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    buttonIcon: "cookie"
                                    model: [
                                        { text: Translation.tr("Disabled"), value: "" },
                                        { text: "Firefox", value: "firefox" },
                                        { text: "Chrome", value: "chrome" },
                                        { text: "Chromium", value: "chromium" },
                                        { text: "Brave", value: "brave" },
                                        { text: "Edge", value: "edge" },
                                        { text: "Opera", value: "opera" },
                                        { text: "Vivaldi", value: "vivaldi" },
                                    ]
                                    textRole: "text"
                                    valueRole: "value"
                                    currentIndex: {
                                        for (let i = 0; i < model.length; i++) {
                                            if (model[i].value === root.cookiesFromBrowser) return i;
                                        }
                                        return 0;
                                    }
                                    onActivated: (index) => {
                                        const browser = model[index].value;
                                        root.cookiesFromBrowser = browser;
                                        // El archivo y el navegador son excluyentes
                                        root.cookiesFile = "";
                                        cookiesPathField.text = "";
                                        ipc.setConfig("cookies_file", "");
                                        ipc.setConfig("cookies_from_browser", browser);
                                    }
                                }

                                MaterialTextField {
                                    id: cookiesPathField
                                    Layout.fillWidth: true
                                    placeholderText: Translation.tr("...or path to cookies.txt")
                                    text: root.cookiesFile
                                    onEditingFinished: {
                                        root.cookiesFile = text;
                                        ipc.setConfig("cookies_file", text);
                                    }
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
            root.lastError = Translation.tr("Backend not ready");
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
                    root.cookiesFromBrowser = config.cookiesFromBrowser || "";
                    root.cookiesFile = config.cookiesFile || "";
                }
            })
            .catch(() => {});
    }

    // ─── Componente interno: sección de configuración ─────────────────────

    component ConfigSection: Rectangle {
        id: section
        property string title: ""
        default property alias sectionContent: sectionColumn.data

        Layout.fillWidth: true
        implicitHeight: sectionColumn.implicitHeight + 20
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: sectionColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: section.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
                opacity: 0.7
                visible: section.title.length > 0
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
