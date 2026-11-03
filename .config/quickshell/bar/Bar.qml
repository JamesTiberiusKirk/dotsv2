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
            // mod+b hides the bar of the focused screen only (ShellState.hiddenOn)
            readonly property bool barHidden: ShellState.isHidden(screen?.name)
            // hidden: islands slide up into the band and fade, windows reclaim
            // the bar body; the thin frame stays (Chrome.qml)
            exclusiveZone: panel.barHidden ? Theme.frameT : barHeight
            // hidden: windows reclaim the bar body, so drop the input region
            // too — otherwise the invisible surface eats clicks in that strip
            mask: Region {
                width: panel.barHidden ? 0 : (panel.vertical ? panel.barHeight : panel.width)
                height: panel.barHidden ? 0 : (panel.vertical ? panel.height : panel.barHeight)
            }

            // shared island entrance/exit: transform + opacity only (GPU),
            // no Canvas repaints during the animation
            property real islandFade: panel.barHidden ? 0 : 1
            Behavior on islandFade { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            property real islandLift: panel.barHidden ? -(barBodyHeight * 0.7) * (far ? -1 : 1) : 0
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

            // Every popout on this bar. Declared, not registered: the set is
            // the same on every screen and every boot, so a list that builds
            // itself at runtime only bought races — popouts unregistering as a
            // bar died left the menu's rows gone until the shell restarted.
            readonly property var popouts: [trayPopout, calendarPopout, displayPopout, powerPopout,
                tailscalePopout, bluetoothPopout, audioPopout, networkPopout, resourcePopout,
                clankerPopout, servicesPopout, ccGrid, ccSys]

            // Is that popout showing? For a cell that lights up while its own
            // popout is open. By name, because the popouts live in their own
            // files now and their ids do not reach this far.
            function isOpen(name) {
                const p = popoutsByName[name];
                return p ? p.open : false;
            }

            // Show a page in the one host card: opens it, or swaps the page
            // already showing (the card morphs). `via`: reached through the
            // control center, so it hangs off the CC cell and draws back.
            function showPage(name, via) {
                const p = popoutsByName[name];
                if (!p) return;
                Notifs.centerOpen = false;
                popoutHost.show(p, via);
            }

            // The path a cell click takes. Open under its own cell: a second
            // click closes it. Open through the control center: the click moves
            // it under the cell instead of closing.
            function toggle(name) {
                const p = popoutsByName[name];
                if (!p) return;
                if (p.open && !popoutHost.viaCC) closeIslandPopouts();
                else showPage(name, false);
            }

            // docker and the vms share the services popout, one tab each. Hang it off the cell of
            // the tab being opened; the same tab open under its own cell closes, the other one switches.
            function toggleServices(tab) {
                const p = servicesPopout;
                if (p.open && !popoutHost.viaCC && p.currentTab === tab) return closeIslandPopouts();
                p.cell = tab === "vms" ? vmsCell : dockerCell;
                p.currentTab = tab;
                showPage("services", !ShellState.inBar(tab));
            }

            function closeIslandPopouts() {
                // Not a popout and not in the registry, but it has always
                // closed alongside them; folding it into the loop would drop it.
                Notifs.centerOpen = false;
                popoutHost.close();
            }

            // Is a control center page of this group ("sys" | "status") showing? Lights its cell.
            function ccShowing(group) {
                const pg = popoutHost.page;
                return popoutHost.open && popoutHost.viaCC && pg !== null && ShellState.groupOf(pg.panelName) === group;
            }
            function toggleCC(group) {
                if (ccShowing(group)) closeIslandPopouts();
                else showPage(ShellState.ccName(group), true);
            }

            // One bar cell per AI agent, hanging the one clanker popout off the one clicked. The ids as a
            // joined string: Clanker re-publishes its agent list every refresh, and a new array would
            // make the Repeater rebuild every cell, nulling clankerPopout.cell under an open popout.
            // A string only notifies when the agents really changed.
            readonly property string agentKey: Clanker.agents.map(a => a.id).join(",")
            readonly property var agentIds: agentKey === "" ? [] : agentKey.split(",")
            // Point the clanker popout at an agent's cell: the selected agent's if it is on the bar,
            // else the first pinned one (the menu opens it with no cell in mind). None visible:
            // the host falls back to the sys control center cell.
            function anchorClanker() {
                let pick = null;
                for (let i = 0; i < agentCells.count; i++) {
                    const c = agentCells.itemAt(i);
                    if (!c || !ShellState.inBar("clanker:" + c.agentId)) continue;
                    if (c.agentId === Clanker.selectedId) { pick = c; break; }
                    if (!pick) pick = c;
                }
                clankerPopout.cell = pick;
            }

            // Popouts by the name the menu uses, derived from the registry.
            readonly property var popoutsByName: {
                const m = {};
                for (const p of popouts) m[p.panelName] = p;
                return m;
            }
            readonly property bool anyPopoutOpen: popoutHost.open
            // Is a popout itself holding the keyboard? Then the dismiss layer
            // must not ask for it: taking focus away from a popout that holds
            // a focus grab clears the grab, and the popout closes on the spot.
            // That is exactly what broke every menu-opened popout.
            readonly property bool anyPopoutGrabbing: popoutHost.grabbing
            onAnyPopoutOpenChanged: Sys.barPopoutsOpen += anyPopoutOpen ? 1 : -1
            onAnyPopoutGrabbingChanged: Sys.barPopoutsGrabbing += anyPopoutGrabbing ? 1 : -1
            // A screen going away takes this bar with it, popout still open:
            // the counters are global, so without this they never come back
            // down and Hyprland's submap is decided off a bar that is gone.
            Component.onDestruction: {
                if (anyPopoutOpen) Sys.barPopoutsOpen -= 1;
                if (anyPopoutGrabbing) Sys.barPopoutsGrabbing -= 1;
            }

            Connections {
                target: Sys
                function onCloseAll() { panel.closeIslandPopouts(); }
                function onTogglePanel(name) {
                    // one panel per screen; only the focused one answers
                    if (Hyprland.focusedMonitor?.name !== panel.screen.name) return;
                    // "services:docker" opens a tabbed popout on that tab; asking
                    // for the tab already showing closes it, like any toggle
                    const [pname, tab] = name.split(":");
                    const p = panel.popoutsByName[pname];
                    if (!p) return;
                    const next = !(p.open && (!tab || p.currentTab === tab));
                    if (tab) p.currentTab = tab;
                    // a folded indicator opens as a control center page, hung
                    // off its group's control center cell. "clanker" counts as on
                    // the bar when any agent is pinned; its selection stays as it is.
                    if (pname === "clanker") panel.anchorClanker();
                    // services: on the bar is a question about the tab's own cell (docker or vms)
                    const svcTab = pname === "services" ? p.currentTab : "";
                    if (svcTab) p.cell = svcTab === "vms" ? vmsCell : dockerCell;
                    if (next) panel.showPage(pname, svcTab ? !ShellState.inBar(svcTab) : !ShellState.inBarPanel(pname));
                    else panel.closeIslandPopouts();
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

            // Right-click on a bar cell folds its indicator into its control center (off the bar).
            // Its own MouseArea that takes only the right button, so each cell's left-click area
            // (and the volume wheel) stays as it was. Not on the bell (right-click is do-not-disturb),
            // the mic dot or the control center cells.
            component FoldArea: MouseArea {
                required property string name
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: ShellState.fold(name)
            }

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
                    // Hidden when none of its cells is on the bar (docker/vms, system, any agent) and
                    // nothing of the sys group is folded (its control center cell lives here).
                    // Asks the state, not the cells: a child's visible follows its parent's.
                    visible: ShellState.inBar("docker") || ShellState.inBar("vms") || ShellState.inBar("system")
                        || ShellState.inBarPanel("clanker") || ShellState.anyInCC("sys")

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

                        // docker and the VMs: a cell each, one shared popout opened
                        // on that cell's tab. Greyed docker means the daemon is down;
                        // normal colour with a 0 means it is up and idle.
                        Cell {
                            id: dockerCell
                            visible: ShellState.inBar("docker")
                            icon: "docker"
                            text: Sys.docker
                            vform: "stack"
                            color: Sys.dockerUp ? Theme.text : Theme.dim
                            MouseArea { anchors.fill: parent; onClicked: panel.toggleServices("docker") }
                            FoldArea { name: "docker" }
                        }
                        Cell {
                            id: vmsCell
                            visible: ShellState.inBar("vms")
                            icon: "server"
                            text: Sys.vm
                            vform: "stack"
                            MouseArea { anchors.fill: parent; onClicked: panel.toggleServices("vms") }
                            FoldArea { name: "vms" }
                        }
                        // cpu / mem / disk are one target: they are the same
                        // machine, and the popout shows the lot
                        Item {
                            id: sysCells
                            visible: ShellState.inBar("system")
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
                            FoldArea { name: "system" }
                        }
                        // AI agents: one cell per agent, its icon and its fullest window.
                        // Each shows only while that agent is pinned (ShellState.inBar; an
                        // agent no collector lists is not present).
                        Repeater {
                            id: agentCells
                            model: panel.agentIds
                            Cell {
                                id: agentCell
                                required property string modelData
                                readonly property string agentId: modelData
                                readonly property var agent: Clanker.agents.find(x => x.id === modelData) ?? null
                                readonly property real used: Clanker.headline(agent)
                                // the limit pinned in the popout; unpinned or limitless falls back to the worst
                                readonly property var pinned: (agent && agent.limits || [])[Clanker.limitSel[modelData] ?? -1] ?? null
                                readonly property real shown: pinned ? Number(pinned.percent) : used
                                visible: ShellState.inBar("clanker:" + modelData)
                                icon: "agent-" + modelData; vform: "stack"
                                text: shown >= 0 ? Math.round(shown * 100) + "%" : ""
                                color: used >= 0.9 ? Theme.urgent : Theme.text
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        // second click on the same agent's cell closes; another agent's
                                        // cell switches the popout over and re-anchors it
                                        const same = clankerPopout.open && !popoutHost.viaCC
                                            && clankerPopout.cell === agentCell && Clanker.selectedId === agentCell.agentId;
                                        if (same) { panel.closeIslandPopouts(); return; }
                                        clankerPopout.cell = agentCell;
                                        Clanker.select(agentCell.agentId);
                                        panel.showPage("clanker", false);
                                    }
                                }
                                FoldArea { name: "clanker:" + agentCell.agentId }
                            }
                        }
                        // control center of the sys group: docker, system and agents folded off the bar
                        Cell {
                            id: sysCcCell
                            visible: ShellState.anyInCC("sys")
                            icon: "view-dashboard"
                            color: panel.ccShowing("sys") ? Theme.bright : Theme.text
                            MouseArea { anchors.fill: parent; onClicked: panel.toggleCC("sys") }
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
                            // ScriptModel: wins is a fresh array on every rev++,
                            // and a plain array rebuilt every pill (hover marquee
                            // reset, clicks landing on dead delegates)
                            model: ScriptModel { values: carousel.wins }

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

                    // recording (~/.scripts/record.sh): shows only while wl-screenrec
                    // runs, elapsed time beside the icon; click stops it
                    Cell {
                        id: recCell
                        visible: ShellState.recording !== ""
                        property int secs: 0
                        icon: ShellState.recording === "gif" ? "image-multiple" : "video"
                        text: Math.floor(secs / 60) + ":" + String(secs % 60).padStart(2, "0")
                        vform: "stack"
                        color: Theme.urgent
                        Timer {
                            running: recCell.visible
                            interval: 1000
                            repeat: true
                            triggeredOnStart: true
                            onTriggered: recCell.secs = Math.floor((Date.now() - ShellState.recStarted) / 1000)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["sh", "-c", "~/.scripts/record.sh"])
                        }
                    }
                    // network — click opens the wifi panel
                    Cell {
                        id: netCell
                        visible: ShellState.inBar("network")
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
                        FoldArea { name: "network" }
                    }
                    // tailscale — beside the net cell, its own panel
                    Cell {
                        id: tsCell
                        visible: ShellState.inBar("tailscale")
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
                        FoldArea { name: "tailscale" }
                    }
                    // battery — click opens the power-profile panel
                    Cell {
                        id: batteryCell
                        vform: "stack"
                        readonly property var dev: UPower.displayDevice
                        visible: ShellState.inBar("power")
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
                        FoldArea { name: "power" }
                    }
                    // backlight — click opens the display panel
                    Cell {
                        id: backlightCell
                        vform: "stack"
                        visible: ShellState.inBar("display")
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
                        FoldArea { name: "display" }
                    }
                    // zenbook duo keyboard backlight: click cycles 0-3
                    Cell {
                        visible: ShellState.inBar("kbd")
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
                        FoldArea { name: "kbd" }
                    }
                    // volume: click opens the audio panel, scroll adjusts.
                    // Mute moved into the panel — click had to give up one of
                    // the two, and the panel is where the devices live.
                    Cell {
                        id: volCell
                        visible: ShellState.inBar("audio")
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
                                parent.av.volume = Math.max(0, Math.min(1, parent.av.volume + d));
                            }
                        }
                        FoldArea { name: "audio" }
                    }
                    // bluetooth — next to the volume cell: the thing most often
                    // reached for here is switching audio to a headset
                    Cell {
                        id: btCell
                        vform: "stack"
                        visible: ShellState.inBar("bluetooth")
                        icon: Bt.icon
                        text: Bt.connectedDevices.length > 1 ? "" + Bt.connectedDevices.length : ""
                        color: Bt.enabled ? Theme.text : Theme.dim

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("bluetooth");
                            }
                        }
                        FoldArea { name: "bluetooth" }
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
                    // control center: every indicator folded out of the bar lives behind this one cell
                    Cell {
                        id: ccCell
                        visible: ShellState.anyInCC("status")
                        icon: "tune-variant"
                        color: panel.ccShowing("status") ? Theme.bright : Theme.text
                        MouseArea { anchors.fill: parent; onClicked: panel.toggleCC("status") }
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
                        visible: ShellState.inBar("tray")
                        icon: "dots-horizontal"
                        text: "" + count
                        color: panel.isOpen("tray") ? Theme.bright : Theme.text
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("tray");
                            }
                        }
                        FoldArea { name: "tray" }
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
                        visible: ShellState.inBar("calendar")
                        vform: "stack"
                        text: Qt.formatDateTime(clock.date, panel.vertical ? "HH:mm\nd" : "ddd d · HH:mm")
                        color: Theme.bright
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel.toggle("calendar");
                            }
                        }
                        FoldArea { name: "calendar" }
                    }
                }
            }

            onBarHiddenChanged: if (barHidden) closeIslandPopouts()

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

            // The one card window every popout page lives in; see PopoutHost.qml.
            PopoutHost {
                id: popoutHost
                bar: panel
                homes: ({ status: ccGrid, sys: ccSys })

                TrayPopout { id: trayPopout; bar: panel; cell: trayCell }
                CalendarPopout { id: calendarPopout; bar: panel; cell: clockCell }
                DisplayPopout { id: displayPopout; bar: panel; cell: backlightCell }
                PowerPopout { id: powerPopout; bar: panel; cell: batteryCell }
                TailscalePopout { id: tailscalePopout; bar: panel; cell: tsCell }
                BluetoothPopout { id: bluetoothPopout; bar: panel; cell: btCell }
                AudioPopout { id: audioPopout; bar: panel; cell: volCell }
                NetworkPopout { id: networkPopout; bar: panel; cell: netCell }
                ResourcePopout { id: resourcePopout; bar: panel; cell: sysCells }
                // cell is set when an agent's cell is clicked or the menu opens it (anchorClanker)
                ClankerPopout { id: clankerPopout; bar: panel }
                // no cell binding: toggleServices points it at the docker or the vms cell
                ServicesPopout { id: servicesPopout; bar: panel; panelName: "services" }
                ControlCenter { id: ccGrid; bar: panel; cell: ccCell; group: "status"; panelName: "cc" }
                ControlCenter { id: ccSys; bar: panel; cell: sysCcCell; group: "sys"; panelName: "cc-sys" }
            }

        }
        }
    }
}
