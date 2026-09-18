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

// ---- calendar popout (click clock) ----
// layer surface (not xdg popup) so hyprland's blur layerrule applies
Popout {
    id: calPopout

    panelName: "calendar"
    iconName: "calendar"
    implicitWidth: 250

    property date shown: new Date()
    onOpenChanged: if (open) shown = new Date()

    // full date, the old custom/date module
    Text {
        text: Qt.formatDate(bar.clockDate, "dddd, d MMMM yyyy")
        font.family: Theme.font; font.pixelSize: 11
        color: Theme.dim
    }

    Item {
        id: calHead
        // hstep is the name AttachedPanel routes h/l to
        function hstep(n) { calPopout.shown = new Date(calPopout.shown.getFullYear(), calPopout.shown.getMonth() + n, 1); }
        width: calPopout.contentWidth
        height: 18
        // the whole header is one stop; h/l page the month,
        // rather than two arrow stops to tab between
        activeFocusOnTab: true
        Keys.onLeftPressed: calHead.hstep(-1)
        Keys.onRightPressed: calHead.hstep(1)
        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: 5
            color: calHead.activeFocus ? Theme.track : "transparent"
        }
        Text {
            text: Qt.locale().monthName(calPopout.shown.getMonth()) + " " + calPopout.shown.getFullYear()
            font.family: Theme.font; font.pixelSize: Theme.fontSize
            font.weight: Font.DemiBold
            color: Theme.bright
        }
        Row {
            anchors.right: parent.right
            spacing: 14
            Text {
                text: "‹"; font.pixelSize: 14; color: calHead.activeFocus ? Theme.bright : Theme.text
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    onClicked: calHead.hstep(-1)
                }
            }
            Text {
                text: "›"; font.pixelSize: 14; color: calHead.activeFocus ? Theme.bright : Theme.text
                MouseArea {
                    anchors.fill: parent; anchors.margins: -6
                    onClicked: calHead.hstep(1)
                }
            }
        }
    }

    DayOfWeekRow {
        width: calPopout.contentWidth
        delegate: Text {
            required property var model
            text: model.shortName
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font; font.pixelSize: 10
            color: Theme.dim
        }
    }
    MonthGrid {
        id: monthGrid
        width: calPopout.contentWidth
        month: calPopout.shown.getMonth()
        year: calPopout.shown.getFullYear()
        spacing: 2
        delegate: Text {
            required property var model
            text: model.day
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font
            font.pixelSize: 11
            font.weight: model.today ? Font.Bold : Font.Normal
            color: model.today ? Theme.accent
                 : model.month === monthGrid.month ? Theme.text : Theme.dim
        }
    }
}
