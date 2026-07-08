// ============================================================================
// FormatSelector — Selector de formato/calidad de descarga
// ============================================================================

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property var formats: []
    property string selectedFormat: "mp4"
    property string selectedQuality: "auto"
    property bool extractAudio: false
    property string customFormat: ""

    signal formatTypeChanged(string format)
    signal qualityLevelChanged(string quality)

    implicitHeight: formatColumn.implicitHeight
    implicitWidth: formatColumn.implicitWidth

    ColumnLayout {
        id: formatColumn
        anchors.fill: parent
        spacing: 8

        // ─── Modo: Video / Solo Audio ──────────────────────────────────────

        StyledComboBox {
            id: modeCombo
            Layout.fillWidth: true
            implicitHeight: 36
            buttonIcon: root.extractAudio ? "music_note" : "video_library"
            model: [
                { text: Translation.tr("Video"), value: false },
                { text: Translation.tr("Audio Only"), value: true },
            ]
            textRole: "text"
            valueRole: "value"
            currentIndex: root.extractAudio ? 1 : 0
            onActivated: (index) => {
                root.extractAudio = model[index].value;
            }
        }

        // ─── Selector de Formato ──────────────────────────────────────────

        StyledComboBox {
            id: formatCombo
            Layout.fillWidth: true
            implicitHeight: 36
            buttonIcon: "video_file"
            model: root.extractAudio
                ? ["mp3", "flac", "aac", "opus", "ogg", "wav"]
                : ["mp4", "mkv", "webm", "avi", "mov"]
            currentIndex: {
                const idx = model.indexOf(root.selectedFormat);
                return idx >= 0 ? idx : 0;
            }
            onCurrentTextChanged: {
                root.selectedFormat = currentText;
            }
        }

        // ─── Selector de Calidad (solo video) ─────────────────────────────

        StyledComboBox {
            id: qualityCombo
            Layout.fillWidth: true
            implicitHeight: 36
            buttonIcon: "quality"
            visible: !root.extractAudio
            model: [
                { text: "Auto", value: "auto" },
                { text: "2160p (4K)", value: "2160p" },
                { text: "1440p (2K)", value: "1440p" },
                { text: "1080p", value: "1080p" },
                { text: "720p", value: "720p" },
                { text: "480p", value: "480p" },
                { text: "360p", value: "360p" },
                { text: "144p", value: "144p" },
                { text: "Custom", value: "custom" },
            ]
            textRole: "text"
            valueRole: "value"
            currentIndex: {
                for (let i = 0; i < model.length; i++) {
                    if (model[i].value === root.selectedQuality) return i;
                }
                return 0;
            }
            onActivated: (index) => {
                root.selectedQuality = model[index].value;
            }
        }

        // ─── Formato personalizado (solo cuando quality = custom) ─────────

        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Custom yt-dlp format (e.g. bestvideo[height<=1080]+bestaudio)")
            visible: root.selectedQuality === "custom"
            onTextChanged: {
                root.customFormat = text;
            }
        }
    }
}
