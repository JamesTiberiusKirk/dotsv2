import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts
import "../../common"

// ---- docker / vm popouts (click their cells) ----
// Same list shape for both: name left, status right, a line of
// dim text when there is nothing to list.
Popout {
    id: lp
    property var rows: []      // [{ name, status }]
    property string empty: "nothing running"

    implicitWidth: 320
    rowSpacing: 6

    Text {
        visible: lp.rows.length === 0
        text: lp.empty
        font.family: Theme.font; font.pixelSize: 11
        color: Theme.dim
    }
    Repeater {
        model: lp.rows
        // Two lines: the name is what you opened this for
        // and container names run long, so it gets the
        // whole width; the status sits under it.
        Column {
            required property var modelData
            width: lp.contentWidth
            spacing: 1
            Text {
                width: parent.width
                text: modelData.name
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.text
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: modelData.status
                font.family: Theme.font; font.pixelSize: 10
                color: Theme.dim
                elide: Text.ElideRight
            }
        }
    }
}
