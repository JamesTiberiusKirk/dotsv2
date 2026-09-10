import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes
import "../common"

// Top-centre chip: the active Hyprland submap (RESIZE, SWAP). Hangs down
// from the top frame band while a mode is on, on the focused screen. The
// capsule is drawn by the chrome (bar/Chrome.qml), same as the bottom OSD;
// over a fullscreen window the chrome is hidden, so the chip paints its own.
Scope {
    id: sub

    property string submap: ""
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "submap") sub.submap = e.data; }
    }
    // the popout submap is plumbing for Esc, not a mode
    readonly property bool on: submap !== "" && submap !== "popout"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData

            screen: modelData
            anchors { top: true }
            readonly property bool fullscreen: Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen ?? false
            // no band over a fullscreen window: the capsule starts at the edge
            readonly property int nT: fullscreen ? 0 : ShellState.bandT("top")
            readonly property int nf: 8
            readonly property int cr: 14
            readonly property bool on: sub.on && Hyprland.focusedMonitor?.name === screen.name
            readonly property int cardW: Math.max(160, label.implicitWidth + 48)
            readonly property int cardH: on ? 36 : 0

            implicitWidth: 320 + 2 * nf
            implicitHeight: 36 + Theme.frameT
            mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            visible: card.height > nT
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-submap"

            Item {
                id: card
                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                width: root.cardW + 2 * root.nf
                height: root.cardH + root.nT
                clip: true
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                function publish() { ShellState.setTop(root.screen.name, [width - 2 * root.nf, height - root.nT]); }
                onWidthChanged: publish()
                onHeightChanged: publish()
                Component.onCompleted: publish()

                // the OSD capsule (osd/Osd.qml), hanging from the top band
                Shape {
                    id: capsule
                    anchors.fill: parent
                    visible: root.fullscreen
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real cw: card.width - 2 * root.nf
                    readonly property real bb: root.nT               // band bottom
                    readonly property real h: card.height
                    readonly property real f: Math.min(root.nf, (h - bb) / 2)
                    readonly property real c: Math.min(root.cr, h - bb - f)
                    component Outline: ShapePath {
                        startX: 0; startY: capsule.bb
                        PathArc { x: root.nf; y: capsule.bb + capsule.f; radiusX: root.nf; radiusY: capsule.f }
                        PathLine { x: root.nf; y: capsule.h - capsule.c }
                        PathArc { x: root.nf + capsule.c; y: capsule.h; radiusX: capsule.c; radiusY: capsule.c; direction: PathArc.Counterclockwise }
                        PathLine { x: root.nf + capsule.cw - capsule.c; y: capsule.h }
                        PathArc { x: root.nf + capsule.cw; y: capsule.h - capsule.c; radiusX: capsule.c; radiusY: capsule.c; direction: PathArc.Counterclockwise }
                        PathLine { x: root.nf + capsule.cw; y: capsule.bb + capsule.f }
                        PathArc { x: card.width; y: capsule.bb; radiusX: root.nf; radiusY: capsule.f }
                    }
                    Outline { strokeColor: "transparent"; fillColor: Theme.island }
                    Outline { strokeColor: Theme.islandBorder; strokeWidth: 1; fillColor: "transparent" }
                }

                // the chip body: below the band, inside the fillets
                Item {
                    anchors { fill: parent; topMargin: root.nT; leftMargin: root.nf; rightMargin: root.nf }
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: sub.submap.toUpperCase()
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 4
                        font.bold: true
                        font.letterSpacing: 2
                        color: Theme.urgent
                    }
                }
            }
        }
    }
}
