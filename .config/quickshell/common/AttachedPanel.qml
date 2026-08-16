import QtQuick
import QtQuick.Shapes

// Popup panel with a "neck" tab that visually attaches it to a bar island.
// GPU-rendered Shape (not Canvas) so every animated property stays buttery:
// the entrance is transform-only (scale from the neck + fade), composited
// from cached textures — no per-frame rasterization.
Item {
    id: root

    default property alias content: content.data

    property bool shown: true
    property real neckX: 20
    property real neckWidth: 48
    property int neckHeight: 9
    property int radius: 12
    property int padding: 14

    // panel geometry (mirrors the old Canvas path, now declarative/animatable)
    readonly property real r: Math.min(radius, width / 2, (height - neckHeight) / 2)
    readonly property real minNeckW: Math.min(24, Math.max(0, width - 2 * r))
    readonly property real nLeft: clamp(neckX, r, width - r - minNeckW)
    readonly property real nRight: clamp(neckX + neckWidth, nLeft + minNeckW, width - r)
    readonly property real f: Math.min(8, neckHeight, (nRight - nLeft) / 2)

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    // grow out of the island: scale anchored at the neck, slight overshoot
    transform: Scale {
        origin.x: root.nLeft + (root.nRight - root.nLeft) / 2
        origin.y: 0
        xScale: root.shown ? 1 : 0.75
        yScale: root.shown ? 1 : 0.75
        Behavior on xScale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on yScale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Theme.islandBorder
            fillColor: Theme.island

            startX: root.nLeft; startY: 0
            PathLine { x: root.nRight; y: 0 }
            PathQuad {
                x: Math.min(root.width - root.r, root.nRight + root.f); y: root.neckHeight
                controlX: root.nRight; controlY: root.neckHeight
            }
            PathLine { x: root.width - root.r; y: root.neckHeight }
            PathQuad {
                x: root.width; y: root.neckHeight + root.r
                controlX: root.width; controlY: root.neckHeight
            }
            PathLine { x: root.width; y: root.height - root.r }
            PathQuad {
                x: root.width - root.r; y: root.height
                controlX: root.width; controlY: root.height
            }
            PathLine { x: root.r; y: root.height }
            PathQuad {
                x: 0; y: root.height - root.r
                controlX: 0; controlY: root.height
            }
            PathLine { x: 0; y: root.neckHeight + root.r }
            PathQuad {
                x: root.r; y: root.neckHeight
                controlX: 0; controlY: root.neckHeight
            }
            PathLine { x: Math.max(root.r, root.nLeft - root.f); y: root.neckHeight }
            PathQuad {
                x: root.nLeft; y: 0
                controlX: root.nLeft; controlY: root.neckHeight
            }
        }
    }

    Item {
        id: content

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            topMargin: root.neckHeight + root.padding
            leftMargin: root.padding
            rightMargin: root.padding
            bottomMargin: root.padding
        }
    }
}
