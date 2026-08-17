import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "../common"

// Screen bezel: solid side and bottom bands that reserve space, molded into
// the bar's top band. Inner corners get the same concave fillets as the
// notches. The top band + top corners are drawn by Bar.qml.
Variants {
    model: Quickshell.screens

    delegate: Scope {
        id: scope

        required property var modelData

        component SideBand: PanelWindow {
            id: side

            property bool rightSide: false
            screen: scope.modelData
            anchors { top: true; bottom: true; left: !rightSide; right: rightSide }
            margins { bottom: Theme.frameFillet } // bottom strip's fillets take over
            implicitWidth: Theme.frameT
            color: "transparent"
            WlrLayershell.namespace: "quickshell-frame"

            Rectangle { anchors.fill: parent; color: Theme.island }
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom }
                x: side.rightSide ? 0 : Theme.frameT - 1
                width: 1
                color: Theme.islandBorder
            }
        }

        // bottom strip maps FIRST so it spans the full screen width — the side
        // bands' reserved zones would otherwise inset it away from the corners
        PanelWindow {
            screen: scope.modelData
            anchors { left: true; right: true; bottom: true }
            implicitHeight: Theme.frameT + Theme.frameFillet
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: Theme.frameT
            color: "transparent"
            WlrLayershell.namespace: "quickshell-frame"

            // Shape + rects, not Canvas: Canvas AA edges composite with a
            // premultiply mismatch on nvidia (dark fringe around path edges)
            Item {
                id: bottomChrome
                anchors.fill: parent
                readonly property real bT: Theme.frameT
                readonly property real bf: Theme.frameFillet
                readonly property real bW: width

                // band + side stubs
                Rectangle { y: bottomChrome.bf; width: bottomChrome.bW; height: bottomChrome.bT; color: Theme.island }
                Rectangle { width: bottomChrome.bT; height: parent.height; color: Theme.island }
                Rectangle { x: bottomChrome.bW - bottomChrome.bT; width: bottomChrome.bT; height: parent.height; color: Theme.island }

                // band top line between the fillets
                Rectangle {
                    x: bottomChrome.bT + bottomChrome.bf; y: bottomChrome.bf
                    width: bottomChrome.bW - 2 * (bottomChrome.bT + bottomChrome.bf); height: 1
                    color: Theme.islandBorder
                }

                // concave fillets
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: "transparent"; fillColor: Theme.island
                        startX: bottomChrome.bT; startY: 0
                        PathArc { x: bottomChrome.bT + bottomChrome.bf; y: bottomChrome.bf; radiusX: bottomChrome.bf; radiusY: bottomChrome.bf; direction: PathArc.Counterclockwise }
                        PathLine { x: bottomChrome.bT; y: bottomChrome.bf }
                    }
                    ShapePath {
                        strokeColor: Theme.islandBorder; strokeWidth: 1; fillColor: "transparent"
                        startX: bottomChrome.bT; startY: 0
                        PathArc { x: bottomChrome.bT + bottomChrome.bf; y: bottomChrome.bf; radiusX: bottomChrome.bf; radiusY: bottomChrome.bf; direction: PathArc.Counterclockwise }
                    }
                    ShapePath {
                        strokeColor: "transparent"; fillColor: Theme.island
                        startX: bottomChrome.bW - bottomChrome.bT; startY: 0
                        PathArc { x: bottomChrome.bW - bottomChrome.bT - bottomChrome.bf; y: bottomChrome.bf; radiusX: bottomChrome.bf; radiusY: bottomChrome.bf }
                        PathLine { x: bottomChrome.bW - bottomChrome.bT; y: bottomChrome.bf }
                    }
                    ShapePath {
                        strokeColor: Theme.islandBorder; strokeWidth: 1; fillColor: "transparent"
                        startX: bottomChrome.bW - bottomChrome.bT; startY: 0
                        PathArc { x: bottomChrome.bW - bottomChrome.bT - bottomChrome.bf; y: bottomChrome.bf; radiusX: bottomChrome.bf; radiusY: bottomChrome.bf }
                    }
                }
            }

        }

        SideBand {}
        SideBand { rightSide: true }
    }
}
