import QtQuick

// Label left, switch right. Was declared inline in the display panel; the
// power panel wanted the same thing, and two copies of a switch is one too
// many. Sizes itself to its Column parent, like every other row in a popout.
Item {
    id: root

    property string label
    property bool checked: false
    signal toggled(bool value)

    width: parent ? parent.width : 0
    height: 20

    Text {
        text: root.label
        anchors.verticalCenter: parent.verticalCenter
        font.family: Theme.font; font.pixelSize: 11
        color: Theme.text
    }
    Rectangle {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 30; height: 16; radius: 8
        color: root.checked ? Theme.accent : Theme.track
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            x: root.checked ? parent.width - width - 2 : 2
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6
            color: root.checked ? Theme.accentText : Theme.bright
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
