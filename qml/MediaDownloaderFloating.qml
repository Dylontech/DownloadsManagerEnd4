// ============================================================================
// MediaDownloaderFloating — Ventana flotante independiente
// ============================================================================
// Se abre como PanelWindow en modo popup/flotante.
// Reutiliza MediaDownloaderPanel como contenido.
// ============================================================================

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.mediaDownloader

Scope {
    id: root

    property int windowWidth: 480
    property int windowHeight: 640

    // ─── Ventana ──────────────────────────────────────────────────────────

    PanelWindow {
        id: floatingWindow
        visible: GlobalStates.mediaDownloaderFloatingOpen ?? false

        function hide() {
            if (typeof GlobalStates.mediaDownloaderFloatingOpen !== "undefined") {
                GlobalStates.mediaDownloaderFloatingOpen = false;
            }
        }

        implicitWidth: root.windowWidth
        implicitHeight: root.windowHeight
        WlrLayershell.namespace: "quickshell:mediaDownloader"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(floatingWindow);
            } else {
                GlobalFocusGrab.removeDismissable(floatingWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                floatingWindow.hide();
            }
        }

        // ─── Contenido ────────────────────────────────────────────────────

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.screenRounding
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true

            // Drag handle para mover la ventana
            Rectangle {
                id: dragHandle
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 32
                color: "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "drag_indicator"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.3
                }

                // Hacemos la ventana movible por el drag handle
                // En Quickshell/Wayland, PanelWindow no es directamente arrastrable
                // Se puede mover mediante hyprctl o configurando anchors
            }

            // Close button
            RippleButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: height / 2
                buttonColor: "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer0
                }

                onClicked: floatingWindow.hide()
            }

            // Panel content
            MediaDownloaderPanel {
                anchors {
                    top: dragHandle.bottom
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    margins: 4
                }
            }
        }
    }

    // ─── IPC para toggle ──────────────────────────────────────────────────

    IpcHandler {
        target: "mediaDownloaderFloating"

        function toggle() {
            if (typeof GlobalStates.mediaDownloaderFloatingOpen !== "undefined") {
                GlobalStates.mediaDownloaderFloatingOpen = !GlobalStates.mediaDownloaderFloatingOpen;
            }
        }

        function open() {
            if (typeof GlobalStates.mediaDownloaderFloatingOpen !== "undefined") {
                GlobalStates.mediaDownloaderFloatingOpen = true;
            }
        }

        function close() {
            if (typeof GlobalStates.mediaDownloaderFloatingOpen !== "undefined") {
                GlobalStates.mediaDownloaderFloatingOpen = false;
            }
        }
    }

    GlobalShortcut {
        name: "mediaDownloaderFloatingToggle"
        description: "Toggles Media Download Center floating window"

        onPressed: {
            if (typeof GlobalStates.mediaDownloaderFloatingOpen !== "undefined") {
                GlobalStates.mediaDownloaderFloatingOpen = !GlobalStates.mediaDownloaderFloatingOpen;
            }
        }
    }
}
