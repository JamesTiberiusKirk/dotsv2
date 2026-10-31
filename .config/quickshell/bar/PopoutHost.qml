import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../common"

// The one card window per screen. Every popout page (common/Popout.qml) lives
// inside it, and showing a different page retargets the card's size and
// position instead of closing one window and mapping another, so pages morph
// into each other along the bar.
//
// The window is the screen minus the bar strip, fixed size, never resized: a
// resize is a Hyprland configure per frame. It is transparent and masked to
// the card, so clicks outside the card fall through to the dismiss layer in
// Bar.qml exactly as before. Namespace stays quickshell-popout: the blur rule
// there only blurs the card's own pixels.
PanelWindow {
    id: host

    required property var bar
    // the control center pages by group ({ status: <cc>, sys: <cc-sys> }); a page
    // reached through the control center hangs off its own group's page's cell
    property var homes: ({})
    // every Popout page is declared inside this
    default property alias pages: pagesItem.data
    // the page showing (a Popout)
    property Popout page: null
    property bool open: false
    // page reached through the control center: hang off the CC cell, draw back
    property bool viaCC: false
    // A popout takes the keyboard only when the menu opened it (Sys.kbdNav) or
    // while an InputField is up. One that always wants keys is the network
    // popout bug (see its own file): Hyprland focuses a layer the moment it
    // maps, and with the pointer still on the cell that focus never comes
    // back for the second, closing click.
    readonly property bool grabbing: open && (Sys.kbdNav || (page ? page.inputs > 0 : false))

    // Swap to page p (or open it). `via`: reached through the control center.
    function show(p, via) {
        // a page whose own cell is hidden has nothing to hang off: its group's CC cell stands in
        via = via || !(p.cell && p.cell.visible);
        if (page && page !== p) page.open = false;
        // all of this runs before `open` goes true, so the Behaviors below are
        // still off and a fresh open snaps to place instead of sliding in from
        // wherever the last page closed
        viaCC = via;
        p.back = via && !isHome(p);
        page = p;
        p.open = true;
        // From closed, the window was unmapped, so the page gets its real
        // layout only in the first frame after mapping. Animating that would
        // grow the card from a stale height; hold the Behaviors off until it lands.
        if (!open) { settled = false; settle.restart(); }
        open = true;
        card.refocus();
    }
    // is p one of the control center pages (they have no back row)
    function isHome(p) { return Object.values(homes).includes(p); }
    // page and viaCC are kept: the geometry must not jump during the exit fade
    function close() { if (page) page.open = false; open = false; settled = false; }

    // morph Behaviors run only once a fresh open has laid out (see show)
    property bool settled: false
    Timer { id: settle; interval: 50; onTriggered: host.settled = true }

    visible: open
    screen: bar.screen
    anchors { top: true; bottom: true; left: true; right: true }
    // The strip the bar and the gap take, on the bar's side only. The old
    // per-popout windows sat at the same screen position (barHeight + gap from
    // that edge), so inside the host a near-side card is at 0 on the cross axis.
    margins {
        top:    ShellState.side === "top"    ? bar.barHeight + Theme.popoutGap : 0
        bottom: ShellState.side === "bottom" ? bar.barHeight + Theme.popoutGap : 0
        left:   ShellState.side === "left"   ? bar.barHeight + Theme.popoutGap : 0
        right:  ShellState.side === "right"  ? bar.barHeight + Theme.popoutGap : 0
    }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-popout"
    WlrLayershell.keyboardFocus: grabbing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    // Plain geometry, not `item: card`: an item region maps through the card's
    // entrance Scale and is snapshotted mid-grow (0.75x around the neck), so the
    // far side of the card let clicks fall through to the dismiss layer.
    mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }
    HyprlandFocusGrab { windows: [host]; active: host.grabbing; onCleared: host.close() }

    // viaCC: the page's group CC cell is the anchor; the page itself if that group has none declared
    readonly property Popout anchorPage: viaCC && page ? (homes[ShellState.groupOf(page.panelName)] ?? page) : page
    readonly property real anchorX: anchorPage ? anchorPage.sourceX : 0
    readonly property real anchorW: anchorPage ? anchorPage.sourceWidth : 0
    readonly property real cardW: page ? page.implicitWidth : 0
    readonly property real cardH: page ? page.implicitHeight : 0
    // Along the bar. The host spans the bar's full length and starts at the
    // screen edge on that axis (only the cross-axis margin is non-zero), so
    // these are the same coordinates the bar's attachedPanelX works in.
    readonly property real along: bar.attachedPanelX(anchorX, anchorW, bar.vertical ? cardH : cardW)

    AttachedPanel {
        id: card
        // cross axis: against the bar side of the host (far: against the opposite edge, which is the bar's)
        x: bar.vertical ? (bar.far ? host.width - host.cardW : 0) : host.along
        y: bar.vertical ? host.along : (bar.far ? host.height - host.cardH : 0)
        width: host.cardW
        height: host.cardH
        // morph: only once settled. A fresh open snaps to place and plays the entrance instead.
        Behavior on x { enabled: host.settled; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: host.settled; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: host.settled; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: host.settled; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        shown: host.open
        keyNav: host.open && Sys.kbdNav
        vertical: bar.vertical
        far: bar.far
        // pages carry their own 14px
        padding: 0
        neckX: host.anchorX - host.along
        neckWidth: host.anchorW
        // Esc inside the card steps back out of a control center detail page,
        // else closes. Esc through the submap or the dismiss layer closes all.
        onEscaped: host.page && host.page.back ? host.page.goBack() : Sys.closeAll()
        Item { id: pagesItem; anchors.fill: parent }
    }
}
