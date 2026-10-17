// ============================================================================
// MediaHistoryList — Historial y favoritos (compartido)
// ============================================================================
// `mode` decide qué se muestra:
//
//   "history"   → todas las descargas completadas, con buscador
//   "favorites" → solo las marcadas como favoritas
//
// Es autónomo: consulta al demonio y se refresca tras cada operación. El
// histórico vive en SQLite, así que no se pierde al cerrar la barra lateral, al
// recargar QuickShell ni al reiniciar la sesión.
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

    property string mode: "history"
    property var entries: []
    property string searchText: ""

    readonly property bool isFavorites: root.mode === "favorites"
    readonly property int count: root.entries.length

    /** Umbral por debajo del cual se lista todo en lugar de buscar. */
    readonly property int minSearchLength: 3

    onModeChanged: root.refresh()

    /** Vuelve a pedir los datos al demonio. */
    function refresh() {
        if (!MediaDownloaderIPC.backendReady) return;

        if (root.isFavorites) {
            MediaDownloaderIPC.listFavorites(100)
                .then((entries) => { root.entries = entries; })
                .catch(() => {});
            return;
        }

        const query = root.searchText.trim();
        const request = query.length >= root.minSearchLength
            ? MediaDownloaderIPC.searchHistory(query)
            : MediaDownloaderIPC.listHistory(100);

        request
            .then((entries) => { root.entries = entries; })
            .catch(() => {});
    }

    function deleteEntry(entryId) {
        MediaDownloaderIPC.deleteHistory(entryId)
            .then(() => root.refresh())
            .catch(() => {});
    }

    function toggleFavorite(entryId) {
        // En favoritos, desmarcar saca la fila de la lista: refrescar es
        // suficiente para ambos modos.
        MediaDownloaderIPC.toggleFavorite(entryId)
            .then(() => root.refresh())
            .catch(() => {});
    }

    Connections {
        target: MediaDownloaderIPC

        function onBackendReadyChanged() {
            if (MediaDownloaderIPC.backendReady) root.refresh();
        }

        function onDownloadCompleted() {
            // Una descarga recién terminada debe aparecer sin cambiar de vista.
            root.refresh();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        MaterialTextField {
            Layout.fillWidth: true
            visible: !root.isFavorites
            placeholderText: Translation.tr("Search history...")
            onTextChanged: {
                root.searchText = text;
                if (text.length === 0 || text.length >= root.minSearchLength) {
                    root.refresh();
                }
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true

            model: root.entries
            delegate: HistoryItem {
                width: ListView.view.width
                entry: modelData
                handleDelete: function(entryId) { root.deleteEntry(entryId); }
                handleFavorite: function(entryId) { root.toggleFavorite(entryId); }
            }

            StyledText {
                anchors.centerIn: parent
                text: root.isFavorites
                    ? Translation.tr("No favorites yet")
                    : Translation.tr("No history yet")
                color: Appearance.colors.colOnLayer0
                opacity: 0.4
                visible: parent.count === 0
            }
        }
    }

    // ─── Componente interno: fila del historial ───────────────────────────
    // (movido desde MediaDownloaderPanel para que lo compartan ambas vistas)

    component HistoryItem: Rectangle {
        id: historyItemRoot
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
                source: historyItemRoot.entry?.thumbnail ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: (historyItemRoot.entry?.thumbnail ?? "").length > 0
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: historyItemRoot.entry?.title ?? "Unknown"
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                StyledText {
                    text: `${historyItemRoot.entry?.provider ?? ""} · ${historyItemRoot.entry?.format?.toUpperCase() ?? ""}${historyItemRoot.entry?.quality ? " · " + historyItemRoot.entry.quality : ""}`
                    font.pixelSize: 10
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.5
                }
            }

            RippleButton {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                buttonRadius: height / 2
                buttonColor: "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: historyItemRoot.entry?.isFavorite ? "star" : "star_border"
                    iconSize: 16
                    color: historyItemRoot.entry?.isFavorite ? "#FFC107" : Appearance.colors.colOnLayer0
                }

                onClicked: {
                    if (historyItemRoot.handleFavorite && historyItemRoot.entry) {
                        historyItemRoot.handleFavorite(historyItemRoot.entry.id);
                    }
                }
            }

            RippleButton {
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
                    if (historyItemRoot.handleDelete && historyItemRoot.entry) {
                        historyItemRoot.handleDelete(historyItemRoot.entry.id);
                    }
                }
            }
        }
    }
}
