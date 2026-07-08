// ============================================================================
// DownloadProgressCard — Card individual de progreso de descarga
// ============================================================================

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property var task: null
    property bool hasTask: task !== null

    signal pauseClicked(string taskId)
    signal resumeClicked(string taskId)
    signal cancelClicked(string taskId)
    signal removeClicked(string taskId)

    implicitHeight: hasTask ? cardRectangle.implicitHeight + 2 : 0
    visible: hasTask

    Behavior on implicitHeight {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: cardRectangle
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: root.borderColor()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // ─── Título + Estado ──────────────────────────────────────────

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    text: root.task?.mediaInfo?.title
                          ?? root.task?.options?.url?.substring(0, 50) + "..."
                          ?? Translation.tr("Unknown")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }

                StatusBadge {
                    status: root.task?.status ?? "queued"
                }
            }

            // ─── Info de formato ──────────────────────────────────────────

            StyledText {
                text: root.formatInfo()
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
                opacity: 0.6
                visible: text.length > 0
            }

            // ─── Barra de progreso ────────────────────────────────────────

            Item {
                Layout.fillWidth: true
                height: 18
                visible: root.task?.status === "running" || root.task?.status === "paused"

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Appearance.colors.colLayer2

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: root.progressColor()
                        width: parent.width * (root.task?.progress?.percent ?? 0) / 100

                        Behavior on width {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            // ─── Stats de velocidad ───────────────────────────────────────

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                visible: root.task?.status === "running"

                StatItem {
                    statIcon: "speed"
                    label: root.task?.progress?.speedFormatted ?? ""
                }

                StatItem {
                    statIcon: "schedule"
                    label: root.task?.progress?.etaFormatted ?? ""
                }

                StatItem {
                    statIcon: "storage"
                    label: root.task?.progress?.downloadedFormatted ?? ""
                    suffix: root.task?.progress?.totalFormatted ? ` / ${root.task.progress.totalFormatted}` : ""
                }
            }

            // ─── Error ────────────────────────────────────────────────────

            StyledText {
                Layout.fillWidth: true
                text: root.task?.error ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: "#FF5252"
                visible: root.task?.status === "failed" && (root.task?.error ?? "").length > 0
                wrapMode: Text.WordWrap
            }

            // ─── Botones de acción ────────────────────────────────────────

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 4
                visible: root.task?.status !== "completed"

                ActionButton {
                    buttonIcon: "play_arrow"
                    visible: root.task?.status === "paused"
                    tooltipText: Translation.tr("Resume")
                    onClicked: root.resumeClicked(root.task.id)
                }

                ActionButton {
                    buttonIcon: "pause"
                    visible: root.task?.status === "running"
                    tooltipText: Translation.tr("Pause")
                    onClicked: root.pauseClicked(root.task.id)
                }

                ActionButton {
                    buttonIcon: "close"
                    buttonIconColor: "#FF5252"
                    tooltipText: root.task?.status === "running" || root.task?.status === "paused"
                        ? Translation.tr("Cancel")
                        : Translation.tr("Remove")
                    onClicked: {
                        if (root.task?.status === "running" || root.task?.status === "paused") {
                            root.cancelClicked(root.task.id);
                        } else {
                            root.removeClicked(root.task.id);
                        }
                    }
                }
            }
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    function borderColor() {
        switch (root.task?.status) {
            case "running": return "#4CAF50";
            case "paused": return "#FFC107";
            case "completed": return "#4CAF50";
            case "failed": return "#FF5252";
            case "cancelled": return "#9E9E9E";
            default: return "transparent";
        }
    }

    function progressColor() {
        switch (root.task?.status) {
            case "running": return "#4CAF50";
            case "paused": return "#FFC107";
            default: return Appearance.colors.colPrimary;
        }
    }

    function formatInfo() {
        if (!root.task) return "";
        const opts = root.task.options;
        let parts = [];
        if (opts.extractAudio) parts.push("Audio");
        else parts.push("Video");
        parts.push(opts.format?.toUpperCase() ?? "");
        if (opts.quality && opts.quality !== "auto") parts.push(opts.quality);
        return parts.join(" · ");
    }

    // ─── Componentes internos ──────────────────────────────────────────────

    component StatusBadge: Rectangle {
        property string status: "queued"
        height: 20
        radius: height / 2
        color: root.borderColor()
        opacity: 0.2

        StyledText {
            anchors.centerIn: parent
            anchors.margins: 8
            text: Translation.tr(root.status.charAt(0).toUpperCase() + root.status.slice(1))
            font.pixelSize: 10
            font.weight: Font.Medium
            color: root.borderColor()
        }
    }

    component StatItem: RowLayout {
        property string statIcon: ""
        property string label: ""
        property string suffix: ""
        spacing: 3

        MaterialSymbol {
            text: root.statIcon
            iconSize: 12
            color: Appearance.colors.colOnLayer0
            opacity: 0.5
        }

        StyledText {
            text: root.label + root.suffix
            font.pixelSize: 10
            color: Appearance.colors.colOnLayer0
            opacity: 0.7
        }
    }

    component ActionButton: RippleButton {
        property string buttonIcon: ""
        property string buttonIconColor: Appearance.colors.colOnLayer0
        property string tooltipText: ""
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: height / 2
        buttonColor: "transparent"

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.buttonIcon
            iconSize: 18
            color: root.buttonIconColor
        }

        StyledToolTip {
            text: root.tooltipText
        }
    }
}
