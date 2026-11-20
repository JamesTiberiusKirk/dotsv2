import QtQuick
import "."

// Segmented LCARS gauge. Tap or drag to set when `interactive`.
// moved() is throttled to 50ms (last value wins) and always fires on release.
Item {
    id: m
    property real value: 0                 // 0..1
    property color tint: Lc.orange
    property bool interactive: false
    signal moved(real v)

    property real _pending: 0
    property bool _dirty: false
    readonly property real shown: area.dragging ? _pending : value
    function _flush() { _dirty = false; m.moved(_pending); }

    // interactive meters are a 56px touch strip (no overlap with neighbours); the bar is drawn centred in it
    implicitHeight: interactive ? 56 : 18
    readonly property real barH: interactive ? 34 : height
    readonly property int seg: 14
    readonly property int count: Math.max(1, Math.floor(width / (seg + 4)))

    Rectangle { width: parent.width; height: m.barH; anchors.verticalCenter: parent.verticalCenter; color: Lc.track }
    Row {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: 4
        Repeater {
            model: Math.round(Math.max(0, Math.min(1, m.shown)) * m.count)
            Rectangle { width: m.seg; height: m.barH; color: m.tint }
        }
    }
    Timer {
        id: throttle
        interval: 50
        onTriggered: if (m._dirty) m._flush()
    }
    // A press alone sets nothing (a stray touch must not change volume): it sets after ~10px of
    // horizontal movement (a drag), or on release as a tap.
    MouseArea {
        id: area
        enabled: m.interactive
        anchors.fill: parent
        property real startX: 0
        property bool dragging: false
        preventStealing: dragging
        function set(x) {
            m._pending = Math.max(0, Math.min(1, x / m.width));
            m._dirty = true;
            if (!throttle.running) { m._flush(); throttle.start(); }
        }
        onPressed: e => { startX = e.x; dragging = false; }
        onPositionChanged: e => {
            if (!dragging && Math.abs(e.x - startX) > 10) dragging = true;
            if (dragging) set(e.x);
        }
        onReleased: e => {
            if (!dragging) set(e.x);
            if (m._dirty) m._flush();
            dragging = false;
        }
        onCanceled: dragging = false
    }
}
