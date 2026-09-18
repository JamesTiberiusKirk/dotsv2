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

// ---- resource panel (click resource island) ----
Popout {
    id: resourcePopout

    panelName: "system"
    iconName: "cpu-64-bit"
    implicitWidth: 320

    component ResourceMeter: Item {
        property string label
        property real value // 0..1
        property string detail: Math.round(value * 100) + "%"

        width: resourcePopout.contentWidth
        height: 18

        Text {
            text: label
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            anchors { right: rvalue.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 100; height: 4; radius: 2
            color: Theme.track
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, value))
                height: parent.height; radius: 2
                color: Theme.accent
            }
        }
        Text {
            id: rvalue
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: detail
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.dim
        }
    }

    component ResourceInfoRow: Item {
        property string label
        property string value

        width: resourcePopout.contentWidth
        height: 16

        Text {
            text: label
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.text
        }
        Text {
            anchors.right: parent.right
            text: value
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.dim
        }
    }

    ResourceMeter { label: "cpu"; value: Sys.cpu }
    ResourceInfoRow { label: "mem"; value: Sys.memText }
    ResourceInfoRow { visible: Sys.swapText !== ""; label: "swap"; value: Sys.swapText }
    ResourceInfoRow { label: "disk free"; value: Sys.diskFree }
    ResourceInfoRow { label: "net"; value: Sys.netText }
}
