import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../common"

// Notification history panel (bell in the bar, or `qs ipc call notifs toggle`).
Scope {
    id: root

    readonly property int topMargin: Theme.barBody + Theme.frameT
    readonly property int panelWidth: 360
    readonly property int gutter: Theme.frameT + Theme.frameFillet + 8
    readonly property real panelX: Math.max(gutter, Math.min(
        Notifs.centerAnchorX + Notifs.centerAnchorWidth / 2 - panelWidth / 2,
        Notifs.centerScreenWidth - panelWidth - gutter
    ))

    function panelHeight() {
        return Math.min(430, Math.max(160, list.contentHeight + 65));
    }

    // IPC opens have no bell to hang from: anchor to the focused monitor,
    // panel centered (AttachedPanel clamps the zero-width neck)
    function anchorToFocusedScreen() {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        const s = [...Quickshell.screens].find(sc => sc.name === name) || Quickshell.screens[0];
        Notifs.setCenterAnchor(s.width / 2, 0, s);
    }

    IpcHandler {
        target: "notifs"
        function toggle(): void {
            if (!Notifs.centerOpen && !Notifs.centerScreen)
                root.anchorToFocusedScreen();
            Notifs.centerOpen = !Notifs.centerOpen;
        }
        function dismissAll(): void { Notifs.dismissAll(); }
        function dismissLatest(): void { Notifs.dismissLatest(); }
    }

    PanelWindow {
        visible: Notifs.centerOpen
        screen: Notifs.centerScreen || Quickshell.screens[0]
        anchors { top: true; right: true; bottom: true; left: true }
        margins { top: root.topMargin }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-notifs-backdrop"

        MouseArea {
            anchors.fill: parent
            onClicked: Notifs.centerOpen = false
        }
    }

    PanelWindow {
        visible: Notifs.centerOpen
        screen: Notifs.centerScreen || Quickshell.screens[0]
        anchors { top: true; left: true }
        margins { top: root.topMargin; left: root.panelX }
        implicitWidth: root.panelWidth
        implicitHeight: root.panelHeight()
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-popout"

        AttachedPanel {
            anchors.fill: parent
            shown: Notifs.centerOpen
            neckX: Notifs.centerAnchorX - root.panelX
            neckWidth: Notifs.centerAnchorWidth

            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 22

                Text {
                    text: "notifications"
                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    color: Theme.bright
                }
                Text {
                    anchors.right: parent.right
                    text: "clear all"
                    font.family: Theme.font; font.pixelSize: 11
                    color: Theme.accent
                    visible: list.count > 0
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Notifs.dismissAll()
                    }
                }
            }

            ListView {
                id: list
                anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 10 }
                clip: true
                spacing: 6
                model: [...Notifs.server.trackedNotifications.values].reverse()

                delegate: Rectangle {
                    required property var modelData
                    width: list.width
                    implicitHeight: Math.max(c.implicitHeight, hicon.visible ? 24 : 0) + 20
                    radius: 9
                    color: Theme.track

                    IconImage {
                        id: hicon
                        anchors { left: parent.left; top: parent.top; margins: 10 }
                        implicitSize: 24
                        visible: String(source) !== ""
                        source: modelData.image || (modelData.appIcon
                            ? (modelData.appIcon.startsWith("/") ? "file://" + modelData.appIcon : Quickshell.iconPath(modelData.appIcon, true))
                            : "")
                    }

                    Column {
                        id: c
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        anchors.leftMargin: hicon.visible ? 42 : 10
                        spacing: 2
                        Text {
                            text: (modelData.appName || "").toUpperCase()
                            font.family: Theme.font; font.pixelSize: 10
                            color: Theme.dim
                            visible: text !== ""
                        }
                        Text {
                            width: parent.width
                            text: modelData.summary
                            font.family: Theme.font; font.pixelSize: Theme.fontSize
                            color: Theme.bright
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            text: modelData.body
                            visible: text !== ""
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                        }
                    }
                    Text {
                        anchors { right: parent.right; top: parent.top; margins: 8 }
                        text: "✕"
                        font.pixelSize: 11
                        color: Theme.dim
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            onClicked: modelData.dismiss()
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "nothing here"
                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                    color: Theme.dim
                }
            }
        }
    }
}
