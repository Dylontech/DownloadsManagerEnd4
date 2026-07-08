// ============================================================================
// UrlInput — Campo de entrada de URL con detección automática de provider
// ============================================================================

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property alias url: urlField.text
    property bool detecting: false
    property string detectedProvider: ""
    property string detectedProviderIcon: "search"
    property string detectedProviderColor: "#888"

    signal submit(string url)
    signal providerDetected(string provider)

    implicitHeight: urlFieldRow.implicitHeight
    implicitWidth: urlFieldRow.implicitWidth

    function clear() {
        urlField.text = "";
        root.detectedProvider = "";
        root.detectedProviderIcon = "search";
        root.detectedProviderColor = "#888";
    }

    function pasteFromClipboard() {
        urlField.paste();
    }

    RowLayout {
        id: urlFieldRow
        anchors.fill: parent
        spacing: 8

        Rectangle {
            id: providerBadge
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: height / 2
            color: root.detectedProvider ? Qt.lighter(root.detectedProviderColor, 1.5) : Appearance.colors.colLayer1
            border.width: 1
            border.color: root.detectedProvider ? root.detectedProviderColor : "transparent"

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.detectedProviderIcon
                iconSize: 20
                color: root.detectedProvider ? root.detectedProviderColor : Appearance.colors.colOnLayer0
            }

            Behavior on color {
                ColorAnimation { duration: 200 }
            }
        }

        MaterialTextField {
            id: urlField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Paste a link to download...")
            placeholderTextColor: Appearance.colors.colOnLayer0

            onTextChanged: {
                if (text.length > 5) {
                    root.detectProviderFromUrl(text);
                } else {
                    root.detectedProvider = "";
                    root.detectedProviderIcon = "search";
                    root.detectedProviderColor = "#888";
                }
            }

            onAccepted: {
                if (text.length > 0) {
                    root.submit(text.trim());
                }
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                    // Ctrl+V handled natively
                }
            }
        }

        RippleButton {
            id: pasteButton
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            buttonRadius: height / 2
            buttonColor: Appearance.colors.colLayer1

            MaterialSymbol {
                anchors.centerIn: parent
                text: "content_paste"
                iconSize: 20
                color: Appearance.colors.colOnLayer0
            }

            StyledToolTip {
                text: Translation.tr("Paste from clipboard")
            }

            onClicked: {
                urlField.paste();
            }
        }

        RippleButton {
            id: downloadButton
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            buttonRadius: height / 2
            buttonColor: root.detectedProviderColor !== "#888" ? root.detectedProviderColor : Appearance.colors.colPrimary
            enabled: urlField.text.trim().length > 0

            MaterialSymbol {
                anchors.centerIn: parent
                text: "download"
                iconSize: 20
                color: "#FFF"
            }

            StyledToolTip {
                text: Translation.tr("Analyze link")
            }

            onClicked: {
                if (urlField.text.trim().length > 0) {
                    root.submit(urlField.text.trim());
                }
            }
        }
    }

    function detectProviderFromUrl(url) {
        // Patrones de proveedores
        const providers = [
            { pattern: /youtube\.com|youtu\.be/i, name: "YouTube", icon: "play_circle", color: "#FF0000" },
            { pattern: /twitch\.tv|clips\.twitch/i, name: "Twitch", icon: "live_tv", color: "#9146FF" },
            { pattern: /tiktok\.com|vm\.tiktok|vt\.tiktok/i, name: "TikTok", icon: "music_video", color: "#000000" },
            { pattern: /instagram\.com/i, name: "Instagram", icon: "camera_alt", color: "#E4405F" },
            { pattern: /twitter\.com|x\.com/i, name: "Twitter / X", icon: "alternate_email", color: "#1DA1F2" },
            { pattern: /vimeo\.com/i, name: "Vimeo", icon: "videocam", color: "#1AB7EA" },
            { pattern: /soundcloud\.com/i, name: "SoundCloud", icon: "audiotrack", color: "#FF7700" },
            { pattern: /bandcamp\.com/i, name: "Bandcamp", icon: "music_note", color: "#629AA9" },
        ];

        for (const p of providers) {
            if (p.pattern.test(url)) {
                root.detectedProvider = p.name;
                root.detectedProviderIcon = p.icon;
                root.detectedProviderColor = p.color;
                root.providerDetected(p.name);
                return;
            }
        }

        root.detectedProvider = "";
        root.detectedProviderIcon = "link";
        root.detectedProviderColor = "#888";
    }
}
