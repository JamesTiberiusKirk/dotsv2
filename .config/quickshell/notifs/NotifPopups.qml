import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import "../common"

// Transient notification popups, top-right. Critical urgency sticks until
// clicked; everything else times out (Notifs singleton owns the list).
PanelWindow {
    visible: Notifs.popups.length > 0
    anchors { top: true; right: true }
    margins { top: 46; right: 12 }
    implicitWidth: 320
    implicitHeight: col.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifs"

    Column {
        id: col
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.popups

            Rectangle {
                required property var modelData
                readonly property var n: modelData.n

                width: col.width
                implicitHeight: Math.max(inner.implicitHeight, nicon.visible ? 32 : 0) + 24
                radius: 12
                color: Theme.surface
                border.color: n?.urgency === 2 ? Theme.urgent : Theme.islandBorder
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    onClicked: n?.dismiss()
                }

                IconImage {
                    id: nicon
                    anchors { left: parent.left; top: parent.top; margins: 12 }
                    implicitSize: 32
                    visible: String(source) !== ""
                    source: n?.image || (n?.appIcon ? Quickshell.iconPath(n.appIcon, true) : "")
                }

                Column {
                    id: inner
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    anchors.leftMargin: nicon.visible ? 54 : 12
                    spacing: 3

                    Text {
                        text: (n?.appName ?? "").toUpperCase()
                        font.family: Theme.font; font.pixelSize: 10
                        font.letterSpacing: 0.5
                        color: Theme.dim
                        visible: text !== ""
                    }
                    Text {
                        width: parent.width
                        text: n?.summary ?? ""
                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                        font.weight: Font.DemiBold
                        color: Theme.bright
                        wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: n?.body ?? ""
                        visible: text !== ""
                        font.family: Theme.font; font.pixelSize: Theme.fontSize
                        color: Theme.text
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                    }
                    Row {
                        spacing: 8
                        topPadding: 6
                        visible: (n?.actions?.length ?? 0) > 0
                        Repeater {
                            model: n?.actions ?? []
                            Rectangle {
                                required property var modelData
                                radius: 7
                                color: Theme.track
                                implicitWidth: at.implicitWidth + 24
                                implicitHeight: at.implicitHeight + 6
                                Text {
                                    id: at
                                    anchors.centerIn: parent
                                    text: parent.modelData.text
                                    font.family: Theme.font; font.pixelSize: 11
                                    color: Theme.bright
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: parent.modelData.invoke()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
