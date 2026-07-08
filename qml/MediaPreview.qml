// ============================================================================
// MediaPreview — Vista previa del media detectado
// ============================================================================

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property var mediaInfo: null
    property bool loading: false
    property bool hasInfo: mediaInfo !== null

    implicitHeight: visible ? previewColumn.implicitHeight + 20 : 0
    visible: mediaInfo !== null || loading

    Behavior on implicitHeight {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: previewColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Thumbnail + Info row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Thumbnail
                Rectangle {
                    id: thumbnailContainer
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 68
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    clip: true

                    StyledImage {
                        id: thumbnail
                        anchors.fill: parent
                        source: root.mediaInfo?.thumbnail ?? ""
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready

                        asynchronous: true
                        cache: true
                    }

                    // Placeholder mientras carga
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "image"
                        iconSize: 28
                        color: Appearance.colors.colOnLayer0
                        opacity: thumbnail.visible ? 0 : 0.4

                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    // Duración badge
                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        radius: 4
                        color: Qt.rgba(0, 0, 0, 0.7)
                        height: durationText.implicitHeight + 4

                        StyledText {
                            id: durationText
                            anchors.centerIn: parent
                            anchors.margins: 4
                            text: root.formatDuration(root.mediaInfo?.duration ?? 0)
                            font.pixelSize: 11
                            color: "#FFF"
                            visible: (root.mediaInfo?.duration ?? 0) > 0
                        }
                    }
                }

                // Title + Author
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: root.mediaInfo?.title ?? Translation.tr("Loading...")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    }

                    StyledText {
                        text: root.mediaInfo?.author ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.7
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                }
            }

            // Provider + Quality tags row
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: root.hasInfo

                // Provider tag
                Rectangle {
                    height: 22
                    radius: height / 2
                    color: Qt.lighter(root.getProviderColor(), 1.8)
                    border.width: 1
                    border.color: root.getProviderColor()

                    RowLayout {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.vertical
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 4

                        MaterialSymbol {
                            text: root.getProviderIcon()
                            iconSize: 14
                            color: root.getProviderColor()
                        }

                        StyledText {
                            text: root.mediaInfo?.provider ?? ""
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: root.getProviderColor()
                        }
                    }
                }

                // Format count tag
                Rectangle {
                    height: 22
                    radius: height / 2
                    color: Appearance.colors.colLayer2
                    visible: (root.mediaInfo?.formats?.length ?? 0) > 0

                    StyledText {
                        anchors.centerIn: parent
                        anchors.margins: 8
                        text: Translation.tr("%1 formats").arg(root.mediaInfo?.formats?.length ?? 0)
                        font.pixelSize: 11
                        color: Appearance.colors.colOnLayer0
                    }
                }

                // Resolution tag
                Rectangle {
                    height: 22
                    radius: height / 2
                    color: Appearance.colors.colLayer2
                    visible: root.bestResolution().length > 0

                    StyledText {
                        anchors.centerIn: parent
                        anchors.margins: 8
                        text: root.bestResolution()
                        font.pixelSize: 11
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    function formatDuration(seconds) {
        if (!seconds || seconds <= 0) return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = Math.floor(seconds % 60);
        if (h > 0) return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
        return `${m}:${s.toString().padStart(2, "0")}`;
    }

    function bestResolution() {
        if (!root.mediaInfo?.formats) return "";
        let best = 0;
        for (const f of root.mediaInfo.formats) {
            if (f.height && f.height > best) best = f.height;
        }
        return best > 0 ? `${best}p` : "";
    }

    function getProviderColor() {
        const colors = {
            "youtube": "#FF0000",
            "twitch": "#9146FF",
            "tiktok": "#000000",
            "instagram": "#E4405F",
            "twitter": "#1DA1F2",
            "vimeo": "#1AB7EA",
            "soundcloud": "#FF7700",
            "bandcamp": "#629AA9",
        };
        return colors[root.mediaInfo?.provider?.toLowerCase() ?? ""] ?? Appearance.colors.colPrimary;
    }

    function getProviderIcon() {
        const icons = {
            "youtube": "play_circle",
            "twitch": "live_tv",
            "tiktok": "music_video",
            "instagram": "camera_alt",
            "twitter": "alternate_email",
            "vimeo": "videocam",
            "soundcloud": "audiotrack",
            "bandcamp": "music_note",
        };
        return icons[root.mediaInfo?.provider?.toLowerCase() ?? ""] ?? "link";
    }
}
