import QtQuick

// One page of the popout card in bar/PopoutHost.qml. This used to be a
// window per popout, which could not morph into each other (a window
// per page, one swap = one closes and one maps) and cost a Hyprland configure
// on every resize. Now it is a plain Item the host shows, sizes and hangs off
// its cell.
//
// A popout still declares what is actually different about it: its name, the
// bar button it hangs off, its width. It puts its rows inside. Everything
// below is the same for all of them.
//
// Deliberately NOT configurable: the card look, the entrance animation, the
// keyboard scheme, and the tab style. One of each. The only tab knob is
// whether there are tabs at all.
Item {
    id: root

    // ---- required ----
    // The bar's panel. Supplies the geometry helpers (vertical, attachedPanelX),
    // the registry this joins and showPage(). Passed in rather than reached
    // for, so a popout can live in its own file.
    //
    // Named `bar`, not `panel`: the bar declares `id: panel`, so a property of
    // that name shadows the id at the use site — `panel: panel` binds the
    // popout to itself, it registers nowhere and never opens.
    property var bar
    // The bar button this points at. The neck animation grows out of it and
    // the card centres on it. A hidden cell is never used: the host falls back
    // to the control center cell.
    property Item cell
    // Registry key. The menu row is "bar/<panelName>", and Sys.openPanel takes
    // the same string. Not `name`: several Qt types already own that.
    property string panelName

    // ---- options, each one backed by variation that already exists ----
    // width is implicitWidth, the card is exactly that wide; in use today: 240..360
    property int rowSpacing: 8              // 8 is the common case; 2, 6 and 10 exist
    property string heading: ""             // calendar and docker/vm draw one, the rest do not
    property var tabs: []                   // empty: no chips, behaves exactly as before
    // InputFields currently showing in this popout; they count themselves in
    // and out. While any is up the host takes the keyboard even when the
    // menu did not open it (see PopoutHost.grabbing for why only then).
    // A count, not a flag, so two fields in one popout cannot undo each other.
    property int inputs: 0

    // ---- state ----
    // set by the host only (PopoutHost.show/close); side effects hang off onOpenChanged
    property bool open: false
    // set by the host: reached through the control center, so draw the back row
    property bool back: false
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

    // Reopening starts back at the first tab only if the current one vanished
    // (a tab list can be conditional); otherwise the tab you left it on sticks.
    onTabsChanged: if (tabs.length > 0 && tabs.indexOf(currentTab) < 0) currentTab = tabs[0];

    // back to the control center of this page's group (the sys page for docker, system, agents)
    function goBack() { root.bar.showPage(ShellState.ccName(ShellState.groupOf(root.panelName)), true); }

    // The card is exactly this big. implicitWidth is the per-popout knob and
    // the 14px padding sits inside it, so contentWidth is what it always was.
    // implicitHeight stays live while closed (the page is hidden but still in
    // the tree), which is how the host measures it before the swap.
    width: implicitWidth
    implicitWidth: 320
    implicitHeight: col.implicitHeight + 28
    height: implicitHeight
    visible: open
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InQuad } }

    Column {
        id: col
        x: 14; y: 14
        width: root.width - 28
        spacing: root.rowSpacing

        // reached through the control center: the way back. Not a tab stop,
        // Esc is the keyboard way back.
        Item {
            visible: root.back
            width: col.width
            height: 18
            Row {
                spacing: 6
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-left"; size: 14; color: Theme.dim }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.heading !== "" ? root.heading : root.panelName
                    font.family: Theme.font; font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Theme.bright
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.goBack() }
        }

        Text {
            visible: root.heading !== ""
            text: root.heading
            font.family: Theme.font; font.pixelSize: 11
            font.weight: Font.DemiBold
            color: Theme.bright
        }

        // One tab stop for the whole row, arrows / h / l switch, three
        // chips would otherwise cost three j/k presses before the content.
        Item {
            id: tabRow
            visible: root.tabs.length > 0
            width: col.width
            height: 22
            activeFocusOnTab: visible
            Keys.onLeftPressed: tabRow.hstep(-1)
            Keys.onRightPressed: tabRow.hstep(1)
            // the card routes h/l to the focused item's hstep()
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
