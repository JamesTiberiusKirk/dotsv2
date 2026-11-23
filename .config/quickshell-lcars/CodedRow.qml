import QtQuick
import "."

// One list row: coloured side rule, fake LCARS code, label, value, optional
// meter along the bottom. Extra children (pills) land at the right end.
// Tap anywhere (below the extras) emits clicked().
Rectangle {
    id: r
    property string label: ""
    property string value: ""
    property string note: ""               // small line under the label
    property string note2: ""              // optional third line, smaller
    property real level: -1                // 0..1 draws the meter, -1 none
    property color tint: Lc.lilac
    property color valueColor: Lc.peach
    property bool hot: false               // highlighted row (current/connected)
    property string code: Lc.code(label)
    default property alias extra: slot.data
    signal clicked()

    implicitHeight: (level >= 0 && note !== "") ? 82 : 64
    color: hot ? Lc.track : "transparent"
    Rectangle { width: 8; height: parent.height; color: r.tint }
    MouseArea { anchors.fill: parent; onClicked: r.clicked() }
    Label { x: 22; anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: r.level >= 0 ? -10 : 0; text: r.code; color: r.tint; font.pixelSize: 15; width: 52 }
    Column {
        x: 82
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: r.level >= 0 ? -10 : 0
        width: Math.max(0, slot.x - 94)
        Label { width: parent.width; text: r.label; color: r.hot ? Lc.orange : Lc.peach; font.pixelSize: 24; elide: Text.ElideRight }
        Label { visible: r.note !== ""; width: parent.width; text: r.note; color: Lc.tan; font.pixelSize: 18; elide: Text.ElideRight }
        Label { visible: r.note2 !== ""; width: parent.width; text: r.note2; color: Lc.tan; font.pixelSize: 15; elide: Text.ElideRight }
    }
    Row {
        id: slot
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter; verticalCenterOffset: r.level >= 0 ? -10 : 0 }
        spacing: 10
        Label { visible: r.value !== ""; anchors.verticalCenter: parent.verticalCenter; text: r.value; color: r.valueColor; font.pixelSize: 26 }
    }
    Meter {
        visible: r.level >= 0
        x: 82; width: parent.width - 82 - 10
        y: parent.height - 18; height: 10
        value: Math.max(0, r.level); tint: r.tint
    }
}
