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
    //
    // Alias al singleton compartido: NO se instancia un backend por widget.
    // Antes cada UI creaba su propio proceso Node, y al desmontarse el widget
    // (cerrar el sidebar o cambiar de pestaña) se llevaba por delante las
    // descargas que estaban en curso.

    readonly property var ipc: MediaDownloaderIPC

    Connections {
        target: MediaDownloaderIPC

        function onDownloadCompleted(taskId, info) {
            console.log("[MediaDownloader] Download completed:", taskId, info?.title);
        }

        function onDownloadFailed(taskId, error) {
            console.warn("[MediaDownloader] Download failed:", taskId, error);
        }
    }

    // ─── Estado ───────────────────────────────────────────────────────────

    // Las descargas activas y el historial los pintan MediaActiveList y
    // MediaHistoryList, que son autónomos: aquí no se duplica ese estado.
    property string currentTab: "download"
    readonly property var tabs: ["download", "active", "history"]

    property bool loading: false
    property string lastError: ""
    property string lastUrl: ""

    property var currentMediaInfo: null
    property var currentFormats: []
    property bool hasMediaInfo: currentMediaInfo !== null

    // Sin temporizador de reintento: el singleton se reconecta por su cuenta.

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
            visible: root.currentTab === "download"
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
            visible: root.loading && root.currentTab === "download"

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
            visible: root.currentTab === "download"
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
            visible: root.hasMediaInfo && root.currentTab === "download"
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
            visible: root.hasMediaInfo && root.currentTab === "download"

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

        // ─── Selector de vista: Descargar · Activas · Historial ───────────
        //
        // El widget vivía solo en la pestaña "Descargar" del sidebar: el
        // historial era inalcanzable desde aquí. Ahora ambas vistas comparten
        // los mismos componentes que el panel flotante.

        SecondaryTabBar {
            id: widgetTabBar
            Layout.fillWidth: true
            Layout.topMargin: 2
            currentIndex: root.tabs.indexOf(root.currentTab)

            SecondaryTabButton {
                buttonIcon: "download"
                buttonText: Translation.tr("Download")
                onClicked: root.currentTab = "download"
            }

            SecondaryTabButton {
                buttonIcon: "downloading"
                buttonText: activeList.count > 0
                    ? `${Translation.tr("Active")} (${activeList.count})`
                    : Translation.tr("Active")
                onClicked: root.currentTab = "active"
            }

            SecondaryTabButton {
                buttonIcon: "history"
                buttonText: Translation.tr("History")
                onClicked: root.currentTab = "history"
            }
        }

        // ─── Descargas activas / historial ────────────────────────────────

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            visible: root.currentTab !== "download"

            MediaActiveList {
                id: activeList
                anchors.fill: parent
                visible: root.currentTab === "active"
            }

            MediaHistoryList {
                id: historyList
                anchors.fill: parent
                mode: "history"
                visible: root.currentTab === "history"
            }
        }

        // ─── Empty state ──────────────────────────────────────────────────

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.hasMediaInfo && root.currentTab === "download" && !root.loading

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
                // El estado lo mantiene MediaActiveList: se le pide que vuelva
                // a consultar la cola del demonio.
                activeList.refresh();
                // Limpiar URL
                urlInput.clear();
                root.currentMediaInfo = null;
                root.currentTab = "active";
            })
            .catch((err) => {
                root.lastError = err.message || Translation.tr("Failed to start download");
            });
    }
}
