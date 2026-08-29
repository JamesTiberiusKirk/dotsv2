import QtQuick
import QtQuick.Layouts

// Layout-only container for a bar cluster. The notch shape itself is painted
// by Bar.qml's bezel canvas so band + notches are one seamless path.
// GridLayout because it is the one layout that flips axis on a property;
// children size by implicitWidth/Height and align via Layout.alignment.
Item {
    id: root
    default property alias content: grid.data

    readonly property bool v: ShellState.vertical
    implicitHeight: v ? grid.implicitHeight + 12 : ShellState.barBody
    implicitWidth: v ? ShellState.barBody : grid.implicitWidth + 12

    GridLayout {
        id: grid
        anchors.centerIn: parent
        flow: root.v ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 0
        columnSpacing: 0
    }
}
