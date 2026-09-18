import QtQuick
import QtQuick.Window

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

    // Keyboard nav, on only while the popout was opened from the menu
    // (Sys.kbdNav). j/k walk Qt's own focus chain, so declaration order is the
    // order and nothing here keeps an index in sync with Repeaters that come
    // and go. Rows opt in with activeFocusOnTab and answer Return themselves;
    // Tab/Shift+Tab work for free, j/k are the same walk under vim keys.
    property bool keyNav: false
    focus: keyNav
    onKeyNavChanged: if (keyNav) Qt.callLater(() => root.step(true));
    function step(fwd) {
        // Window.activeFocusItem, not the PanelWindow's: PanelWindow is a
        // Quickshell wrapper, not a QQuickWindow, so that property is
        // undefined and every step restarts the walk from the top.
        const next = (root.Window.activeFocusItem || content).nextItemInFocusChain(fwd);
        if (next) next.forceActiveFocus(Qt.TabFocusReason);
    }
    // Rows consume only the keys they act on (Return, Left/Right on a slider),
    // so everything else bubbles up to here from whatever holds focus.
    // h/l are the vim half of Left/Right and reach the focused row the same
    // way j/k reach the focus chain: a row opts in by declaring hstep(dir),
    // which its own Left/Right handlers already call. Rows without one (a
    // toggle, a trailing icon) simply ignore the key.
    Keys.onPressed: e => {
        if (!root.keyNav) return;
        if (e.key === Qt.Key_J || e.key === Qt.Key_Down) root.step(true);
        else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) root.step(false);
        else if (e.key === Qt.Key_H || e.key === Qt.Key_L) {
            const it = root.Window.activeFocusItem;
            if (it && typeof it.hstep === "function") it.hstep(e.key === Qt.Key_L ? 1 : -1);
        }
        else if (e.key === Qt.Key_Escape) Sys.closeAll();
        else return;
        e.accepted = true;
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
