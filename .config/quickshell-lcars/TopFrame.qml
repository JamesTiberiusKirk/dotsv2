import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Hyprland
import "."

// Top-screen (eDP-1) LCARS frame: elbow + bar across the top, thin spine down the left edge to the
// screen bottom, where it meets the console's stub on the screen below. Painted content only: the
// window, mask and space reservers live in Lcars.qml. `hinge` false = the lower screen is not
// directly below, so the spine ends in its own cap instead of running off the edge.
Item {
    id: tf
    required property var ship
    required property var ui
    property bool hinge: true
    property bool consoleOnline: ui.screenPresent
    // clickable areas, for the window's input mask
    readonly property alias barArea: bar
    readonly property alias spineArea: spine
    readonly property alias elbowArea: elbowShape

    readonly property int y0: Lc.pad
    readonly property int elbowW: Lc.topSpine + 70
    readonly property int elbowH: Lc.topBar + 54
    readonly property var kbd: ship.btDevices.find(d => d.icon === "keyboard" && d.connected && d.battery >= 0) ?? null
    readonly property bool red: ship.alert !== "CONDITION GREEN"
    // active Hyprland key mode (RESIZE, SWAP); "popout" is plumbing for Esc, not a mode. Replaces osd/Submap.qml's chip on the laptop panels.
    property string submap: ""
    readonly property bool mode: submap !== "" && submap !== "popout"
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "submap") tf.submap = e.data; }
    }

    component Cell: Rectangle {
        property string cap: ""
        property string value: ""
        property color ink: "black"
        property int size: 34
        signal tapped()
        Layout.fillHeight: true
        implicitWidth: Math.max(96, val.implicitWidth + 36)
        color: Lc.blue
        Label { visible: parent.cap !== ""; text: parent.cap; color: parent.ink; font.pixelSize: 12; anchors { left: parent.left; top: parent.top; leftMargin: 8; topMargin: 3 } }
        Label { id: val; text: parent.value; color: parent.ink; font.pixelSize: parent.size; anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 1 } }
        MouseArea { anchors.fill: parent; onClicked: parent.tapped() }
    }

    // ---- elbow (concave inner corner, so nothing opaque sits over windows) ----
    Shape {
        id: elbowShape
        opacity: Lc.beat
        x: Lc.pad; y: tf.y0; width: tf.elbowW; height: tf.elbowH
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            id: ep
            fillColor: Lc.orange; strokeWidth: -1
            readonly property int w: tf.elbowW
            readonly property int h: tf.elbowH
            readonly property int sp: Lc.topSpine
            readonly property int b: Lc.topBar
            startX: 0; startY: 60
            PathArc { x: 60; y: 0; radiusX: 60; radiusY: 60; direction: PathArc.Clockwise }
            PathLine { x: ep.w; y: 0 }
            PathLine { x: ep.w; y: ep.b }
            PathLine { x: ep.sp + 30; y: ep.b }
            PathArc { x: ep.sp; y: ep.b + 30; radiusX: 30; radiusY: 30; direction: PathArc.Counterclockwise }
            PathLine { x: ep.sp; y: ep.h }
            PathLine { x: 0; y: ep.h }
            PathLine { x: 0; y: 60 }
        }
    }
    Label { x: Lc.pad + 8; y: tf.y0 + tf.elbowH - 24; text: Lc.code("topelbow"); color: "black"; font.pixelSize: 14 }

    // ---- bar ----
    Item {
        id: bar
        x: Lc.pad + tf.elbowW + Lc.gap; y: tf.y0
        width: tf.width - x - Lc.pad; height: Lc.topBar
        RowLayout {
            anchors.fill: parent
            spacing: Lc.gap

            // workspaces on this screen
            Repeater {
                model: tf.ship.workspaces.filter(w => w.monitor === "eDP-1")
                Rectangle {
                    required property var modelData
                    Layout.fillHeight: true; implicitWidth: 60
                    color: modelData.urgent ? Lc.red : modelData.active ? Lc.orange : Lc.lilac
                    Label { text: modelData.name; color: "black"; font.pixelSize: 36; anchors { right: parent.right; bottom: parent.bottom; rightMargin: 10; bottomMargin: 1 } }
                    Label { text: "WS"; color: "black"; font.pixelSize: 12; anchors { left: parent.left; top: parent.top; leftMargin: 8; topMargin: 3 } }
                    MouseArea { anchors.fill: parent; onClicked: tf.ship.dispatch("hl.dsp.focus({ workspace = " + modelData.id + " })") }
                }
            }

            // stretch: dim bar, or the keep-or-revert banner while a display change is pending
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 20
                readonly property bool captured: tf.ship.computer.typing && tf.ship.confirmKind === ""   // COMPUTER chat box holds the keyboard
                color: tf.ship.confirmKind !== "" ? Lc.track : captured ? Lc.red : Lc.dim
                opacity: tf.ship.confirmKind !== "" || captured ? 1 : Lc.beat
                border.width: tf.ship.confirmKind !== "" ? 3 : 0; border.color: Lc.red
                radius: tf.ship.confirmKind !== "" ? height / 2 : 0
                Label {
                    visible: parent.captured
                    anchors.centerIn: parent
                    text: "KEYBOARD: COMPUTER  ESC TO RELEASE"; color: "black"; font.pixelSize: 24
                }
                Label {
                    visible: tf.ship.confirmKind === "" && !parent.captured
                    anchors { right: parent.right; rightMargin: 10; bottom: parent.bottom; bottomMargin: 2 }
                    text: Lc.code("topbar"); color: "black"; font.pixelSize: 16
                }
                RowLayout {
                    visible: tf.ship.confirmKind !== ""
                    anchors { fill: parent; leftMargin: 22; rightMargin: 6; topMargin: 4; bottomMargin: 4 }
                    spacing: 8
                    Label {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: "KEEP " + tf.ship.confirmText + "?  REVERTING IN " + tf.ship.confirmLeft
                        color: Lc.red; font.pixelSize: 20
                    }
                    Pill { text: "KEEP"; tint: Lc.green; Layout.preferredHeight: 40; Layout.preferredWidth: 84; implicitHeight: 40; implicitWidth: 84; labelSize: 18; onClicked: tf.ship.keepDisplay() }
                    Pill { text: "REVERT"; tint: Lc.red; Layout.preferredHeight: 40; Layout.preferredWidth: 100; implicitHeight: 40; implicitWidth: 100; labelSize: 18; onClicked: tf.ship.revertDisplay() }
                }
            }

            // active station: tap brings the console back
            Cell {
                // while a key mode is on this cell shows it instead; tap leaves the mode
                cap: tf.mode ? "MODE  TAP TO EXIT" : tf.consoleOnline ? "CONSOLE" : "LOWER DISPLAY"
                value: tf.mode ? tf.submap.toUpperCase() : tf.consoleOnline ? tf.ui.station : tf.ui.panelOpen ? "CLOSE PANEL" : "CONSOLE OFFLINE"
                color: tf.mode ? Lc.orange : tf.consoleOnline ? Lc.tan : Lc.dim
                size: 30
                onTapped: if (tf.mode) tf.ship.dispatch('hl.dsp.submap("reset")'); else if (tf.consoleOnline) { tf.ui.released = false; tf.ui.poke(); } else tf.ui.panelOpen = !tf.ui.panelOpen
            }
            Cell {
                cap: Lc.stardate(tf.ship.now)
                value: Qt.formatTime(tf.ship.now, "HH:mm")
                color: Lc.blue
            }
            Cell {
                cap: "WARP CORE"
                value: tf.ship.battery < 0 ? "--" : Math.round(tf.ship.battery) + "%"
                color: tf.ship.battery >= 0 && tf.ship.battery < 15 ? Lc.red : Lc.peach
            }
            Cell {
                cap: "DILITHIUM"
                value: tf.ship.claude < 0 ? "--" : Math.round(tf.ship.claude * 100) + "%"
                color: tf.ship.claude >= 0.9 ? Lc.red : Lc.green
            }
            Cell {
                visible: tf.kbd !== null
                cap: "KEYBOARD"
                value: tf.kbd ? tf.kbd.battery + "%" : ""
                color: tf.kbd && tf.kbd.battery < 15 ? Lc.red : Lc.sky
            }
            Cell {
                cap: tf.red ? (tf.ship.alertAcked ? "ACKNOWLEDGED" : "TAP TO ACKNOWLEDGE") : ""
                value: tf.ship.alert
                color: tf.red ? Lc.red : Lc.green
                size: 22
                implicitWidth: 210
                onTapped: tf.ship.ackAlert()
            }
            Rectangle { implicitWidth: 40; Layout.fillHeight: true; color: Lc.lilac; topRightRadius: 13; bottomRightRadius: 13; opacity: Lc.beat }
        }
    }

    // ---- spine: elbow stem, coloured blocks, then lilac to the bottom edge (matches Console's stub) ----
    // While docked (no lower screen) the blocks are the 5 station taps for the fallback panel.
    Item {
        id: spine
        x: Lc.pad; y: tf.y0
        width: Lc.topSpine
        height: tf.height - y - (tf.hinge ? 0 : Lc.pad)
        Column {
            y: tf.elbowH + Lc.gap
            width: parent.width
            spacing: Lc.gap
            readonly property real avail: spine.height - y
            readonly property var parts: tf.consoleOnline
                ? [{ w: 2, c: Lc.blue }, { w: 1, c: Lc.tan }, { w: 4, c: Lc.peach }, { w: 1, c: Lc.dim }, { w: 3, c: Lc.rose }, { w: 6, c: Lc.lilac }]
                : tf.ui.stations.map(s => ({ w: 3, c: s.tint, name: s.name })).concat([{ w: 4, c: Lc.lilac }])
            readonly property int total: parts.reduce((a, p) => a + p.w, 0)
            Repeater {
                model: parent.parts
                Rectangle {
                    id: seg
                    required property var modelData
                    required property int index
                    width: Lc.topSpine
                    height: (parent.avail - (parent.parts.length - 1) * Lc.gap) * modelData.w / parent.total
                    color: modelData.name && tf.ui.panelOpen && tf.ui.station === modelData.name ? Lc.orange : modelData.c
                    opacity: Lc.beat
                    bottomLeftRadius: index === parent.parts.length - 1 && !tf.hinge ? 30 : 0
                    Label {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 8; bottomMargin: 3 }
                        text: Lc.code("tspine" + index); color: "black"; font.pixelSize: 14
                        visible: seg.height > 24 && !modelData.name
                    }
                    // the big peach block carries the fixed title, rotated; docked blocks carry the station name
                    Label {
                        visible: tf.consoleOnline ? index === 2 : !!modelData.name
                        anchors.centerIn: parent; rotation: -90
                        text: modelData.name ?? "FORWARD STATION"; color: "black"; font.pixelSize: modelData.name ? 20 : 24
                    }
                    MouseArea { anchors.fill: parent; enabled: !!modelData.name; onClicked: tf.ui.tapStation(modelData.name) }
                }
            }
        }
    }
}
