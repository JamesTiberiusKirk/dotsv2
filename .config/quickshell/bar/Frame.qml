import Quickshell
import Quickshell.Wayland
import QtQuick
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

            Canvas {
                id: bottomBand
                anchors.fill: parent

                onPaint: {
                    const ctx = getContext("2d");
                    const T = Theme.frameT, f = Theme.frameFillet;
                    const W = width, H = height;
                    ctx.reset();

                    // band + side stubs + concave fillets, one fill op
                    ctx.beginPath();
                    ctx.rect(0, f, W, T);
                    ctx.rect(0, 0, T, H);
                    ctx.rect(W - T, 0, T, H);
                    ctx.moveTo(T, 0);
                    ctx.arc(T + f, 0, f, Math.PI, 0.5 * Math.PI, true);
                    ctx.lineTo(T, f);
                    ctx.closePath();
                    ctx.moveTo(W - T, 0);
                    ctx.arc(W - T - f, 0, f, 0, 0.5 * Math.PI, false);
                    ctx.lineTo(W - T, f);
                    ctx.closePath();
                    ctx.fillStyle = Theme.island;
                    ctx.fill();

                    // inner border: fillet arcs + band top line
                    ctx.beginPath();
                    ctx.moveTo(T, 0);
                    ctx.arc(T + f, 0, f, Math.PI, 0.5 * Math.PI, true);
                    ctx.moveTo(T + f, f + 0.5);
                    ctx.lineTo(W - T - f, f + 0.5);
                    ctx.moveTo(W - T, 0);
                    ctx.arc(W - T - f, 0, f, 0, 0.5 * Math.PI, false);
                    ctx.strokeStyle = Theme.islandBorder;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                }

                Connections {
                    target: Theme
                    function onModeChanged() { bottomBand.requestPaint(); }
                }
            }
        }

        SideBand {}
        SideBand { rightSide: true }
    }
}
