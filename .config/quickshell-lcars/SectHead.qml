import QtQuick
import QtQuick.Layouts
import "."

// Section head: orange title, dim rule, optional small code at the end.
RowLayout {
    property alias text: t.text
    property string code: ""
    Layout.fillWidth: true
    spacing: 12
    Label { id: t; color: Lc.orange; font.pixelSize: 26 }
    Rectangle { Layout.fillWidth: true; height: 6; radius: 3; color: Lc.dim }
    Label { visible: parent.code !== ""; text: parent.code; color: Lc.tan; font.pixelSize: 15 }
}
