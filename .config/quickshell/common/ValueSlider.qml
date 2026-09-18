import QtQuick

// A labelled slider row: label left, optional icons, value right, track below.
// Used by the display popout (brightness, night-light temperature) and the
// audio popout (per-device volume, AirPods adaptive level), which is why it
// lives here rather than inside either of them.
Item {
    id: sl
    property string label
    // Optional leading icon. iconOn dims rather than hides it,
    // so a list where only one row is marked stays aligned.
    property string icon: ""
    property bool iconOn: true
    // Second leading icon, for what the row *is* rather
    // than whether it is selected — `icon` is already
    // the default-device tick on every device row.
    property string leadIcon: ""
    // Right-hand extras, both optional: a dim note before
    // the value, and an icon with its own hit area and
    // tab stop for a second action on the row.
    property string note: ""
    property string trailIcon: ""
    signal trailPressed()
    readonly property real trailPad: rightRow.width + 8
    property int value: 0
    property int minValue: 0
    property int maxValue: 100
    property string suffix: "%"
    // control present but inert: the backlight still
    // takes writes, they just light nothing
    property bool off: false
    signal commit(int v)

    // One wheel notch moves a twentieth of the range, so
    // 0-100 still steps by 5 the way it always did.
    readonly property int wheelStep:
        Math.max(1, Math.round((maxValue - minValue) / 20))

    // the row fills whatever column it is dropped into; callers
    // that need something else set width themselves
    width: parent ? parent.width : 0
    height: 30
    opacity: off ? 0.4 : 1
    // arrows / h / l move by the same notch the wheel
    // does. Still a tab stop when off: a muted device's
    // Return still selects it, and skipping it would
    // strand it.
    activeFocusOnTab: true
    Keys.onLeftPressed: sl.hstep(-1)
    Keys.onRightPressed: sl.hstep(1)
    function hstep(dir) {
        if (sl.off) return;
        sl.shown = Math.max(sl.minValue, Math.min(sl.maxValue, sl.shown + dir * sl.wheelStep));
        sl.commit(sl.shown);
    }

    Rectangle {
        anchors { fill: parent; margins: -3 }
        radius: 5
        color: sl.activeFocus ? Theme.track : "transparent"
    }

    // While dragging, the slider owns the value: the 2s
    // poll is far slower than the drag and would keep
    // snapping the handle back to a stale reading.
    property bool held: false
    property int shown: 0
    onValueChanged: if (!held) shown = value
    Component.onCompleted: shown = value

    Row {
        id: slLabel

        spacing: 4

        Icon {
            name: sl.icon
            visible: sl.icon !== ""
            opacity: sl.iconOn ? 1 : 0
            size: 13
            color: sl.off ? Theme.dim : Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        Icon {
            name: sl.leadIcon
            visible: sl.leadIcon !== ""
            size: 13
            color: sl.off ? Theme.dim : Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: sl.label
            font.family: Theme.font; font.pixelSize: 11
            color: sl.off ? Theme.dim : Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Row {
        id: rightRow
        anchors.right: parent.right
        spacing: 6
        // Above the row-wide "make this the default"
        // MouseArea, which is a later sibling of this Row.
        z: 10

        Text {
            visible: sl.note !== ""
            // notes carry their own colours per span
            textFormat: Text.StyledText
            text: sl.note
            font.family: Theme.font; font.pixelSize: 10
            color: Theme.dim
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: sl.off ? "off" : sl.shown + sl.suffix
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.dim
            anchors.verticalCenter: parent.verticalCenter
        }
        // z: the strip this sits on already carries a
        // click meaning "make this the default device",
        // and that MouseArea is declared later, so it
        // would otherwise swallow the icon.
        Item {
            id: trail
            visible: sl.trailIcon !== ""
            width: 15; height: 15
            anchors.verticalCenter: parent.verticalCenter
            activeFocusOnTab: sl.trailIcon !== ""
            Keys.onReturnPressed: sl.trailPressed()

            Rectangle {
                anchors { fill: parent; margins: -2 }
                radius: 4
                color: trail.activeFocus ? Theme.track : "transparent"
            }
            Icon {
                anchors.centerIn: parent
                name: sl.trailIcon
                size: 13
                color: Theme.dim
            }
            MouseArea {
                anchors { fill: parent; margins: -4 }
                onClicked: sl.trailPressed()
            }
        }
    }

    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 2 }
        height: 6
        radius: 3
        color: Theme.track

        readonly property real frac:
            (sl.shown - sl.minValue) / Math.max(1, sl.maxValue - sl.minValue)

        Rectangle {
            width: parent.width * track.frac
            height: parent.height
            radius: 3
            color: sl.off ? Theme.dim : Theme.accent
        }
        Rectangle {
            visible: !sl.off
            x: Math.max(0, Math.min(parent.width - width, parent.width * track.frac - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6
            color: Theme.bright
        }

        function valueAt(mx) {
            const v = sl.minValue + mx / width * (sl.maxValue - sl.minValue);
            return Math.max(sl.minValue, Math.min(sl.maxValue, Math.round(v)));
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8 // 6px track is a small target
            enabled: !sl.off
            preventStealing: true
            onPressed: m => { sl.held = true; sl.shown = track.valueAt(m.x); writeTimer.restart(); }
            onPositionChanged: m => { if (sl.held) { sl.shown = track.valueAt(m.x); writeTimer.restart(); } }
            onReleased: { sl.held = false; writeTimer.stop(); sl.commit(sl.shown); }
            onWheel: w => {
                sl.shown = Math.max(sl.minValue, Math.min(sl.maxValue,
                    sl.shown + (w.angleDelta.y > 0 ? sl.wheelStep : -sl.wheelStep)));
                sl.commit(sl.shown);
            }
        }
        // one write per 50ms of dragging, not one per frame
        Timer {
            id: writeTimer
            interval: 50
            onTriggered: sl.commit(sl.shown)
        }
    }
}
