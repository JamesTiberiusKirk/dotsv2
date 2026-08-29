import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "../common"

// Screen bezel: solid bands that reserve space on the three edges the bar is
// not on, molded into the bar's own band. Inner corners get the same concave
// fillets as the notches. The bar's edge (band + its corners) is drawn by
// Bar.qml; ShellState.side says which one that is.
Variants {
    model: Quickshell.screens

    delegate: Scope {
        id: scope

        required property var modelData

        // Reservation lives in these invisible windows so the visible chrome
        // can ignore every exclusive zone: a strip that respects the side
        // band's zone (or vice versa, map order is a race on side switches)
        // stops short of the screen corner and leaves a hole there.
        component Reserver: PanelWindow {
            property string edge
            screen: scope.modelData
            visible: ShellState.side !== edge
            anchors { top: edge !== "bottom"; bottom: edge !== "top"; left: edge !== "right"; right: edge !== "left" }
            implicitWidth: Theme.frameT
            implicitHeight: Theme.frameT
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: Theme.frameT
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "quickshell-frame"
        }

        component SideBand: PanelWindow {
            id: side

            property bool rightSide: false
            screen: scope.modelData
            visible: ShellState.side !== (rightSide ? "right" : "left")
            anchors { top: true; bottom: true; left: !rightSide; right: rightSide }
            // the strips' fillets take over at the corners they own
            margins {
                bottom: ShellState.side === "bottom" ? 0 : Theme.frameFillet
                top: ShellState.side === "top" ? 0 : Theme.frameFillet
            }
            implicitWidth: Theme.frameT
            exclusionMode: ExclusionMode.Ignore
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

        // strips map FIRST so they span the full screen width — the side
        // bands' reserved zones would otherwise inset them away from the corners
        component EdgeStrip: PanelWindow {
            id: strip
            property bool topSide: false
            visible: ShellState.side !== (topSide ? "top" : "bottom")
            screen: scope.modelData
            anchors { left: true; right: true; bottom: !topSide; top: topSide }
            implicitHeight: Theme.frameT + Theme.frameFillet
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "quickshell-frame"

            // Shape + rects, not Canvas: Canvas AA edges composite with a
            // premultiply mismatch on nvidia (dark fringe around path edges)
            Item {
                id: bottomChrome
                anchors.fill: parent
                // drawn as the bottom strip, flipped for the top one
                transform: Scale { origin.y: bottomChrome.height / 2; yScale: strip.topSide ? -1 : 1 }
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

                // rounded screen corners: black outside the arc
                Shape {
                    id: corners
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real r: Theme.frameRadius
                    readonly property real h: bottomChrome.height
                    ShapePath {
                        strokeColor: "transparent"; fillColor: Theme.bezel
                        startX: 0; startY: corners.h - corners.r
                        PathLine { x: 0; y: corners.h }
                        PathLine { x: corners.r; y: corners.h }
                        PathArc { x: 0; y: corners.h - corners.r; radiusX: corners.r; radiusY: corners.r }
                    }
                    ShapePath {
                        strokeColor: "transparent"; fillColor: Theme.bezel
                        startX: bottomChrome.bW; startY: corners.h - corners.r
                        PathLine { x: bottomChrome.bW; y: corners.h }
                        PathLine { x: bottomChrome.bW - corners.r; y: corners.h }
                        PathArc { x: bottomChrome.bW; y: corners.h - corners.r; radiusX: corners.r; radiusY: corners.r; direction: PathArc.Counterclockwise }
                    }
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

        Reserver { edge: "top" }
        Reserver { edge: "bottom" }
        Reserver { edge: "left" }
        Reserver { edge: "right" }
        EdgeStrip {}
        EdgeStrip { topSide: true }
        SideBand {}
        SideBand { rightSide: true }
    }
}
