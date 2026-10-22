import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../common"

// Region picker shared by ~/.scripts/screenshot.sh and ~/.scripts/record.sh; replaces
// slurp (CPU-drawn, chokes on 4K). Lives in the main shell so it opens instantly:
// `qs ipc call region pick '<sh cmd>'`. Drag a box on any screen, release → runs the cmd
// detached with the box as $1 ("x,y wxh", what grim -g / wl-screenrec -g want).
// Esc or right click cancels → cmd runs with $1 empty, so callers can clean up.
Scope {
    id: root

    property bool active: false
    property string cmd: ""

    // drag state in global logical coords
    property real x0: 0
    property real y0: 0
    property real x1: 0
    property real y1: 0
    property bool dragging: false
    // wl-screenrec can't span outputs: pickOne keeps the box on the screen the drag began on
    property bool oneScreen: false
    readonly property real rx: Math.min(x0, x1)
    readonly property real ry: Math.min(y0, y1)
    readonly property real rw: Math.abs(x1 - x0)
    readonly property real rh: Math.abs(y1 - y0)
    property string geom: ""
    // last picked box, kept for the recording frame
    property rect shot: Qt.rect(0, 0, 0, 0)

    IpcHandler {
        target: "region"
        function pickOne(cmd: string): void { pick(cmd); root.oneScreen = true; }
        function pick(cmd: string): void {
            root.oneScreen = false;
            root.cmd = cmd;
            root.x0 = root.y0 = root.x1 = root.y1 = 0;
            root.dragging = false;
            root.active = true;
        }
        function recStart(mode: string): void {
            ShellState.recStarted = Date.now();
            ShellState.recording = mode;
        }
        function recStop(): void { ShellState.recording = ""; }
    }

    function close() {
        dragging = false;
        active = false;
        geom = "";
        runDelay.restart();
    }

    function finish() {
        const w = Math.round(rw), h = Math.round(rh);
        if (w < 2 || h < 2) return close();
        dragging = false;
        active = false;
        geom = `${Math.round(rx)},${Math.round(ry)} ${w}x${h}`;
        shot = Qt.rect(Math.round(rx), Math.round(ry), w, h);
        runDelay.restart();
    }

    // let the dim layers fade out before the capture starts.
    // ponytail: fixed delay, raise it if the shade ever shows up in captures
    Timer {
        id: runDelay
        interval: 60
        onTriggered: Quickshell.execDetached(["sh", "-c", root.cmd, "sh", root.geom])
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "region-picker"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            readonly property real ox: modelData.x
            readonly property real oy: modelData.y

            // dim everything; the selection is punched out by four bands around it
            readonly property real sx: root.rx - ox
            readonly property real sy: root.ry - oy
            readonly property color shade: "#66000000"
            Rectangle { color: win.shade; x: 0; y: 0; width: parent.width; height: Math.max(0, win.sy) }
            Rectangle { color: win.shade; x: 0; y: Math.max(0, win.sy + root.rh); width: parent.width; height: parent.height - y }
            Rectangle { color: win.shade; x: 0; y: Math.max(0, win.sy); width: Math.max(0, win.sx); height: Math.max(0, Math.min(parent.height, win.sy + root.rh) - y) }
            Rectangle { color: win.shade; x: Math.max(0, win.sx + root.rw); y: Math.max(0, win.sy); width: parent.width - x; height: Math.max(0, Math.min(parent.height, win.sy + root.rh) - y) }

            Rectangle {
                visible: root.dragging
                // drawn just outside the box so it never lands in the grim capture
                x: win.sx - 2; y: win.sy - 2; width: root.rw + 4; height: root.rh + 4
                color: "transparent"
                border.color: "#A000FF"
                border.width: 2
            }

            MouseArea {
                anchors.fill: parent
                focus: true
                cursorShape: Qt.CrossCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: e => {
                    if (e.button === Qt.RightButton) return root.close();
                    root.x0 = root.x1 = Math.round(e.x + win.ox);
                    root.y0 = root.y1 = Math.round(e.y + win.oy);
                    root.dragging = true;
                }
                // pointer stays grabbed by this surface while held, so coords past
                // its edge still map into neighbouring screens
                onPositionChanged: e => {
                    if (!root.dragging) return;
                    const x = root.oneScreen ? Math.max(0, Math.min(win.width, e.x)) : e.x;
                    const y = root.oneScreen ? Math.max(0, Math.min(win.height, e.y)) : e.y;
                    root.x1 = Math.round(x + win.ox);
                    root.y1 = Math.round(y + win.oy);
                }
                onReleased: e => { if (e.button === Qt.LeftButton && root.dragging) root.finish(); }
                Keys.onEscapePressed: root.close()
            }
        }
    }

    // red outline around the box while record.sh is recording. Sits just outside
    // the box so wl-screenrec never captures it; empty mask = clicks pass through.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: frame
            required property var modelData
            screen: modelData
            readonly property real ox: modelData.x
            readonly property real oy: modelData.y
            visible: ShellState.recording !== "" && root.shot.width > 0
                && root.shot.x >= ox && root.shot.x < ox + modelData.width
                && root.shot.y >= oy && root.shot.y < oy + modelData.height
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "record-frame"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                x: root.shot.x - frame.ox - 2; y: root.shot.y - frame.oy - 2
                width: root.shot.width + 4; height: root.shot.height + 4
                color: "transparent"
                border.color: Theme.urgent
                border.width: 2
            }
        }
    }
}
