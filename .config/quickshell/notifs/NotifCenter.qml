import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes
import "../common"

// Notification drawer — full height, right edge, slides in from off-screen
// (bell in the bar, or `qs ipc call notifs toggle`). History on top, the
// controls that govern it pinned to the bottom.
Scope {
    id: root

    readonly property int drawerWidth: 360
    readonly property int slideMs: 240
    // same geometry as the bar's capsules: convex corner, concave fillet where
    // the island meets its band
    readonly property int cornerR: 12
    readonly property int fillet: 8

    // Esc in the `popout` submap (binds.lua) lands here.
    IpcHandler {
        target: "popouts"
        function closeAll(): void { Sys.closeAll(); }
    }

    IpcHandler {
        target: "notifs"
        function toggle(): void { Notifs.toggle(); }
        function dismissAll(): void { Notifs.dismissAll(); }
        function dismissLatest(): void { Notifs.dismissLatest(); }
        // same switch as right-clicking the bell, for a keybind
        function dnd(): void { Notifs.dnd = !Notifs.dnd; }
    }

    // click-off
    PanelWindow {
        visible: Notifs.centerOpen
        screen: Notifs.centerScreen || Quickshell.screens[0]
        anchors { top: true; right: true; bottom: true; left: true }
        margins { top: Theme.barBody + Theme.frameT }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-notifs-backdrop"

        MouseArea {
            anchors.fill: parent
            onClicked: Notifs.centerOpen = false
        }
    }

    PanelWindow {
        id: win

        // Mapped at full size and left that way while open; the sheet inside
        // does the moving. Held after close for the slide-out, then unmapped —
        // same reasoning as the toasts: resizing or unmapping mid-animation
        // blinks the whole surface.
        //
        // Set imperatively rather than bound to `centerOpen || closing.running`:
        // a binding re-evaluates before the handler that starts the timer, so
        // for one frame both halves were false — the surface unmapped, then
        // mapped again to play the slide-out.
        visible: false
        Timer { id: closing; interval: root.slideMs; onTriggered: win.visible = false }
        Connections {
            target: Notifs
            function onCenterOpenChanged() {
                if (Notifs.centerOpen) { closing.stop(); win.visible = true; }
                else closing.restart();
            }
        }

        screen: Notifs.centerScreen || Quickshell.screens[0]
        anchors { top: true; right: true; bottom: true }
        // Hangs off the right frame band like a bar island hangs off the top
        // one. The fillets curve out onto the band above and below the
        // island, so the window is a fillet taller at each end than the island
        // itself and the content insets by that much.
        margins {
            top: Theme.barBody + Theme.frameT + Theme.popoutGap - root.fillet
            right: Theme.frameT
            bottom: Theme.frameT + Theme.frameFillet + Theme.popoutGap - root.fillet
        }
        implicitWidth: root.drawerWidth
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-drawer"
        // No keyboard focus. Hyprland focuses a layer that asks for it the
        // moment it maps, and with the pointer still parked on the bell that
        // focus stayed on the drawer — the second click never reached the
        // bar. Esc-to-close went with it; click-off and the bell both close.

        Item {
            id: sheet

            width: parent.width
            height: parent.height
            // parked off the right edge; the animation brings it in
            x: Notifs.centerOpen ? 0 : width
            Behavior on x { NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }

            // The island itself — the bar's capsule path turned on its side.
            // Shape, not Canvas: Canvas AA edges composite with a premultiply
            // mismatch on nvidia (dark fringe around every path edge).
            Shape {
                id: island
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // qualified below by id: a ShapePath only sees the properties
                // of its component root, and this Shape is not one (the bar's
                // capsule Shape is a Repeater delegate, which is why it can
                // use bare names)
                readonly property real w: width
                readonly property real h: height
                readonly property real nf: root.fillet
                readonly property real cr: root.cornerR

                // fill — auto-closes along x = island.w, flush against the band
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: Theme.island
                    startX: island.w; startY: 0
                    // fillets are concave: default (clockwise) arcs, the
                    // same as the bar's capsules; the convex corners between
                    // them are the counterclockwise ones
                    PathArc { x: island.w - island.nf; y: island.nf; radiusX: island.nf; radiusY: island.nf }
                    PathLine { x: island.cr; y: island.nf }
                    PathArc { x: 0; y: island.nf + island.cr; radiusX: island.cr; radiusY: island.cr; direction: PathArc.Counterclockwise }
                    PathLine { x: 0; y: island.h - island.nf - island.cr }
                    PathArc { x: island.cr; y: island.h - island.nf; radiusX: island.cr; radiusY: island.cr; direction: PathArc.Counterclockwise }
                    PathLine { x: island.w - island.nf; y: island.h - island.nf }
                    PathArc { x: island.w; y: island.h; radiusX: island.nf; radiusY: island.nf }
                }
                // outline — same run, left open along the band
                ShapePath {
                    strokeColor: Theme.islandBorder
                    strokeWidth: 1
                    fillColor: "transparent"
                    startX: island.w; startY: 0
                    // fillets are concave: default (clockwise) arcs, the
                    // same as the bar's capsules; the convex corners between
                    // them are the counterclockwise ones
                    PathArc { x: island.w - island.nf; y: island.nf; radiusX: island.nf; radiusY: island.nf }
                    PathLine { x: island.cr; y: island.nf }
                    PathArc { x: 0; y: island.nf + island.cr; radiusX: island.cr; radiusY: island.cr; direction: PathArc.Counterclockwise }
                    PathLine { x: 0; y: island.h - island.nf - island.cr }
                    PathArc { x: island.cr; y: island.h - island.nf; radiusX: island.cr; radiusY: island.cr; direction: PathArc.Counterclockwise }
                    PathLine { x: island.w - island.nf; y: island.h - island.nf }
                    PathArc { x: island.w; y: island.h; radiusX: island.nf; radiusY: island.nf }
                }
            }

            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16; topMargin: 16 + root.fillet }
                height: 22

                Text {
                    text: "notifications"
                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    color: Theme.bright
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "clear all"
                    font.family: Theme.font; font.pixelSize: 11
                    color: Theme.accent
                    visible: list.count > 0
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: Notifs.dismissAll()
                    }
                }
            }

            // ScriptModel rather than a plain JS array: an array model has no row
            // identity, so every arrival re-instantiated the whole list — scroll
            // position reset and every icon re-decoded. Keyed on the record's own
            // key because the daemon reuses notification ids after a close.
            ScriptModel {
                id: histModel
                objectProp: "key"
                values: [...Notifs.history].reverse()
            }

            ListView {
                id: list
                anchors {
                    top: header.bottom; bottom: controls.top
                    left: parent.left; right: parent.right
                    topMargin: 10; bottomMargin: 10; leftMargin: 16; rightMargin: 16
                }
                clip: true
                spacing: 6
                model: histModel
                // Rows are variable height, so the view estimates its content
                // height and corrects it whenever a row is instantiated — and
                // a correction mid-fling stops the fling. History is capped at
                // 100, so keeping every row alive is cheap and the glide is
                // never interrupted.
                cacheBuffer: 100000
                SmoothScroll { flick: list }

                delegate: Rectangle {
                    required property var modelData
                    width: list.width
                    implicitHeight: Math.max(c.implicitHeight, hicon.visible ? 24 : 0) + 20
                    radius: 9
                    color: Theme.track
                    // muted senders still land here, just quieter
                    opacity: Notifs.isMuted(modelData.appName) ? 0.5 : 1

                    IconImage {
                        id: hicon
                        anchors { left: parent.left; top: parent.top; margins: 10 }
                        implicitSize: 24
                        // A sender can pass a temp file and delete it once the
                        // notification is out (satty does), so a path that was fine on
                        // arrival fails to load later. Fold the slot away rather than
                        // show the error placeholder.
                        visible: String(source) !== "" && status !== Image.Error
                        // live handle first, then whatever path the record kept
                        // picture first; if that file is gone, the app icon
                        readonly property string pic: Notifs.imageSource((modelData.n && String(modelData.n.image || "")) || modelData.image)
                        readonly property string fallback: Notifs.appIconSource(modelData.appIcon, modelData.appName)
                        property bool picFailed: false
                        onStatusChanged: if (status === Image.Error && String(source) === pic) picFailed = true
                        source: (pic && !picFailed) ? pic : fallback
                    }

                    Column {
                        id: c
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        anchors.leftMargin: hicon.visible ? 42 : 10
                        anchors.rightMargin: 44   // clear of the mute + X
                        spacing: 2

                        Row {
                            spacing: 6
                            Text {
                                text: (modelData.appName || "").toUpperCase()
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.dim
                                visible: text !== ""
                            }
                            Text {
                                // relative, and re-evaluated off Notifs.tick while
                                // the drawer is open — an absolute clock time reads
                                // as noise on something that arrived a minute ago
                                text: Notifs.ago(modelData.time)
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.dim
                            }
                        }
                        Text {
                            width: parent.width
                            text: modelData.summary
                            font.family: Theme.font; font.pixelSize: Theme.fontSize
                            color: Theme.bright
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            text: modelData.body
                            visible: text !== ""
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                        }
                        ActionRow { actions: modelData.n ? modelData.n.actions : [] }
                    }
                    Row {
                        anchors { right: parent.right; top: parent.top; margins: 8 }
                        spacing: 8
                        // mute this sender in place — the full list is at the
                        // bottom, but the row you are annoyed by is right here
                        Icon {
                            readonly property bool muted: Notifs.isMuted(modelData.appName)
                            visible: modelData.appName !== ""
                            name: muted ? "bell-off" : "bell"
                            size: 13
                            color: muted ? Theme.accent : Theme.dim
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                onClicked: Notifs.setMuted(modelData.appName, !parent.muted)
                            }
                        }
                        Icon {
                            name: "close"
                            size: 13
                            color: Theme.dim
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                onClicked: Notifs.remove(modelData)
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: "nothing here"
                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                    color: Theme.dim
                }
            }

            // Pinned to the bottom: the switches that decide what reaches you.
            Column {
                id: controls
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 16; bottomMargin: 16 + root.fillet }
                spacing: 8

                Rectangle { width: parent.width; height: 1; color: Theme.track }

                ToggleRow {
                    label: "do not disturb"
                    checked: Notifs.dnd
                    onToggled: v => Notifs.dnd = v
                }

                Text {
                    text: "muted apps"
                    font.family: Theme.font; font.pixelSize: 10
                    color: Theme.dim
                    visible: Notifs.apps.length > 0
                }
                // Every sender history knows about. Muting is per appName,
                // which is why the list is whatever has actually sent
                // something rather than a registry you would have to fill.
                Repeater {
                    model: Notifs.apps
                    ToggleRow {
                        required property string modelData
                        label: modelData
                        checked: Notifs.isMuted(modelData)
                        onToggled: v => Notifs.setMuted(modelData, v)
                    }
                }
            }
        }
    }
}
