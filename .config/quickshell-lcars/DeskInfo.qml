import QtQuick
import "."

// Desktop readout drawn on the black backdrop: shows through wherever a workspace has no windows.
// `mon` picks the monitor; insets keep it inside the LCARS frame. Only `pillArea` should take input.
Item {
    id: d
    required property var ship
    property string mon: "eDP-1"
    property int leftInset: Lc.pad + Lc.topSpine
    property int topInset: 0
    readonly property Item pillArea: pills
    readonly property var info: ship.desk(mon)
    readonly property int cx: leftInset + 40
    readonly property int cy: topInset + 36

    // DECK display: giant workspace number between two rules
    Rectangle { x: d.cx; y: d.cy; width: 420; height: 10; color: Lc.orange; radius: 5 }
    Label { x: d.cx; y: d.cy + 14; text: "DECK"; color: Lc.tan; font.pixelSize: 44; font.letterSpacing: 8 }
    Label { x: d.cx - 8; y: d.cy - 12; text: d.info.id > 0 ? d.info.id : "--"; color: Lc.orange; font.pixelSize: 300; font.weight: Font.Bold }
    Rectangle { x: d.cx; y: d.cy + 340; width: 420; height: 10; color: Lc.orange; radius: 5 }
    Label { x: d.cx; y: d.cy + 356; text: d.info.name + "  /  " + d.info.layout; color: Lc.peach; font.pixelSize: 34 }
    Label { x: d.cx + 420 - width; y: d.cy + 14; text: Lc.code("DECK" + d.mon); color: Lc.lilac; font.pixelSize: 24 }

    // right column: windows then monitor
    Column {
        x: d.cx + 480; y: d.cy
        width: 640
        spacing: 6
        Rectangle { width: parent.width; height: 10; color: Lc.lilac; radius: 5 }
        Label { text: "OCCUPANTS: " + d.info.count; color: Lc.lilac; font.pixelSize: 34 }
        Repeater {
            model: d.info.titles.slice(0, 6)
            CodedRow { width: 640; height: 46; implicitHeight: 46; label: modelData; tint: Lc.blue; enabled: false }
        }
        Label { visible: d.info.count === 0; text: "DECK UNOCCUPIED"; color: Lc.dim; font.pixelSize: 26 }
        Label { visible: d.info.count > 6; text: "+" + (d.info.count - 6) + " MORE"; color: Lc.tan; font.pixelSize: 22 }
        Item { width: 1; height: 24 }
        Rectangle { width: parent.width; height: 10; color: Lc.sky; radius: 5 }
        Label { text: "DISPLAY " + d.mon; color: Lc.sky; font.pixelSize: 34 }
        CodedRow { width: 640; height: 46; implicitHeight: 46; label: "RESOLUTION"; value: d.info.res; tint: Lc.sky; enabled: false }
        CodedRow { width: 640; height: 46; implicitHeight: 46; label: "SCALE"; value: d.info.scale; tint: Lc.sky; enabled: false }
        CodedRow { width: 640; height: 46; implicitHeight: 46; label: "REFRESH"; value: d.info.refresh; tint: Lc.sky; enabled: false }
    }

    // other decks on this monitor: the only part of the backdrop that takes input
    Row {
        id: pills
        x: d.cx; y: d.cy + 440
        spacing: 10
        Repeater {
            model: d.info.others
            Pill {
                tint: modelData.urgent ? Lc.red : Lc.blue
                text: "DECK " + modelData.id
                sub: Lc.code("D" + modelData.id)
                implicitWidth: 150; implicitHeight: 64
                onClicked: d.ship.dispatch("hl.dsp.focus({ workspace = " + modelData.id + " })")
            }
        }
    }
}
