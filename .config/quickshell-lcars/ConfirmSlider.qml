import QtQuick
import "."

// Slide-to-confirm for destructive actions. Drag the handle (the drag can only start on the handle) to the far end;
// releasing short of it snaps back. A tap anywhere never confirms. Emits confirmed() once.
Item {
    id: cs
    property string text: "SLIDE TO CONFIRM"
    property color tint: Lc.red
    signal confirmed()
    implicitWidth: 420
    implicitHeight: 64

    Rectangle { anchors.fill: parent; radius: height / 2; color: Lc.track; border.width: 3; border.color: cs.tint }
    Label {
        anchors { centerIn: parent; horizontalCenterOffset: handle.width / 2 }
        text: cs.text; color: cs.tint; font.pixelSize: 22
        width: Math.min(implicitWidth, cs.width - handle.width - 40); elide: Text.ElideRight   // a long title must not run under the handle
        opacity: 1 - handle.x / Math.max(1, cs.width - handle.width)
    }
    Rectangle {
        id: handle
        width: 96; height: cs.height
        radius: height / 2
        color: area.held ? "white" : cs.tint
        Label { anchors.centerIn: parent; text: ">>>"; color: "black"; font.pixelSize: 24 }
        NumberAnimation on x { id: back; running: false; to: 0; duration: 160 }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        property real grab: 0
        property bool held: false   // the press began on the handle: only then is this a slide (a tap on the track never confirms)
        // inside a Flickable / ListView on a touch screen: a held handle must not be stolen by the scroll
        preventStealing: held
        onPressed: e => {
            held = e.x >= handle.x && e.x <= handle.x + handle.width;
            if (!held) { e.accepted = false; return; }   // not ours: the scroll view underneath gets it
            back.stop();
            grab = e.x - handle.x;
        }
        onPositionChanged: e => { if (held) handle.x = Math.max(0, Math.min(cs.width - handle.width, e.x - grab)); }
        onReleased: {
            const ok = held && handle.x >= (cs.width - handle.width) * 0.92;
            held = false;
            if (ok) cs.confirmed();
            back.start();
        }
        onCanceled: { held = false; back.start(); }
    }
}
