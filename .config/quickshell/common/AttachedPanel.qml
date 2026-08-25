import QtQuick

// Popup panel for the bar islands. No neck: the panel reads as its own card,
// and the tab that used to bridge it to the island only ever half-lined-up
// with the island edge. neckX/neckWidth survive as the anchor the entrance
// animation grows from, so a popout still expands out of its own trigger.
Item {
    id: root

    default property alias content: content.data

    property bool shown: true
    property real neckX: 20
    property real neckWidth: 48
    property int radius: 12
    property int padding: 14

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    // grow out of the island: scale anchored where the trigger sits, slight
    // overshoot. Clamped, since a trigger near the screen edge gets a panel
    // shifted away from it and the raw x would land outside the card.
    transform: Scale {
        origin.x: root.clamp(root.neckX + root.neckWidth / 2, 0, root.width)
        origin.y: 0
        xScale: root.shown ? 1 : 0.75
        yScale: root.shown ? 1 : 0.75
        Behavior on xScale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        Behavior on yScale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.island
        border.width: 1
        border.color: Theme.islandBorder
    }

    Item {
        id: content

        anchors {
            fill: parent
            margins: root.padding
        }
    }
}
