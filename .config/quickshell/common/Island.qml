import QtQuick

// Layout-only container for a bar cluster. The notch shape itself is painted
// by Bar.qml's bezel canvas so band + notches are one seamless path.
Item {
    default property alias content: row.data

    implicitHeight: 30
    implicitWidth: row.implicitWidth + 12

    Row {
        id: row
        anchors.centerIn: parent
    }
}
