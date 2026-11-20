import QtQuick
import "."

// Label + big number + small note, with the LCARS side rule.
Item {
    id: r
    property string label: ""
    property string value: "--"
    property string note: ""
    property real level: -1                 // 0..1 draws a meter, -1 hides it
    property color tint: Lc.orange

    implicitHeight: col.implicitHeight + 6
    Rectangle { width: 8; height: parent.height; color: Lc.lilac }
    Column {
        id: col
        x: 22; width: parent.width - 22; spacing: 2
        Label { text: r.label; color: Lc.lilac; font.pixelSize: 16 }
        Row {
            spacing: 10
            Label { text: r.value; font.pixelSize: 44 }
            Label { text: r.note; color: Lc.tan; font.pixelSize: 19; anchors.baseline: parent.children[0].baseline }
        }
        Meter { visible: r.level >= 0; width: parent.width; value: r.level; tint: r.tint }
    }
}
