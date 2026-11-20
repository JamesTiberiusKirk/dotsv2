import QtQuick
import "."

// LCARS button. Label sits bottom-right like the show. Flashes white on press.
// `toggle` pills dim when off. `holdMs` > 0 means press-and-hold to fire, with a fill.
Rectangle {
    id: pill
    property string text: ""
    property color tint: Lc.blue
    property bool toggle: false
    property bool on: true
    property bool square: false            // square left edge (station column)
    property int labelSize: 20
    property string sub: ""                // small code in the top-left
    property int holdMs: 0
    property real progress: 0
    property bool flash: false             // a very quick tap still shows white for a moment (timer runs only after a tap)
    signal clicked()

    implicitWidth: Math.max(140, lbl.implicitWidth + 44)
    implicitHeight: 54
    radius: square ? 0 : height / 2
    color: (area.pressed || flash) && holdMs === 0 ? "white" : (toggle && !on ? Lc.dim : tint)
    clip: true

    Rectangle {
        visible: pill.holdMs > 0 && pill.progress > 0
        width: parent.width * pill.progress; height: parent.height
        radius: pill.radius
        color: "white"
    }
    Label {
        id: lbl
        text: pill.text
        color: toggle && !on ? Lc.peach : "black"
        font.pixelSize: pill.labelSize
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: pill.square ? 12 : 22; bottomMargin: 4 }
    }
    Label {
        visible: pill.sub !== ""
        text: pill.sub
        color: "black"
        font.pixelSize: 12
        anchors { left: parent.left; top: parent.top; leftMargin: 10; topMargin: 4 }
    }
    NumberAnimation {
        id: hold
        target: pill; property: "progress"
        from: 0; to: 1; duration: pill.holdMs
        onFinished: { pill.progress = 0; pill.clicked(); }
    }
    Timer { id: flashOff; interval: 160; onTriggered: pill.flash = false }
    MouseArea {
        id: area
        anchors.fill: parent
        onPressed: if (pill.holdMs > 0) hold.restart()
        onReleased: if (pill.holdMs > 0) { hold.stop(); pill.progress = 0; }
        onCanceled: if (pill.holdMs > 0) { hold.stop(); pill.progress = 0; }
        onClicked: if (pill.holdMs === 0) { pill.flash = true; flashOff.restart(); pill.clicked(); }
    }
}
