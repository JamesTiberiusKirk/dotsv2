import QtQuick

// Pill-shaped button: label with its own background, used by the power
// profile selector, the audio device rows and the tailscale exit picker.
// Lifted out of Bar.qml so a popout in its own file can still use it.
Text {
    id: pb
    property bool active: false
    signal pressed()
    topPadding: 4; bottomPadding: 4; leftPadding: 10; rightPadding: 10
    font.family: Theme.font
    font.pixelSize: 11
    color: pb.active ? Theme.accentText : Theme.text
    activeFocusOnTab: true
    Keys.onReturnPressed: pb.pressed()
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: pb.active ? Theme.accent : Theme.track
        border.width: pb.activeFocus ? 1 : 0
        border.color: Theme.bright
        z: -1
    }
    MouseArea { anchors.fill: parent; onClicked: pb.pressed() }
}
