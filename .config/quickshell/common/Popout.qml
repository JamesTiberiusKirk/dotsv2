import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The shell every bar popout is made of. Before this, each of the twelve
// hand-rolled the same eighteen lines of PanelWindow plumbing and registered
// itself in five separate lists by hand, so adding one meant editing six
// places and forgetting one of them was the usual bug.
//
// A popout now declares what is actually different about it — its name, its
// icon, the bar button it hangs off, its width — and puts its rows inside.
// Everything below is the same for all of them.
//
// Deliberately NOT configurable: the card look, the entrance animation, the
// keyboard scheme, and the tab style. One of each. The only tab knob is
// whether there are tabs at all.
PanelWindow {
    id: root

    // ---- required ----
    // The bar's panel. Supplies the geometry helpers (vertical, attachedPanelX,
    // popoutTop/Left, navOn/navFocus) and the registry this joins. Passed in
    // rather than reached for, so a popout can live in its own file.
    //
    // Named `bar`, not `panel`: the bar declares `id: panel`, so a property of
    // that name shadows the id at the use site — `panel: panel` binds the
    // popout to itself, it registers nowhere and never opens.
    property var bar
    // The bar button this points at. The neck animation grows out of it and
    // the card centres on it.
    property Item cell
    // Registry key. The menu row is "bar/<panelName>", and Sys.openPanel takes
    // the same string. Not `name`: several Qt types already own that.
    property string panelName

    // ---- options, each one backed by variation that already exists ----
    // width is implicitWidth, PanelWindow's own; in use today: 240..360
    property int rowSpacing: 8              // 8 is the common case; 2, 6 and 10 exist
    property string heading: ""             // calendar and docker/vm draw one, the rest do not
    property var tabs: []                   // empty: no chips, behaves exactly as before
    // InputFields currently showing in this popout; they count themselves in
    // and out. While any is up the popout takes the keyboard even when the
    // menu did not open it. Only then: a popout that always asks for keys
    // cannot be closed by a second click on its own cell, because Hyprland
    // focuses a layer the moment it maps and that focus never returns to the bar.
    // A count, not a flag, so two fields in one popout cannot undo each other.
    property int inputs: 0

    // ---- state ----
    property bool open: false
    property string currentTab: tabs.length > 0 ? tabs[0] : ""

    default property alias content: col.data
    // Rows size themselves off this. `parent.width` works for a direct child,
    // but not inside an inline `component` declared at column level, which is
    // where the taller popouts keep their row types.
    readonly property alias contentWidth: col.width

    // Offset of `cell` along the bar's axis, by walking up to the window.
    // Replaces the per-popout `bar.pos(row) + bar.pos(island) + bar.pos(cell)`,
    // which spelled out the containers by hand and so had to be rewritten for
    // every new popout.
    //
    // Reactive on purpose: a QML binding captures every property read while it
    // evaluates, including inside a called function, so this re-runs when any
    // ancestor moves — which is what happens when the bar flips vertical or a
    // cell hides. `mapToItem` would give the same number once and then go
    // stale, which is why it is not used here.
    function offsetOf(it) {
        let v = 0;
        for (let n = it; n; n = n.parent)
            v += root.bar.vertical ? n.y : n.x;
        return v;
    }

    readonly property real sourceX: root.cell ? root.offsetOf(root.cell) : 0
    readonly property real sourceWidth: root.cell ? (root.bar.vertical ? root.cell.height : root.cell.width) : 0
    readonly property real popupX: root.bar.attachedPanelX(
        sourceX, sourceWidth, root.bar.vertical ? implicitHeight : implicitWidth)

    // Reopening starts back at the first tab only if the current one vanished
    // (a tab list can be conditional); otherwise the tab you left it on sticks.
    onTabsChanged: if (tabs.length > 0 && tabs.indexOf(currentTab) < 0) currentTab = tabs[0];

    visible: open
    screen: bar.screen
    anchors { top: true; left: true }
    margins {
        top: bar.popoutTop(popupX, implicitWidth, implicitHeight)
        left: bar.popoutLeft(popupX, implicitWidth, implicitHeight)
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-popout"
    readonly property bool grabbing: bar.navOn(root) || (open && inputs > 0)
    WlrLayershell.keyboardFocus: grabbing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    implicitWidth: 320
    implicitHeight: col.implicitHeight + 28
    color: "transparent"

    HyprlandFocusGrab {
        windows: [root]
        active: root.grabbing
        onCleared: root.open = false
    }

    AttachedPanel {
        anchors.fill: parent
        shown: root.open
        keyNav: root.bar.navOn(root)
        neckX: root.sourceX - root.popupX
        neckWidth: root.sourceWidth

        Column {
            id: col
            width: parent.width
            spacing: root.rowSpacing

            Text {
                visible: root.heading !== ""
                text: root.heading
                font.family: Theme.font; font.pixelSize: 11
                font.weight: Font.DemiBold
                color: Theme.bright
            }

            // One tab stop for the whole row, arrows / h / l switch — three
            // chips would otherwise cost three j/k presses before the content.
            Item {
                id: tabRow
                visible: root.tabs.length > 0
                width: col.width
                height: 22
                activeFocusOnTab: visible
                Keys.onLeftPressed: tabRow.hstep(-1)
                Keys.onRightPressed: tabRow.hstep(1)
                // AttachedPanel routes h/l to the focused item's hstep()
                function hstep(d) {
                    const i = root.tabs.indexOf(root.currentTab);
                    root.currentTab = root.tabs[(i + d + root.tabs.length) % root.tabs.length];
                }

                Rectangle {
                    anchors { fill: parent; margins: -3 }
                    radius: 5
                    color: tabRow.activeFocus ? Theme.track : "transparent"
                }
                Row {
                    spacing: 14
                    Repeater {
                        model: root.tabs
                        Item {
                            required property var modelData
                            readonly property bool on: modelData === root.currentTab
                            width: chip.width; height: 22
                            Text {
                                id: chip
                                text: modelData
                                font.family: Theme.font; font.pixelSize: 11
                                font.bold: parent.on
                                color: parent.on ? Theme.bright : Theme.dim
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 2
                                color: Theme.accent
                                visible: parent.on
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.currentTab = modelData }
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: Theme.track
                }
            }
        }
    }
}
