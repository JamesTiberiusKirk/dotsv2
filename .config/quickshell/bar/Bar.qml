import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts
import "../common"
import "popouts"

Variants {
    model: Quickshell.screens

    delegate: Component {
        Scope {
            id: barScope
            required property var modelData
        // declared first so it maps first: the chrome is the cells' background
        Chrome { bar: panel }
        PanelWindow {
            id: panel

            screen: barScope.modelData
            // ShellState.side picks the edge. The bar owns the frame band on
            // whichever edge it sits on (Frame.qml drops its strip there), so
            // the capsules hang off the band the same way on every side.
            readonly property bool vertical: ShellState.vertical
            readonly property bool far: ShellState.far
            anchors {
                top: vertical || ShellState.side === "top"
                bottom: vertical || ShellState.side === "bottom"
                left: !vertical || ShellState.side === "left"
                right: !vertical || ShellState.side === "right"
            }
            // A side switch unmaps the layer, moves it, maps it again: flipping
            // the anchors of a mapped layer surface has crashed Hyprland.
            // The chrome (Chrome.qml) remaps a beat before the bar so it stacks
            // below it, as it does at startup (declared first).
            property bool mapped: true
            property bool chromeMapped: true
            visible: mapped
            Connections {
                target: ShellState
                function onSideChanged() {
                    panel.closeIslandPopouts();
                    panel.mapped = false;
                    panel.chromeMapped = false;
                    remapChrome.start();
                }
            }
            Timer { id: remapChrome; interval: 80; onTriggered: { panel.chromeMapped = true; remap.start(); } }
            Timer { id: remap; interval: 60; onTriggered: panel.mapped = true }

            readonly property int barBodyHeight: ShellState.barBody
            readonly property int barHeight: barBodyHeight
            // island offset inside the window on the cross axis (the band is at
            // the far edge of the window on right/bottom), and from the screen
            // corners along the bar
            readonly property int edgeIn: 0
            // 0: the end islands run into the screen corners and are capped
            // there (see the capsule Shape) — corner-most edge is the screen
            // edge itself, so island and frame are one piece
            readonly property int gutter: 0
            readonly property real along: vertical ? height : width
            // Chrome (capsules, band, fillets) is drawn once in top-bar
            // coordinates — x along the bar, y inward from the edge — and this
            // maps it onto the actual edge: mirrored for bottom, transposed
            // for left, transposed + mirrored for right.
            readonly property matrix4x4 chromeMatrix: {
                const T = barHeight;
                switch (ShellState.side) {
                case "bottom": return Qt.matrix4x4(1, 0, 0, 0,  0, -1, 0, T,  0, 0, 1, 0,  0, 0, 0, 1);
                case "left":   return Qt.matrix4x4(0, 1, 0, 0,  1, 0, 0, 0,   0, 0, 1, 0,  0, 0, 0, 1);
                case "right":  return Qt.matrix4x4(0, -1, 0, T, 1, 0, 0, 0,   0, 0, 1, 0,  0, 0, 0, 1);
                default:       return Qt.matrix4x4();
                }
            }
            // main-axis position / extent of a bar item, whichever axis the bar runs on
            function pos(it) { return vertical ? it.y : it.x; }
            function ext(it) { return vertical ? it.height : it.width; }

            implicitHeight: barHeight
            implicitWidth: barHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            // hidden: islands slide up into the band and fade, windows reclaim
            // the bar body; the thin frame stays (Chrome.qml)
            exclusiveZone: ShellState.hidden ? Theme.frameT : barHeight
            // hidden: windows reclaim the bar body, so drop the input region
            // too — otherwise the invisible surface eats clicks in that strip
            mask: Region {
                width: ShellState.hidden ? 0 : (panel.vertical ? panel.barHeight : panel.width)
                height: ShellState.hidden ? 0 : (panel.vertical ? panel.height : panel.barHeight)
            }

            // shared island entrance/exit: transform + opacity only (GPU),
            // no Canvas repaints during the animation
            property real islandFade: ShellState.hidden ? 0 : 1
            Behavior on islandFade { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            property real islandLift: ShellState.hidden ? -(barBodyHeight * 0.7) * (far ? -1 : 1) : 0
            readonly property real liftX: vertical ? islandLift : 0
            readonly property real liftY: vertical ? 0 : islandLift
            Behavior on islandLift { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            WlrLayershell.namespace: "quickshell"

            readonly property PwNode sink: Pipewire.defaultAudioSink
            PwObjectTracker { objects: [panel.sink] }

            SystemClock { id: clock; precision: SystemClock.Minutes }
            // for popouts in their own file: one clock, so the resume resync
            // below keeps applying to them too
            readonly property date clockDate: clock.date
            // SystemClock has no resync; toggling it re-reads the wall clock
            // and re-arms the minute tick from now rather than from before sleep
            Connections {
                target: Sys
                function onResumed() { clock.enabled = false; clock.enabled = true; }
            }

            // A popout takes the keyboard only when the menu opened it. One that
            // always wants keys is the network popout bug (see its own file):
            // Hyprland focuses a
            // layer the moment it maps, and with the pointer still on the cell
            // that focus never comes back for the second, closing click.
            function navOn(p) { return p.open && Sys.kbdNav; }
            function navFocus(p) { return navOn(p) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None; }

            // Every Popout adds itself here on creation. The three derived
            // things below used to be three hand-maintained lists of twelve.
            property var popouts: []
            // Only the ones that exist right now: `available` gates a popout
            // whose cell is conditional (clanker needs an agent), so the menu
            // does not offer a row that opens nothing.
            readonly property var livePopouts: popouts.filter(p => p.available)

            // Is that popout showing? For a cell that lights up while its own
            // popout is open. By name, because the popouts live in their own
            // files now and their ids do not reach this far.
            function isOpen(name) {
                const p = popoutsByName[name];
                return p ? p.open : false;
            }

            // The path a cell click takes: close the rest, then flip this one.
            function toggle(name) {
                const p = popoutsByName[name];
                if (!p) return;
                const next = !p.open;
                closeIslandPopouts();
                p.open = next;
            }

            function closeIslandPopouts() {
                // Not a popout and not in the registry, but it has always
                // closed alongside them; folding it into the loop would drop it.
                Notifs.centerOpen = false;
                for (const p of popouts) p.open = false;
            }

            // Popouts by the name the menu uses, derived from the registry.
            readonly property var popoutsByName: {
                const m = {};
                for (const p of popouts) m[p.panelName] = p;
                return m;
            }
            readonly property bool anyPopoutOpen: popouts.some(p => p.open)
            // Is a popout itself holding the keyboard? Then the dismiss layer
            // must not ask for it: taking focus away from a popout that holds
            // a focus grab clears the grab, and the popout closes on the spot.
            // That is exactly what broke every menu-opened popout.
            readonly property bool anyPopoutGrabbing: popouts.some(p => p.grabbing)
            onAnyPopoutOpenChanged: Sys.barPopoutsOpen += anyPopoutOpen ? 1 : -1

            // What the menu (and through it the launcher) lists. Assigned
            // wholesale rather than appended: one bar per screen, each writing
            // the same list, so the last one simply wins.
            // Sorted by name: popouts register in completion order, which is not
            // declaration order and is not something to depend on for the order
            // rows appear in the menu.
            onLivePopoutsChanged: Sys.barPanels = livePopouts
                .map(p => ({ name: p.panelName, icon: p.iconName }))
                .sort((a, b) => a.name.localeCompare(b.name))

            Connections {
                target: Sys
                function onCloseAll() { panel.closeIslandPopouts(); }
                function onTogglePanel(name) {
                    // one panel per screen; only the focused one answers
                    if (Hyprland.focusedMonitor?.name !== panel.screen.name) return;
                    const p = panel.popoutsByName[name];
                    if (!p) return;
                    const next = !p.open;
                    panel.closeIslandPopouts();
                    p.open = next;
                }
            }

            function clamp(v, lo, hi) {
                return Math.max(lo, Math.min(hi, v));
            }

            // Icon name for a process. Substring match, not a table lookup:
            // top reports "wezterm-gui", ".firefox-wrapped", "code-oss".
            // Everything unmatched gets the cog — the list is two rows deep, so
            // an exhaustive map would be a lot of table for a lot of nothing.
            // Discord has no MDI icon; chat is the nearest honest stand-in.
            function procIcon(name) {
                const n = name.toLowerCase();
                if (n.includes("firefox")) return "firefox";
                if (n.includes("chrom") || n.includes("brave")) return "google-chrome";
                if (n.includes("code") || n.includes("nvim") || n.includes("vim")) return "code-tags";
                if (n.includes("term") || n.includes("kitty") || n.includes("foot")
                    || n.includes("zsh") || n.includes("bash")) return "console";
                if (n.includes("steam")) return "steam";
                if (n.includes("spotify")) return "spotify";
                if (n.includes("slack")) return "slack";
                if (n.includes("telegram")) return "send";
                if (n.includes("discord")) return "chat";
                if (n.includes("mpv") || n.includes("vlc") || n.includes("mplayer")) return "video";
                if (n.includes("zoom") || n.includes("teams") || n.includes("meet")) return "video";
                if (n.includes("obs")) return "video";
                if (n.includes("pw-play") || n.includes("pw-cat") || n.includes("paplay")) return "volume-high";
                if (n.includes("docker") || n.includes("containerd")) return "docker";
                if (n.includes("qemu")) return "monitor";
                if (n.includes("pipewire") || n.includes("wireplumber")) return "volume-high";
                if (n.includes("hyprland") || n.includes("quickshell") || n === "qs") return "view-dashboard";
                return "cog";
            }

            // Popout placement along the bar's axis, centred on its cell and
            // kept off the screen corners. popoutTop/Left turn that into
            // window margins for whichever edge the bar is on.
            function attachedPanelX(sourceX, sourceWidth, popupExt) {
                const gutter = Theme.frameT + Theme.frameFillet + 8;
                return clamp(sourceX + sourceWidth / 2 - popupExt / 2,
                             gutter,
                             (vertical ? panel.height : panel.width) - popupExt - gutter);
            }
            function popoutTop(along, w, h) {
                if (vertical) return along;
                return far ? panel.screen.height - barHeight - Theme.popoutGap - h : barHeight + Theme.popoutGap;
            }
            function popoutLeft(along, w, h) {
                if (!vertical) return along;
                return far ? panel.screen.width - barHeight - Theme.popoutGap - w : barHeight + Theme.popoutGap;
            }

            // Text-as-root with the pill drawn behind it: sizing an outer
            // Rectangle from an inner Text's implicitWidth does not resolve
            // inside an inline component, so the label is the root instead.

            // Icon plus label. Was a bare Text with the icon baked into the
            // string as a nerd-font glyph; icons are SVG now, so the two are
            // separate items and the icon no longer depends on whichever font
            // fontconfig happened to resolve for the label.
            // vform is the vertical-bar form: "icon" drops the label, "stack"
            // puts the label under the icon in a smaller face, "rot" turns the
            // label on its side (reads bottom-up on a left bar, top-down on a
            // right one, like a book spine).
            component Cell: Item {
                id: cell

                property string icon: ""
                property alias text: cellLabel.text
                property alias font: cellLabel.font
                property color color: Theme.text
                property int leftPadding: 8
                property int rightPadding: 8
                property string vform: "icon"
                // extra height above the row on a vertical bar, for a glyph the
                // caller draws itself (backlight's two-panel indicator)
                property int topSlot: 0

                readonly property bool v: panel.vertical
                readonly property bool stacked: v && vform === "stack" && text !== ""
                readonly property bool rot: v && vform === "rot" && text !== ""
                readonly property bool showLabel: text !== "" && (!v || stacked || rot)

                implicitWidth: v ? panel.barBodyHeight - 6 : cellRow.implicitWidth + leftPadding + rightPadding
                implicitHeight: v ? cellRow.implicitHeight + 8 + topSlot : Theme.fontSize + 14

                Grid {
                    id: cellRow

                    // x/y, not anchors: swapping anchors on a flip left the
                    // row parked at the old anchor's position
                    x: cell.v ? (cell.width - width) / 2 : cell.leftPadding
                    y: (cell.height - height + (cell.v ? cell.topSlot : 0)) / 2
                    flow: cell.stacked ? Grid.TopToBottom : Grid.LeftToRight
                    // exact count, not a big number: Grid reserves one spacing
                    // for the column after the last item, so an over-declared
                    // count pads the row and pushes it off centre
                    columns: cell.stacked ? 1 : Math.max(1, cellRow.visibleChildren.length)
                    spacing: cell.stacked ? 1 : 5
                    verticalItemAlignment: Grid.AlignVCenter
                    horizontalItemAlignment: Grid.AlignHCenter

                    Icon {
                        name: cell.icon
                        color: cell.color
                        // positioners drop invisible children and their spacing,
                        // so a label-only Cell costs no leading gap
                        visible: cell.icon !== ""
                    }
                    // the label's footprint, swapped when it is rotated so the
                    // positioner lays out the visual box, not the unrotated one
                    // visibility lives here, not on the Text: a child reads as
                    // invisible while its parent is, so binding the wrapper to
                    // the label's own `visible` latches it hidden
                    Item {
                        visible: cell.showLabel
                        width: cell.rot ? cellLabel.height : cellLabel.width
                        height: cell.rot ? cellLabel.width : cellLabel.height
                        Text {
                            id: cellLabel

                            anchors.centerIn: parent
                            rotation: cell.rot ? (panel.far ? 90 : -90) : 0
                            horizontalAlignment: Text.AlignHCenter
                            font.family: Theme.font
                            font.pixelSize: cell.stacked ? 10 : Theme.fontSize
                            color: cell.color
                        }
                    }
                }
            }

            // [x, width, visible] per island in panel coords — reactive; the
            // chrome window shapes its capsules from this
            readonly property var islandGeom: [
                [pos(leftRow) + pos(wsIsland), ext(wsIsland), wsIsland.visible],
                [pos(leftRow) + pos(svcWrap), ext(svcWrap), svcWrap.visible],
                [pos(titleIsland), ext(titleIsland), titleIsland.visible],
                [pos(rightRow) + pos(powerIsland), ext(powerIsland), powerIsland.visible],
                [pos(rightRow) + pos(trayIsland), ext(trayIsland), trayIsland.visible]
            ]

            // ---- left: layout + workspaces, then services/system ----
            GridLayout {
                id: leftRow
                visible: opacity > 0
                opacity: panel.islandFade
                transform: Translate { x: panel.liftX; y: panel.liftY }
                x: panel.vertical ? panel.edgeIn : panel.gutter
                y: panel.vertical ? panel.gutter : panel.edgeIn
                flow: panel.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                rowSpacing: 10
                columnSpacing: 10

                // hyprland's IPC reports the wrong name for lua layouts (always
                // the first one registered), so read layout-switcher.sh's
                // persisted picks instead — the file is the source of truth
                FileView {
                    id: layoutFile
                    path: `${Quickshell.env("HOME")}/.config/hypr/.layout`
                    watchChanges: true
                    onFileChanged: reload()
                }

                Island {
                    id: wsIsland
                    Cell {
                        vform: "rot"
                        text: {
                            const ws = Hyprland.monitorFor(panel.screen)?.activeWorkspace?.id;
                            let def = "dwindle", cur = "";
                            for (const line of layoutFile.text().split("\n")) {
                                const [k, v] = line.split("=");
                                if (k === "*") def = v;
                                else if (k == ws) cur = v;
                            }
                            return (cur || def).replace("lua:", "");
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.closeIslandPopouts();
                                Quickshell.execDetached(["sh", "-c", "~/.scripts/layout-switcher.sh"]);
                            }
                        }
                    }
                    Grid {
                        Layout.alignment: Qt.AlignCenter
                        flow: panel.vertical ? Grid.TopToBottom : Grid.LeftToRight
                        // wsRep.count, not visibleChildren: the Repeater is a
                        // child of the Grid too, so counting children over-counts
                        // by one and pads the row (see cellRow)
                        columns: panel.vertical ? 1 : Math.max(1, wsRep.count)
                        spacing: 3
                        padding: 4
                        Repeater {
                            id: wsRep
                            model: Hyprland.workspaces.values
                                .filter(w => w.id > 0 && w.monitor?.name === panel.screen.name)
                                .sort((a, b) => a.id - b.id)
                            Rectangle {
                                required property var modelData
                                readonly property bool on:
                                    modelData.monitor?.activeWorkspace?.id === modelData.id
                                width: 18; height: 18; radius: 6
                                color: on ? Theme.accent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.name
                                    font.family: Theme.font
                                    font.pixelSize: 10
                                    color: parent.modelData.urgent ? Theme.urgent
                                         : parent.on ? Theme.accentText : Theme.dim
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    // lua-config hyprland: classic dispatch syntax errors out
                                    onClicked: {
                                        panel.closeIslandPopouts();
                                        Hyprland.dispatch("hl.dsp.focus({ workspace = " + parent.modelData.id + " })");
                                    }
                                }
                            }
                        }
                    }
                }

                // services + system stats (the old inline waybar modules)
                MouseArea {
                    id: svcWrap

                    // implicit, not width/height: GridLayout sizes children by these
                    implicitWidth: svcIsland.implicitWidth
                    implicitHeight: svcIsland.implicitHeight

                    // Three things share this island, each with its own
                    // popout: docker, the VMs, and the machine itself. One
                    // click used to open a single list of all of it.

                    Island {
                        id: svcIsland

                        width: panel.vertical ? panel.barBodyHeight : svcWrap.width
                        height: panel.vertical ? svcWrap.height : panel.barBodyHeight

                        // Both always shown. Greyed docker means the daemon is
                        // down; normal colour with a 0 means it is up and idle.
                        Cell {
                            id: dockerCell
                            icon: "docker"; text: Sys.docker; vform: "stack"
                            color: Sys.dockerUp ? Theme.text : Theme.dim
                            MouseArea { anchors.fill: parent; onClicked: panel.toggle("docker") }
                        }
                        // server, not the memory chip it used to be — that glyph
                        // sat next to the CPU and RAM cells reading as a third one
                        Cell {
                            id: vmCell
                            icon: "server"; text: Sys.vm; vform: "stack"
                            MouseArea { anchors.fill: parent; onClicked: panel.toggle("vm") }
                        }
                        // cpu / mem / disk are one target: they are the same
                        // machine, and the popout shows the lot
                        Item {
                            id: sysCells
                            implicitWidth: sysRow.width
                            implicitHeight: sysRow.height
                            Layout.alignment: Qt.AlignCenter
                            // the MouseArea is a sibling of the Grid, not a child:
                            // a positioner lays out every child it has, MouseArea included
                            Grid {
                                id: sysRow
                                flow: panel.vertical ? Grid.TopToBottom : Grid.LeftToRight
                                columns: panel.vertical ? 1 : Math.max(1, sysRow.visibleChildren.length)
                                Cell { icon: "cpu-64-bit"; text: Math.round(Sys.cpu * 100) + "%"; vform: "stack" }
                                Cell { visible: Sys.memText !== ""; icon: "memory"; text: panel.vertical ? Sys.memText.split("/")[0] : Sys.memText; vform: "stack" }
                                Cell { visible: Sys.diskFree !== ""; icon: "harddisk"; text: Sys.diskFree; vform: "stack" }
                            }
                            MouseArea { anchors.fill: parent; onClicked: panel.toggle("system") }
                        }
                        // AI agents: worst limit across every subscription.
                        // Hidden until some collector has found usage.
                        Cell {
                            id: clankerCell
                            visible: Clanker.agents.length > 0
                            icon: Clanker.agent ? "agent-" + Clanker.agent.id : "robot"; vform: "stack"
                            text: Clanker.shown >= 0 ? Math.round(Clanker.shown * 100) + "%" : ""
                            color: Clanker.alarming ? Theme.urgent : Theme.text
                            MouseArea { anchors.fill: parent; onClicked: panel.toggle("clanker") }
                        }
                    }
                }
            }

            // ---- center: window carousel ----
            // All windows on this screen's active workspace as pills; the
            // focused one is highlighted and the strip slides to keep it
            // centered. Clicking a pill focuses that window.
            Island {
                id: titleIsland
                x: panel.vertical ? panel.edgeIn : (panel.width - width) / 2
                y: panel.vertical ? (panel.height - height) / 2 : panel.edgeIn
                visible: opacity > 0 && carousel.wins.length > 0
                opacity: panel.islandFade
                transform: Translate { x: panel.liftX; y: panel.liftY }

                Item {
                    id: carousel

                    readonly property var mon: Hyprland.monitorFor(panel.screen)
                    // rev is a rebuild trigger: .values is a fresh array each
                    // access but only re-evaluates on list add/remove, not when
                    // a toplevel's workspace property changes (window moved)
                    property int rev: 0
                    readonly property var wins: (rev, Hyprland.toplevels.values.filter(t =>
                        t.workspace && carousel.mon
                        && t.workspace.id === carousel.mon.activeWorkspace?.id))
                    readonly property int activeIndex: {
                        for (let i = 0; i < wins.length; i++)
                            if (wins[i] === Hyprland.activeToplevel)
                                return i;
                        return -1;
                    }

                    // laid out unrotated, then the viewport inside turns on its
                    // side for a vertical bar (spine direction per side)
                    // capped at a fraction of the bar, and never past the free
                    // run between the left and right clusters (island stays
                    // centred, so the tighter side bounds both; 12 = Island
                    // chrome, 10 = gap to each neighbour)
                    readonly property real barLen: panel.vertical ? panel.height : panel.width
                    readonly property real free: 2 * Math.min(barLen / 2 - (panel.pos(leftRow) + panel.ext(leftRow)),
                                                              panel.pos(rightRow) - barLen / 2) - 12 - 20
                    readonly property real along: Math.max(0, Math.min(strip.width, barLen * 0.25, free))
                    implicitWidth: panel.vertical ? panel.barBodyHeight : along
                    implicitHeight: panel.vertical ? along : panel.barBodyHeight
                    Layout.alignment: Qt.AlignCenter

                    Connections {
                        target: Hyprland
                        function onRawEvent(e) {
                            switch (e.name) {
                            case "openwindow":
                            case "closewindow":
                            case "movewindowv2":
                            case "workspacev2":
                            case "focusedmonv2":
                                carousel.rev++;
                            }
                        }
                    }

                    function recenter() {
                        const it = pills.itemAt(activeIndex);
                        if (it)
                            strip.x = along / 2 - (it.x + it.width / 2);
                        else if (wins.length === 0)
                            strip.x = 0;
                    }
                    onActiveIndexChanged: recenter()
                    onAlongChanged: recenter()

                    Item {
                        id: viewport
                        anchors.centerIn: parent
                        width: carousel.along
                        height: panel.barBodyHeight
                        rotation: panel.vertical ? (panel.far ? 90 : -90) : 0
                        clip: true

                    Row {
                        id: strip
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter
                        onWidthChanged: carousel.recenter()
                        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                        Repeater {
                            id: pills
                            model: carousel.wins

                            delegate: Rectangle {
                                id: pill
                                required property var modelData
                                required property int index
                                readonly property bool active: index === carousel.activeIndex

                                width: pillRow.width + 22
                                height: panel.barBodyHeight - 10
                                anchors.verticalCenter: parent.verticalCenter
                                radius: 8
                                color: pill.active ? Theme.track : "transparent"
                                border.color: pill.active ? Theme.islandBorder : "transparent"

                                Row {
                                    id: pillRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    IconImage {
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitSize: 14
                                        visible: source != ""
                                        // appId rarely matches the icon name verbatim;
                                        // heuristicLookup resolves e.g. wezterm's reverse-DNS id
                                        source: {
                                            const appId = pill.modelData.wayland?.appId ?? "";
                                            const entry = DesktopEntries.heuristicLookup(appId);
                                            return Quickshell.iconPath(entry?.icon ?? appId, true);
                                        }
                                    }

                                    // capped; a long title marquees while hovered
                                    Item {
                                        id: pillClip
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(pillText.implicitWidth, 160)
                                        height: pillText.implicitHeight
                                        clip: true
                                        readonly property real over: pillText.implicitWidth - width
                                        readonly property bool marquee: pillHover.containsMouse && over > 0

                                        Text {
                                            id: pillText
                                            width: pillClip.marquee ? implicitWidth : pillClip.width
                                            elide: Text.ElideMiddle
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize
                                            color: pill.active ? Theme.bright : Theme.dim
                                            text: pill.modelData.title || pill.modelData.wayland?.title || ""

                                            SequentialAnimation on x {
                                                running: pillClip.marquee
                                                loops: Animation.Infinite
                                                onRunningChanged: if (!running) pillText.x = 0
                                                PauseAnimation { duration: 400 }
                                                NumberAnimation { to: -pillClip.over; duration: pillClip.over * 30 }
                                                PauseAnimation { duration: 600 }
                                                NumberAnimation { to: 0; duration: pillClip.over * 30 }
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: pillHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        panel.closeIslandPopouts();
                                        Hyprland.dispatch(
                                            "hl.dsp.focus({ window = \"address:0x"
                                            + pill.modelData.address.replace(/^0x/, "") + "\" })");
                                    }
                                }
                            }
                        }
                    }
                    }
                }
            }

            // ---- right: status cluster + audio/power + tray/clock ----
            GridLayout {
                id: rightRow
                visible: opacity > 0
                opacity: panel.islandFade
                transform: Translate { x: panel.liftX; y: panel.liftY }
                x: panel.vertical ? panel.edgeIn : panel.width - width - panel.gutter
                y: panel.vertical ? panel.height - height - panel.gutter : panel.edgeIn
                flow: panel.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                rowSpacing: 10
                columnSpacing: 10

                Island {
                    id: powerIsland
                    // network + tailscale, icon only (names in their popouts)

                    // network — click opens the wifi panel
                    Cell {
                        id: netCell
                        icon: Sys.netIcon
                        // icon only — the SSID is in the popout, and the
                        // signal ladder already says what the bar needs to
                        color: Sys.netUp ? Theme.text : Theme.urgent

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("network");
                            }
                        }
                    }
                    // tailscale — beside the net cell, its own panel
                    Cell {
                        id: tsCell
                        visible: Sys.tsPresent
                        icon: "lock-outline"
                        // icon only; node name lives in the popout
                        color: Sys.tsUp ? (Sys.tsHealth.length ? Theme.warn : Theme.text)
                                        : Theme.dim

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("tailscale");
                            }
                        }
                    }
                    // battery — click opens the power-profile panel
                    Cell {
                        id: batteryCell
                        vform: "stack"
                        readonly property var dev: UPower.displayDevice
                        visible: (dev?.isLaptopBattery ?? false)
                        readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 0
                        readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false
                        // five-step battery icon, bolt while charging.
                        // Assigned to Cell's own icon property rather than
                        // declared — redeclaring it here would shadow the type's.
                        icon: charging ? "battery-charging"
                            : pct > 87 ? "battery"
                            : pct > 62 ? "battery-70"
                            : pct > 37 ? "battery-50"
                            : pct > 12 ? "battery-30"
                            : "battery-10"
                        text: Math.round(pct) + "%"
                        color: charging ? Theme.ok
                             : pct <= 10 ? Theme.urgent
                             : pct <= 20 ? Theme.warn
                             : Theme.text

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("power");
                            }
                        }
                    }
                    // backlight — click opens the display panel
                    Cell {
                        id: backlightCell
                        vform: "stack"
                        visible: Sys.backlight >= 0
                        // On the Duo the sun becomes two stacked halves, one per
                        // panel, so the bar says at a glance whether the bottom
                        // screen is still lit under the keyboard. Drawn, not a
                        // glyph: Theme.font is a Nerd Font that is not actually
                        // installed here, and half-block characters are exactly
                        // the kind of thing a fallback face renders wrong.
                        leftPadding: Sys.isDuo ? 22 : 8
                        topSlot: Sys.isDuo ? 16 : 0
                        icon: Sys.isDuo ? "" : "white-balance-sunny"
                        text: Math.round(Sys.backlight * 100) + "%"

                        Item {
                            visible: Sys.isDuo
                            width: 10
                            height: 14
                            // left of the label on a horizontal bar, above it on
                            // a vertical one (x/y, not anchors — see cellRow)
                            x: panel.vertical ? (parent.width - width) / 2 : 8
                            y: panel.vertical ? 5 : (parent.height - height) / 2
                            // top panel: always on, or the bar would not be drawn
                            Rectangle {
                                anchors { top: parent.top; left: parent.left; right: parent.right }
                                height: 6
                                radius: 1
                                color: Theme.text
                            }
                            Rectangle {
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                height: 6
                                radius: 1
                                color: Sys.subScreen ? Theme.text : Theme.track
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("display");
                            }
                        }
                    }
                    // zenbook duo keyboard backlight: click cycles 0-3
                    Cell {
                        visible: Sys.duoKbd
                        icon: "keyboard"
                        text: Sys.kbdBacklight === 0 ? "off" : Sys.kbdBacklight + "/3"
                        vform: "stack"
                        color: Sys.kbdBacklight === 0 ? Theme.dim : Theme.text
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.closeIslandPopouts();
                                Quickshell.execDetached(
                                    ["sh", "-c", "~/go/bin/duo kbd backlight " + ((Sys.kbdBacklight + 1) % 4)]);
                            }
                        }
                    }
                    // volume: click opens the audio panel, scroll adjusts.
                    // Mute moved into the panel — click had to give up one of
                    // the two, and the panel is where the devices live.
                    Cell {
                        id: volCell
                        vform: "stack"
                        readonly property var av: Audio.sink?.audio ?? null
                        icon: av ? Audio.volIcon(av.volume, av.muted) : ""
                        text: av ? (av.muted ? "\u2013" : Math.round(av.volume * 100) + "%") : ""
                        color: av?.muted ? Theme.dim : Theme.text
                        rightPadding: Audio.recording ? 2 : 8
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("audio");
                            }
                            onWheel: w => {
                                if (!parent.av) return;
                                const d = w.angleDelta.y > 0 ? 0.05 : -0.05;
                                parent.av.volume = Math.max(0, Math.min(1.5, parent.av.volume + d));
                            }
                        }
                    }
                    // bluetooth — next to the volume cell: the thing most often
                    // reached for here is switching audio to a headset
                    Cell {
                        id: btCell
                        vform: "stack"
                        visible: Bt.present
                        icon: Bt.icon
                        text: Bt.connectedDevices.length > 1 ? "" + Bt.connectedDevices.length : ""
                        color: Bt.enabled ? Theme.text : Theme.dim

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("bluetooth");
                            }
                        }
                    }
                    // macOS puts a dot in the menu bar whenever something holds
                    // the mic. A mic glyph says the same thing and says which.
                    Cell {
                        visible: Audio.recording
                        icon: "microphone"
                        color: Theme.warn
                        leftPadding: 4
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("audio");
                            }
                        }
                    }
                }

                Island {
                    id: trayIsland
                    // tray folded behind one cell; the items live in a popout.
                    // A row of third-party icons was the one thing in the bar
                    // not drawn in its own language.
                    Cell {
                        id: trayCell
                        vform: "stack"
                        readonly property int count: SystemTray.items.values.length
                        visible: count > 0
                        icon: "dots-horizontal"
                        text: "" + count
                        color: panel.isOpen("tray") ? Theme.bright : Theme.text
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("tray");
                            }
                        }
                    }
                    // notification bell → history panel
                    Cell {
                        id: notifBellCell
                        vform: "stack"

                        // history, not the daemon's tracked set — the two stopped
                        // being the same thing once history outlived a restart
                        readonly property int count: Notifs.history.length
                        icon: Notifs.dnd ? "bell-off" : "bell"
                        text: count > 0 ? "" + count : ""
                        color: Notifs.dnd ? Theme.dim
                             : count > 0 ? Theme.bright : Theme.dim
                        MouseArea {
                            anchors.fill: parent
                            // right-click toggles do-not-disturb. No dedicated
                            // control for it: the bell already says whether
                            // toasts are coming, so it may as well own the switch.
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    Notifs.dnd = !Notifs.dnd;
                                    return;
                                }
                                const next = !Notifs.centerOpen;
                                panel.closeIslandPopouts();
                                if (next)
                                    Notifs.setCenterAnchor(notifBellCell.mapToItem(null, 0, 0).x,
                                                           notifBellCell.width,
                                                           panel.screen);
                                Notifs.centerOpen = next;
                            }
                        }
                    }
                    Cell {
                        id: clockCell
                        vform: "stack"
                        text: Qt.formatDateTime(clock.date, panel.vertical ? "HH:mm\nd" : "ddd d · HH:mm")
                        color: Theme.bright
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("calendar");
                            }
                        }
                    }
                }
            }

            Connections {
                target: ShellState
                function onHiddenChanged() {
                    if (ShellState.hidden)
                        panel.closeIslandPopouts();
                }
            }

            // ---- dismiss layer for the bar popouts ----
            // Click-away and Escape for every popout, in one place rather than
            // twelve. Escape lives here, not on the popout, on purpose: a
            // popout that asks for the keyboard whenever it is open is the
            // netPopout bug written up below — Hyprland focuses a layer the
            // moment it maps, and the second click on its own cell never gets
            // back to the bar to close it. This layer stops at the bar's edge
            // and holds no focus grab, so the cell keeps its clicks while
            // Escape still lands somewhere.
            //
            // AttachedPanel also answers Escape, for the case where the menu
            // opened the popout and the popout itself holds the keyboard.
            PanelWindow {
                id: dismissLayer
                visible: panel.anyPopoutOpen
                screen: panel.screen
                anchors { top: true; left: true; right: true; bottom: true }
                margins {
                    top: ShellState.side === "top" ? panel.barHeight : 0
                    bottom: ShellState.side === "bottom" ? panel.barHeight : 0
                    left: ShellState.side === "left" ? panel.barHeight : 0
                    right: ShellState.side === "right" ? panel.barHeight : 0
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "quickshell-backdrop"
                // Only when no popout holds the keyboard itself: a menu-opened
                // popout has its own focus grab and answers Escape through
                // AttachedPanel, and stealing focus from it would close it.
                WlrLayershell.keyboardFocus: panel.anyPopoutOpen && !panel.anyPopoutGrabbing
                    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                MouseArea {
                    anchors.fill: parent
                    onClicked: panel.closeIslandPopouts()
                }
                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onEscapePressed: panel.closeIslandPopouts()
                }
            }

            TrayPopout {
                bar: panel
                cell: trayCell
            }

            CalendarPopout {
                bar: panel
                cell: clockCell
            }

            DisplayPopout {
                bar: panel
                cell: backlightCell
            }

            PowerPopout {
                bar: panel
                cell: batteryCell
            }

            TailscalePopout {
                bar: panel
                cell: tsCell
            }

            BluetoothPopout {
                bar: panel
                cell: btCell
            }

            AudioPopout {
                bar: panel
                cell: volCell
            }

            NetworkPopout {
                bar: panel
                cell: netCell
            }

            ResourcePopout {
                bar: panel
                cell: sysCells
            }

            ClankerPopout {
                bar: panel
                cell: clankerCell
            }


            ListPopout {
                id: dockerPopout
                bar: panel
                cell: dockerCell
                panelName: "docker"
                iconName: "docker"
                heading: "docker"
                rows: Sys.dockerList
                empty: Sys.dockerUp ? "no containers running" : "daemon is down"
            }
            ListPopout {
                id: vmPopout
                bar: panel
                cell: vmCell
                panelName: "vm"
                iconName: "server"
                heading: "virtual machines"
                rows: Sys.vmList
                empty: "no vms running"
            }

        }
        }
    }
}
