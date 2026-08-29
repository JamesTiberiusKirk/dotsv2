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

Variants {
    model: Quickshell.screens

    delegate: Component {
        Scope {
            id: barScope
            required property var modelData
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
            // The bezel remaps a beat after the bar so it stacks above it, as
            // it does at startup (declared later in this file): remapped on the
            // same tick the order flipped and the glassed bar hid the band.
            property bool mapped: true
            property bool bezelMapped: true
            visible: mapped
            Connections {
                target: ShellState
                function onSideChanged() {
                    panel.closeIslandPopouts();
                    panel.mapped = false;
                    panel.bezelMapped = false;
                    remap.start();
                }
            }
            Timer { id: remap; interval: 80; onTriggered: { panel.mapped = true; remapBezel.start(); } }
            Timer { id: remapBezel; interval: 60; onTriggered: panel.bezelMapped = true }

            readonly property int barBodyHeight: ShellState.barBody
            readonly property int barHeight: barBodyHeight + Theme.frameT
            // island offset inside the window on the cross axis (the band is at
            // the far edge of the window on right/bottom), and from the screen
            // corners along the bar
            readonly property int edgeIn: far ? 0 : Theme.frameT
            readonly property int gutter: Theme.frameT + Theme.frameFillet + 12
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
            // the bar body; the thin frame stays (bezelWin), like the bottom strip
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

            property string submap: ""
            Connections {
                target: Hyprland
                function onRawEvent(e) {
                    if (e.name === "submap")
                        panel.submap = e.data;
                }
            }

            readonly property PwNode sink: Pipewire.defaultAudioSink
            PwObjectTracker { objects: [panel.sink] }

            SystemClock { id: clock; precision: SystemClock.Minutes }
            // SystemClock has no resync; toggling it re-reads the wall clock
            // and re-arms the minute tick from now rather than from before sleep
            Connections {
                target: Sys
                function onResumed() { clock.enabled = false; clock.enabled = true; }
            }
            QtObject { id: sysPopout; property bool open: false }
            QtObject { id: dockerPopout; property bool open: false }
            QtObject { id: vmPopout; property bool open: false }
            QtObject {
                id: dispPopout
                property bool open: false
                onOpenChanged: Sys.panelOpen = open
            }
            QtObject {
                id: pwrPopout
                property bool open: false
                onOpenChanged: Sys.powerPanelOpen = open
            }
            QtObject { id: tsPopout; property bool open: false }
            QtObject { id: trayPopout; property bool open: false }
            QtObject { id: clankerPopout; property bool open: false }
            QtObject {
                id: btPopout
                property bool open: false
                onOpenChanged: Bt.panelOpen = open
            }
            QtObject {
                id: audPopout
                property bool open: false
                onOpenChanged: Audio.panelOpen = open
            }
            QtObject {
                id: netPopout
                property bool open: false
                // which SSID has its detail row unfolded; "" = none
                property string expanded: ""
                onOpenChanged: {
                    Sys.netPanelOpen = open;
                    if (!open) expanded = "";
                }
            }

            function closeIslandPopouts() {
                Notifs.centerOpen = false;
                calPopout.open = false;
                sysPopout.open = false;
                dockerPopout.open = false;
                vmPopout.open = false;
                dispPopout.open = false;
                pwrPopout.open = false;
                netPopout.open = false;
                audPopout.open = false;
                btPopout.open = false;
                tsPopout.open = false;
                trayPopout.open = false;
                clankerPopout.open = false;
            }

            // Popouts by the name the menu uses. Same path a cell click takes:
            // close the rest, then flip this one.
            readonly property var popoutsByName: ({
                calendar: calPopout, system: sysPopout, docker: dockerPopout, vm: vmPopout, display: dispPopout, power: pwrPopout,
                network: netPopout, audio: audPopout, bluetooth: btPopout, tailscale: tsPopout, tray: trayPopout, clanker: clankerPopout
            })
            readonly property bool anyPopoutOpen: calPopout.open || sysPopout.open || dockerPopout.open || vmPopout.open || dispPopout.open || pwrPopout.open
                || netPopout.open || audPopout.open || btPopout.open || tsPopout.open || trayPopout.open || clankerPopout.open
            onAnyPopoutOpenChanged: Sys.barPopoutsOpen += anyPopoutOpen ? 1 : -1

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
            component PillBtn: Text {
                id: pb
                property bool active: false
                signal pressed()
                topPadding: 4; bottomPadding: 4; leftPadding: 10; rightPadding: 10
                font.family: Theme.font
                font.pixelSize: 11
                color: pb.active ? Theme.accentText : Theme.text
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: pb.active ? Theme.accent : Theme.track
                    z: -1
                }
                MouseArea { anchors.fill: parent; onClicked: pb.pressed() }
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
                    columns: cell.stacked ? 1 : 999
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

            // [x, width, visible] per island in panel coords — reactive,
            // shared by the capsule canvas (this window) and the bezel window
            readonly property var islandGeom: [
                [pos(leftRow) + pos(wsIsland), ext(wsIsland), wsIsland.visible],
                [pos(leftRow) + pos(svcWrap), ext(svcWrap), svcWrap.visible],
                [pos(titleIsland), ext(titleIsland), titleIsland.visible],
                [pos(rightRow) + pos(powerIsland), ext(powerIsland), powerIsland.visible],
                [pos(rightRow) + pos(trayIsland), ext(trayIsland), trayIsland.visible]
            ]
            readonly property int notchFillet: 8 // notch fillet (Island.qml)

            // ---- island capsules: the only pixels hyprglass touches ----
            // The band/stubs/corner fillets live in the separate bezel window
            // below (namespace quickshell-frame, unglassed) — glass edge
            // refraction on the 2px chrome smeared the screen corners.
            Item {
                id: topEdge
                visible: opacity > 0
                opacity: panel.islandFade
                width: panel.along
                height: panel.barHeight
                transform: [
                    Matrix4x4 { matrix: panel.chromeMatrix },
                    Translate { x: panel.liftX; y: panel.liftY }
                ]

                // Shape, not Canvas: Canvas AA edges composite with a premultiply
                // mismatch on nvidia (dark fringe around every path edge)
                // stable count model: geometry changes (clock tick, cpu% width)
                // rebind ix/iw in place instead of rebuilding the delegates
                Repeater {
                    model: panel.islandGeom.length
                    Shape {
                        required property int index
                        readonly property var g: panel.islandGeom[index]
                        visible: g[2]
                        readonly property real ix: g[0]
                        readonly property real iw: g[1]
                        readonly property real nT: Theme.frameT
                        readonly property real nf: panel.notchFillet
                        readonly property real cr: 12
                        readonly property real ch: panel.barBodyHeight
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        // fill under the band too: hyprglass highlights the edge
                        // of this layer's content, and with the fill starting
                        // at y = T that edge ran along the band, through every
                        // capsule. Pushed to the screen edge it hides under the bezel.
                        Rectangle { x: ix - nf; y: 0; width: iw + 2 * nf; height: nT; color: Theme.island }
                        // capsule fill — auto-closes along y = T, flush under the band
                        ShapePath {
                            strokeColor: "transparent"
                            fillColor: Theme.island
                            startX: ix - nf; startY: nT
                            PathArc { x: ix; y: nT + nf; radiusX: nf; radiusY: nf }
                            PathLine { x: ix; y: nT + ch - cr }
                            PathArc { x: ix + cr; y: nT + ch; radiusX: cr; radiusY: cr; direction: PathArc.Counterclockwise }
                            PathLine { x: ix + iw - cr; y: nT + ch }
                            PathArc { x: ix + iw; y: nT + ch - cr; radiusX: cr; radiusY: cr; direction: PathArc.Counterclockwise }
                            PathLine { x: ix + iw; y: nT + nf }
                            PathArc { x: ix + iw + nf; y: nT; radiusX: nf; radiusY: nf }
                        }
                        // outline — same run, left open at the top edge
                        ShapePath {
                            strokeColor: Theme.islandBorder
                            strokeWidth: 1
                            fillColor: "transparent"
                            startX: ix - nf; startY: nT
                            PathArc { x: ix; y: nT + nf; radiusX: nf; radiusY: nf }
                            PathLine { x: ix; y: nT + ch - cr }
                            PathArc { x: ix + cr; y: nT + ch; radiusX: cr; radiusY: cr; direction: PathArc.Counterclockwise }
                            PathLine { x: ix + iw - cr; y: nT + ch }
                            PathArc { x: ix + iw; y: nT + ch - cr; radiusX: cr; radiusY: cr; direction: PathArc.Counterclockwise }
                            PathLine { x: ix + iw; y: nT + nf }
                            PathArc { x: ix + iw + nf; y: nT; radiusX: nf; radiusY: nf }
                        }
                    }
                }
            }



            // ---- left: layout + workspaces + submap, then services/system ----
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
                        columns: panel.vertical ? 1 : 999
                        spacing: 3
                        padding: 4
                        Repeater {
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
                    Cell {
                        // the popout submap is plumbing for Esc, not a mode
                        visible: panel.submap !== "" && panel.submap !== "popout"
                        text: panel.submap.toUpperCase()
                        color: Theme.urgent
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
                    function toggle(p) {
                        const next = !p.open;
                        panel.closeIslandPopouts();
                        p.open = next;
                    }

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
                            MouseArea { anchors.fill: parent; onClicked: svcWrap.toggle(dockerPopout) }
                        }
                        // server, not the memory chip it used to be — that glyph
                        // sat next to the CPU and RAM cells reading as a third one
                        Cell {
                            id: vmCell
                            icon: "server"; text: Sys.vm; vform: "stack"
                            MouseArea { anchors.fill: parent; onClicked: svcWrap.toggle(vmPopout) }
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
                                columns: panel.vertical ? 1 : 999
                                Cell { icon: "cpu-64-bit"; text: Math.round(Sys.cpu * 100) + "%"; vform: "stack" }
                                Cell { visible: Sys.memText !== ""; icon: "memory"; text: panel.vertical ? Sys.memText.split("/")[0] : Sys.memText; vform: "stack" }
                                Cell { visible: Sys.diskFree !== ""; icon: "harddisk"; text: Sys.diskFree; vform: "stack" }
                            }
                            MouseArea { anchors.fill: parent; onClicked: svcWrap.toggle(sysPopout) }
                        }
                        // AI agents: worst limit across every subscription.
                        // Hidden until some collector has found usage.
                        Cell {
                            id: clankerCell
                            visible: Clanker.agents.length > 0
                            icon: Clanker.agent ? "agent-" + Clanker.agent.id : "robot"; vform: "stack"
                            text: Clanker.worst >= 0 ? Math.round(Clanker.worst * 100) + "%" : ""
                            color: Clanker.alarming ? Theme.urgent : Theme.text
                            MouseArea { anchors.fill: parent; onClicked: svcWrap.toggle(clankerPopout) }
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
                    readonly property real along: Math.min(strip.width, (panel.vertical ? panel.height : panel.width) * 0.4)
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

                                    Text {
                                        id: pillText
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, 240)
                                        elide: Text.ElideMiddle
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize
                                        color: pill.active ? Theme.bright : Theme.dim
                                        text: pill.modelData.title || pill.modelData.wayland?.title || ""
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
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
                                const next = !netPopout.open;
                                panel.closeIslandPopouts();
                                netPopout.open = next;
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
                                const next = !tsPopout.open;
                                panel.closeIslandPopouts();
                                tsPopout.open = next;
                            }
                        }
                    }
                    Cell {
                        visible: Sys.corne !== ""
                        icon: "keyboard"
                        text: Sys.corne
                        vform: "rot"
                        color: Theme.bright
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
                        color: !charging && pct <= 10 ? Theme.urgent
                             : !charging && pct <= 20 ? Theme.warn
                             : Theme.text

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                const next = !pwrPopout.open;
                                panel.closeIslandPopouts();
                                pwrPopout.open = next;
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
                                const next = !dispPopout.open;
                                panel.closeIslandPopouts();
                                dispPopout.open = next;
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
                                const next = !audPopout.open;
                                panel.closeIslandPopouts();
                                audPopout.open = next;
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
                                const next = !btPopout.open;
                                panel.closeIslandPopouts();
                                btPopout.open = next;
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
                                const next = !audPopout.open;
                                panel.closeIslandPopouts();
                                audPopout.open = next;
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
                        color: trayPopout.open ? Theme.bright : Theme.text
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                const next = !trayPopout.open;
                                panel.closeIslandPopouts();
                                trayPopout.open = next;
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
                                const next = !calPopout.open;
                                panel.closeIslandPopouts();
                                calPopout.open = next;
                            }
                        }
                    }
                }
            }

            QsMenuAnchor {
                id: trayMenu
                anchor.window: panel
            }

            Connections {
                target: ShellState
                function onHiddenChanged() {
                    if (ShellState.hidden)
                        panel.closeIslandPopouts();
                }
            }

            // ---- click-away backdrop for the bar popouts ----
            PanelWindow {
                visible: calPopout.open || sysPopout.open || dispPopout.open || pwrPopout.open || netPopout.open || audPopout.open || btPopout.open || tsPopout.open || clankerPopout.open
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

                MouseArea {
                    anchors.fill: parent
                    onClicked: panel.closeIslandPopouts()
                }
            }

            // ---- tray popout (click the dots cell) ----
            PanelWindow {
                id: trayPanel

                readonly property real sourceX: panel.pos(rightRow) + panel.pos(trayIsland) + panel.pos(trayCell)
                readonly property real sourceWidth: panel.ext(trayCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: trayPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 240
                implicitHeight: trayCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: trayPopout.open
                    neckX: trayPanel.sourceX - trayPanel.popupX
                    neckWidth: trayPanel.sourceWidth

                    Column {
                        id: trayCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: SystemTray.items.values
                            Item {
                                id: trayRow
                                required property var modelData
                                width: trayCol.width
                                height: 28

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 7
                                    color: trayHover.hovered ? Theme.track : "transparent"
                                }
                                IconImage {
                                    id: trayRowIcon
                                    anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                    implicitSize: 16
                                    source: trayRow.modelData.icon
                                }
                                Text {
                                    anchors { left: trayRowIcon.right; leftMargin: 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                    // title is what the app registers; the id is a bus name, last resort
                                    text: trayRow.modelData.title || trayRow.modelData.tooltipTitle || trayRow.modelData.id
                                    font.family: Theme.font; font.pixelSize: 11
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }
                                HoverHandler { id: trayHover }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: e => {
                                        if (e.button === Qt.LeftButton) {
                                            trayRow.modelData.activate();
                                            panel.closeIslandPopouts();
                                        } else if (trayRow.modelData.hasMenu) {
                                            // the item's own menu, hung off this row rather
                                            // than off the bar; the popout stays for it
                                            trayMenu.anchor.window = trayPanel;
                                            trayMenu.menu = trayRow.modelData.menu;
                                            trayMenu.anchor.rect.x = trayRow.mapToItem(null, 0, 0).x + trayRow.width;
                                            trayMenu.anchor.rect.y = trayRow.mapToItem(null, 0, 0).y;
                                            trayMenu.open();
                                        } else {
                                            trayRow.modelData.secondaryActivate();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- calendar popout (click clock) ----
            // layer surface (not xdg popup) so hyprland's blur layerrule applies
            PanelWindow {
                id: calPopout

                property bool open: false
                property date shown: new Date()
                readonly property real sourceX: panel.pos(rightRow) + panel.pos(trayIsland) + panel.pos(clockCell)
                readonly property real sourceWidth: panel.ext(clockCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)
                onOpenChanged: if (open) shown = new Date()

                visible: open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 250
                implicitHeight: calCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: calPopout.open
                    neckX: calPopout.sourceX - calPopout.popupX
                    neckWidth: calPopout.sourceWidth

                    Column {
                        id: calCol
                        width: parent.width
                        spacing: 8

                        // full date, the old custom/date module
                        Text {
                            text: Qt.formatDate(clock.date, "dddd, d MMMM yyyy")
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                        }

                        Item {
                            width: calCol.width
                            height: 18
                            Text {
                                text: Qt.locale().monthName(calPopout.shown.getMonth()) + " " + calPopout.shown.getFullYear()
                                font.family: Theme.font; font.pixelSize: Theme.fontSize
                                font.weight: Font.DemiBold
                                color: Theme.bright
                            }
                            Row {
                                anchors.right: parent.right
                                spacing: 14
                                Text {
                                    text: "‹"; font.pixelSize: 14; color: Theme.text
                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -6
                                        onClicked: calPopout.shown = new Date(calPopout.shown.getFullYear(), calPopout.shown.getMonth() - 1, 1)
                                    }
                                }
                                Text {
                                    text: "›"; font.pixelSize: 14; color: Theme.text
                                    MouseArea {
                                        anchors.fill: parent; anchors.margins: -6
                                        onClicked: calPopout.shown = new Date(calPopout.shown.getFullYear(), calPopout.shown.getMonth() + 1, 1)
                                    }
                                }
                            }
                        }

                        DayOfWeekRow {
                            width: calCol.width
                            delegate: Text {
                                required property var model
                                text: model.shortName
                                horizontalAlignment: Text.AlignHCenter
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.dim
                            }
                        }
                        MonthGrid {
                            id: monthGrid
                            width: calCol.width
                            month: calPopout.shown.getMonth()
                            year: calPopout.shown.getFullYear()
                            spacing: 2
                            delegate: Text {
                                required property var model
                                text: model.day
                                horizontalAlignment: Text.AlignHCenter
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.weight: model.today ? Font.Bold : Font.Normal
                                color: model.today ? Theme.accent
                                     : model.month === monthGrid.month ? Theme.text : Theme.dim
                            }
                        }
                    }
                }
            }

            // ---- display panel (click the backlight cell) ----
            // Built from what the machine actually has: one slider per DRM
            // backlight, the sync lock only when there are two to lock, and the
            // Duo-only rows only on the Duo. A desktop has no backlights at all,
            // so the trigger cell is hidden and this never opens.
            PanelWindow {
                id: displayPopout

                readonly property real sourceX: panel.pos(rightRow) + panel.pos(powerIsland) + panel.pos(backlightCell)
                readonly property real sourceWidth: panel.ext(backlightCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: dispPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 280
                implicitHeight: dispCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: dispPopout.open
                    neckX: displayPopout.sourceX - displayPopout.popupX
                    neckWidth: displayPopout.sourceWidth

                    Column {
                        id: dispCol

                        width: parent.width
                        spacing: 10

                        // Generalised out of the brightness slider so the
                        // night-light temperature could reuse it: same drag
                        // ownership, same 50ms write throttle, different range
                        // and a caller-supplied commit.
                        component ValueSlider: Item {
                            id: sl
                            property string label
                            // Optional leading icon. iconOn dims rather than hides it,
                            // so a list where only one row is marked stays aligned.
                            property string icon: ""
                            property bool iconOn: true
                            property int value: 0
                            property int minValue: 0
                            property int maxValue: 100
                            property string suffix: "%"
                            // control present but inert: the backlight still
                            // takes writes, they just light nothing
                            property bool off: false
                            signal commit(int v)

                            // One wheel notch moves a twentieth of the range, so
                            // 0-100 still steps by 5 the way it always did.
                            readonly property int wheelStep:
                                Math.max(1, Math.round((maxValue - minValue) / 20))

                            width: dispCol.width
                            height: 30
                            opacity: off ? 0.4 : 1

                            // While dragging, the slider owns the value: the 2s
                            // poll is far slower than the drag and would keep
                            // snapping the handle back to a stale reading.
                            property bool held: false
                            property int shown: 0
                            onValueChanged: if (!held) shown = value
                            Component.onCompleted: shown = value

                            Row {
                                id: slLabel

                                spacing: 4

                                Icon {
                                    name: sl.icon
                                    visible: sl.icon !== ""
                                    opacity: sl.iconOn ? 1 : 0
                                    size: 13
                                    color: sl.off ? Theme.dim : Theme.text
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: sl.label
                                    font.family: Theme.font; font.pixelSize: 11
                                    color: sl.off ? Theme.dim : Theme.text
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Text {
                                anchors.right: parent.right
                                text: sl.off ? "off" : sl.shown + sl.suffix
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.dim
                            }

                            Rectangle {
                                id: track
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 2 }
                                height: 6
                                radius: 3
                                color: Theme.track

                                readonly property real frac:
                                    (sl.shown - sl.minValue) / Math.max(1, sl.maxValue - sl.minValue)

                                Rectangle {
                                    width: parent.width * track.frac
                                    height: parent.height
                                    radius: 3
                                    color: sl.off ? Theme.dim : Theme.accent
                                }
                                Rectangle {
                                    visible: !sl.off
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * track.frac - width / 2))
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 12; height: 12; radius: 6
                                    color: Theme.bright
                                }

                                function valueAt(mx) {
                                    const v = sl.minValue + mx / width * (sl.maxValue - sl.minValue);
                                    return Math.max(sl.minValue, Math.min(sl.maxValue, Math.round(v)));
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8 // 6px track is a small target
                                    enabled: !sl.off
                                    preventStealing: true
                                    onPressed: m => { sl.held = true; sl.shown = track.valueAt(m.x); writeTimer.restart(); }
                                    onPositionChanged: m => { if (sl.held) { sl.shown = track.valueAt(m.x); writeTimer.restart(); } }
                                    onReleased: { sl.held = false; writeTimer.stop(); sl.commit(sl.shown); }
                                    onWheel: w => {
                                        sl.shown = Math.max(sl.minValue, Math.min(sl.maxValue,
                                            sl.shown + (w.angleDelta.y > 0 ? sl.wheelStep : -sl.wheelStep)));
                                        sl.commit(sl.shown);
                                    }
                                }
                                // one write per 50ms of dragging, not one per frame
                                Timer {
                                    id: writeTimer
                                    interval: 50
                                    onTriggered: sl.commit(sl.shown)
                                }
                            }
                        }

                        Repeater {
                            model: Sys.brightnessRows
                            ValueSlider {
                                label: modelData.label
                                value: modelData.pct
                                // never 0: a panel driven fully dark is
                                // indistinguishable from one that died
                                minValue: 1
                                off: modelData.off
                                onCommit: v => Sys.setBrightness(modelData.name, v)
                            }
                        }

                        // nothing to lock together with a single panel
                        ToggleRow {
                            visible: Sys.isDuo && Sys.backlights.length > 1
                            label: "lock together"
                            checked: Sys.brightnessSync
                            onToggled: v => Sys.setBrightnessSync(v)
                        }

                        // ---- night light ----
                        // Above the Duo rows: it applies to every host, and the
                        // temperature belongs next to brightness.
                        Rectangle {
                            width: dispCol.width; height: 1
                            color: Theme.islandBorder
                        }
                        ToggleRow {
                            label: "night light"
                            checked: Sys.nightLight
                            onToggled: v => Sys.setNightLight(v)
                        }
                        ValueSlider {
                            label: "temperature"
                            value: Sys.nightTemp
                            minValue: 2500   // heavy amber
                            maxValue: 6500   // neutral daylight, no visible shift
                            suffix: "K"
                            onCommit: v => Sys.setNightTemp(v)
                        }

                        Rectangle {
                            visible: Sys.isDuo
                            width: dispCol.width; height: 1
                            color: Theme.islandBorder
                        }
                        ToggleRow {
                            visible: Sys.isDuo
                            label: "sub screen"
                            checked: Sys.subScreen
                            onToggled: v => Sys.setSubScreen(v)
                        }
                        ToggleRow {
                            visible: Sys.isDuo
                            label: "auto-rotate"
                            checked: Sys.autoRotate
                            onToggled: v => Sys.setAutoRotate(v)
                        }
                    }
                }
            }

            // ---- power panel (click the battery cell) ----
            // Battery detail plus the profile selector. Profiles bind straight
            // to PowerProfiles (Quickshell.Services.UPower) — the daemon is the
            // state, so there is nothing local to keep in sync.
            PanelWindow {
                id: powerPopout

                readonly property real sourceX: panel.pos(rightRow) + panel.pos(powerIsland) + panel.pos(batteryCell)
                readonly property real sourceWidth: panel.ext(batteryCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                readonly property var dev: Sys.batteryDevice
                readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false

                visible: pwrPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 300
                implicitHeight: pwrCol.implicitHeight + 28
                color: "transparent"

                // seconds -> "4h 18m" / "18m". 0 means UPower has no estimate yet
                // (it needs a rate sample) rather than "empty right now".
                function dur(s) {
                    if (!(s > 0)) return "—";
                    const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
                    return h > 0 ? h + "h " + m + "m" : m + "m";
                }

                AttachedPanel {
                    anchors.fill: parent
                    shown: pwrPopout.open
                    neckX: powerPopout.sourceX - powerPopout.popupX
                    neckWidth: powerPopout.sourceWidth

                    Column {
                        id: pwrCol

                        width: parent.width
                        spacing: 6

                        // label left, value right — the whole panel is this shape
                        component StatRow: Item {
                            id: sr
                            property string label
                            property string value
                            property color valueColor: Theme.text
                            property real indent: 0
                            // optional leading icon (the top-cpu rows use it)
                            property string icon: ""
                            width: pwrCol.width
                            height: 15
                            Row {
                                x: sr.indent
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Icon {
                                    name: sr.icon
                                    visible: sr.icon !== ""
                                    size: 12
                                    color: Theme.dim
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: sr.label
                                    font.family: Theme.font; font.pixelSize: 11
                                    color: Theme.dim
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: sr.value
                                font.family: Theme.font; font.pixelSize: 11
                                color: sr.valueColor
                            }
                        }
                        component Sep: Rectangle {
                            width: pwrCol.width; height: 1
                            color: Theme.islandBorder
                        }

                        // ---- battery ----
                        Item {
                            width: pwrCol.width
                            height: 22
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(powerPopout.dev?.percentage > 1
                                    ? powerPopout.dev.percentage
                                    : (powerPopout.dev?.percentage ?? 0) * 100) + "%"
                                font.family: Theme.font; font.pixelSize: 17
                                color: Theme.bright
                            }
                            Text {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: powerPopout.charging
                                    ? powerPopout.dur(powerPopout.dev?.timeToFull ?? 0) + " to full"
                                    : powerPopout.dur(powerPopout.dev?.timeToEmpty ?? 0) + " left"
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.text
                            }
                        }
                        StatRow {
                            label: powerPopout.charging ? "charge rate" : "discharge rate"
                            value: (powerPopout.dev?.changeRate ?? 0).toFixed(1) + " W"
                        }
                        StatRow {
                            // healthSupported is false on batteries that report no
                            // design capacity — showing 0% there would read as dead
                            visible: powerPopout.dev?.healthSupported ?? false
                            label: "health"
                            value: Math.round(powerPopout.dev?.healthPercentage ?? 0) + "%"
                        }

                        Sep {}

                        // ---- profile selector ----
                        // One segment per profile. performance is dropped when the
                        // daemon says the machine cannot sustain it.
                        Row {
                            id: profRow
                            width: pwrCol.width
                            spacing: 4

                            readonly property var profiles: PowerProfiles.hasPerformanceProfile
                                ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                                : [PowerProfile.PowerSaver, PowerProfile.Balanced]

                            Repeater {
                                model: profRow.profiles
                                Rectangle {
                                    id: seg
                                    readonly property bool active: PowerProfiles.profile === modelData
                                    readonly property string icon:
                                        modelData === PowerProfile.PowerSaver ? "leaf"
                                        : modelData === PowerProfile.Performance ? "rocket-launch"
                                        : "scale-balance"
                                    readonly property string name:
                                        modelData === PowerProfile.PowerSaver ? "saver"
                                        : modelData === PowerProfile.Performance ? "turbo"
                                        : "balanced"
                                    property bool hovered: false

                                    width: (profRow.width - profRow.spacing * (profRow.profiles.length - 1))
                                        / profRow.profiles.length
                                    height: 26
                                    radius: 4
                                    color: active ? Theme.accent : (hovered ? Theme.track : "transparent")
                                    border.width: active ? 0 : 1
                                    border.color: Theme.islandBorder
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    // Row, not Column: verticalCenter is the layout
                                    // axis in a Column, so anchoring both children
                                    // that way stacks them on the same line.
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Icon {
                                            name: seg.icon
                                            size: 13
                                            color: seg.active ? Theme.accentText : Theme.text
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: seg.name
                                            font.family: Theme.font; font.pixelSize: 11
                                            color: seg.active ? Theme.accentText : Theme.text
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: seg.hovered = true
                                        onExited: seg.hovered = false
                                        onClicked: PowerProfiles.profile = modelData
                                    }
                                }
                            }
                        }
                        // why the daemon is holding performance back, when it is
                        StatRow {
                            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
                            label: "throttled"
                            value: PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected
                                ? "lap detected" : "high temperature"
                            valueColor: Theme.warn
                        }

                        Sep {}

                        // ---- charge cap ----
                        // Hidden on hardware with no threshold node. The 80 is
                        // upowerd's, not ours — it is not a writable property.
                        ToggleRow {
                            visible: Sys.chargeLimit >= 0
                            label: "charge limit \u00b7 80%"
                            checked: Sys.chargeLimitOn
                            onToggled: v => Sys.setChargeLimit(v)
                        }

                        Sep { visible: Sys.topProcs.length > 0 }

                        // ---- top cpu ----
                        // CPU time, not watts: nothing attributes power per process
                        // without a powertop calibration run.
                        Text {
                            visible: Sys.topProcs.length > 0
                            text: "top cpu"
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                        }
                        Repeater {
                            model: Sys.topProcs
                            StatRow {
                                indent: 8
                                icon: panel.procIcon(modelData.name)
                                label: modelData.name
                                value: modelData.pct.toFixed(1) + "%"
                            }
                        }
                    }
                }
            }

            // ---- tailscale panel (click ts cell) ----
            PanelWindow {
                id: tsPanel

                readonly property real sourceX: panel.pos(rightRow) + panel.pos(powerIsland) + panel.pos(tsCell)
                readonly property real sourceWidth: panel.ext(tsCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: tsPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 300
                implicitHeight: tsCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: tsPopout.open
                    neckX: tsPanel.sourceX - tsPanel.popupX
                    neckWidth: tsPanel.sourceWidth

                    Column {
                        id: tsCol
                        width: parent.width
                        spacing: 8

                        component TsDiv: Rectangle {
                            width: tsCol.width; height: 1
                            color: Theme.islandBorder
                        }
                        component TsHead: Text {
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                        }
                        // click copies `value`; the label reads "copied" for a
                        // second so the click is seen to land. Popout stays open.
                        component TsCopy: Text {
                            id: tc
                            property string value
                            property string label
                            text: copied.running ? "copied" : label
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                            Timer { id: copied; interval: 1000 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Quickshell.execDetached(["wl-copy", "--", tc.value]);
                                    copied.restart();
                                }
                            }
                        }

                        ToggleRow {
                            label: "tailscale"
                            checked: Sys.tsUp
                            onToggled: value => Sys.tsSetUp(value)
                        }
                        Row {
                            visible: Sys.tsUp
                            width: tsCol.width
                            spacing: 6
                            TsCopy { label: Sys.tsNode; value: Sys.tsDns }
                            TsHead { text: "\u00b7" }
                            TsCopy { label: Sys.tsIp; value: Sys.tsIp }
                        }

                        // ---- exit node ----
                        TsDiv { visible: Sys.tsUp && Sys.tsExitOptions.length > 0 }
                        TsHead {
                            visible: Sys.tsUp && Sys.tsExitOptions.length > 0
                            text: "exit node"
                        }
                        Item {
                            visible: Sys.tsUp && Sys.tsExitOptions.length > 0
                            width: tsCol.width
                            height: 20

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Icon {
                                    name: "check"
                                    size: 13
                                    // reserved, not removed — the peer rows below
                                    // line their names up with this one
                                    opacity: Sys.tsExit === "" ? 1 : 0
                                    color: Theme.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: "none"
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Theme.font; font.pixelSize: 12
                                    color: Sys.tsExit === "" ? Theme.bright : Theme.text
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: Sys.tsExit !== ""
                                onClicked: Sys.tsSetExit("")
                            }
                        }
                        Repeater {
                            model: Sys.tsUp ? Sys.tsExitOptions : []

                            Item {
                                id: exRow
                                readonly property var peer: modelData
                                readonly property bool current: peer.ip === Sys.tsExit

                                width: tsCol.width
                                height: 20

                                Row {
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 5

                                    Icon {
                                        name: "check"
                                        size: 13
                                        opacity: exRow.current ? 1 : 0
                                        color: Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        width: Math.max(0, parent.width - 18)
                                        elide: Text.ElideRight
                                        text: exRow.peer.n + (exRow.peer.on ? "" : "  (offline)")
                                        font.family: Theme.font; font.pixelSize: 12
                                        color: exRow.current ? Theme.bright
                                             : exRow.peer.on ? Theme.text : Theme.dim
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: exRow.peer.on
                                    onClicked: Sys.tsSetExit(exRow.current ? "" : exRow.peer.ip)
                                }
                            }
                        }

                        // ---- peers ----
                        TsDiv { visible: Sys.tsUp }
                        Item {
                            visible: Sys.tsUp
                            width: tsCol.width
                            height: 16

                            TsHead {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "peers"
                            }
                            TsHead {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: Sys.tsPeersOnline + "/" + Sys.tsPeerCount + " up"
                            }
                        }
                        Flickable {
                            id: tsScroll
                            visible: Sys.tsUp
                            width: tsCol.width
                            height: Math.min(contentHeight, 200)
                            contentHeight: peerCol.implicitHeight
                            clip: true
                            SmoothScroll { flick: tsScroll }

                            Column {
                                id: peerCol
                                width: parent.width

                                Repeater {
                                    model: Sys.tsPeerList

                                    Item {
                                        id: pRow
                                        readonly property var peer: modelData

                                        width: peerCol.width
                                        height: 20

                                        // name copies the full MagicDNS name, ip copies the ip
                                        TsCopy {
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            width: parent.width - 120
                                            label: (pRow.peer.on ? "\u25cf  " : "\u25cb  ") + pRow.peer.n
                                            value: pRow.peer.d
                                            font.pixelSize: 12
                                            color: pRow.peer.on ? Theme.text : Theme.dim
                                        }
                                        TsCopy {
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            label: pRow.peer.ip
                                            value: pRow.peer.ip
                                        }
                                    }
                                }
                            }
                        }

                        // never surfaced anywhere before: a silently broken
                        // MagicDNS looks exactly like a working one
                        TsDiv { visible: Sys.tsHealth.length > 0 }
                        Repeater {
                            model: Sys.tsHealth
                            Text {
                                width: tsCol.width
                                wrapMode: Text.WordWrap
                                text: modelData
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.urgent
                            }
                        }
                    }
                }
            }

            // ---- bluetooth panel (click bt cell) ----
            PanelWindow {
                id: btPanel

                readonly property real sourceX: panel.pos(rightRow) + panel.pos(powerIsland) + panel.pos(btCell)
                readonly property real sourceWidth: panel.ext(btCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: btPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 300
                implicitHeight: btCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: btPopout.open
                    neckX: btPanel.sourceX - btPanel.popupX
                    neckWidth: btPanel.sourceWidth

                    Column {
                        id: btCol
                        width: parent.width
                        spacing: 8

                        ToggleRow {
                            label: "bluetooth"
                            checked: Bt.enabled
                            onToggled: value => Bt.setEnabled(value)
                        }

                        Rectangle {
                            visible: Bt.enabled
                            width: btCol.width; height: 1; color: Theme.islandBorder
                        }

                        Text {
                            visible: Bt.enabled && Bt.devices.length === 0
                            text: "nothing paired"
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                        }

                        Repeater {
                            model: Bt.enabled ? Bt.devices : []

                            Item {
                                id: btRow
                                readonly property var dev: modelData
                                readonly property bool busy:
                                    dev.state === BluetoothDeviceState.Connecting
                                    || dev.state === BluetoothDeviceState.Disconnecting

                                width: btCol.width
                                height: 24

                                Icon {
                                    id: btRowIcon

                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    name: Bt.devIcon(btRow.dev)
                                    size: 14
                                    color: btRow.dev.connected ? Theme.text : Theme.dim
                                }
                                Text {
                                    anchors { left: btRowIcon.right; leftMargin: 6; right: btMarks.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                    elide: Text.ElideRight
                                    text: btRow.dev.name
                                    font.family: Theme.font; font.pixelSize: 12
                                    color: btRow.dev.connected ? Theme.bright : Theme.text
                                }
                                Row {
                                    id: btMarks
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 6

                                    // bluez only reports battery while connected,
                                    // and only for devices that publish it at all
                                    Text {
                                        visible: btRow.dev.batteryAvailable
                                        text: Math.round(btRow.dev.battery * 100) + "%"
                                        font.family: Theme.font; font.pixelSize: 11
                                        color: btRow.dev.battery <= 0.2 ? Theme.urgent
                                             : btRow.dev.battery <= 0.35 ? Theme.warn
                                             : Theme.dim
                                    }
                                    Text {
                                        visible: btRow.busy
                                        text: "\u2026"
                                        font.family: Theme.font; font.pixelSize: 12
                                        color: Theme.warn
                                    }
                                    Icon {
                                        visible: !btRow.busy && btRow.dev.connected
                                        name: "check"
                                        size: 14
                                        color: Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !btRow.busy
                                    onClicked: Bt.toggle(btRow.dev)
                                }
                            }
                        }

                        Rectangle {
                            visible: Bt.enabled
                            width: btCol.width; height: 1; color: Theme.islandBorder
                        }
                        // pairing needs an agent to answer passkey prompts, which
                        // this panel has no way to show — blueman already does it
                        Text {
                            visible: Bt.enabled
                            text: "pair a new device\u2026"
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.accent
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Quickshell.execDetached(["blueman-manager"]);
                                    panel.closeIslandPopouts();
                                }
                            }
                        }
                    }
                }
            }

            // ---- audio panel (click volume cell) ----
            PanelWindow {
                id: audioPopout

                readonly property real sourceX: panel.pos(rightRow) + panel.pos(powerIsland) + panel.pos(volCell)
                readonly property real sourceWidth: panel.ext(volCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: audPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 340
                implicitHeight: audCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: audPopout.open
                    neckX: audioPopout.sourceX - audioPopout.popupX
                    neckWidth: audioPopout.sourceWidth

                    Column {
                        id: audCol
                        width: parent.width
                        spacing: 8

                        component AudDiv: Rectangle {
                            width: audCol.width; height: 1
                            color: Theme.islandBorder
                        }

                        // section header: name on the left, mute on the right
                        component AudHead: Item {
                            id: ah
                            property string label
                            property var target: null       // the PwNode to mute
                            readonly property var na: ah.target?.audio ?? null

                            width: audCol.width
                            height: 18

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ah.label
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.dim
                            }
                            Icon {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                visible: ah.na !== null
                                name: ah.na && ah.na.muted ? "volume-off" : "volume-high"
                                size: 15
                                color: ah.na && ah.na.muted ? Theme.urgent : Theme.text
                                MouseArea {
                                    anchors { fill: parent; margins: -6 }
                                    onClicked: if (ah.na) ah.na.muted = !ah.na.muted
                                }
                            }
                        }

                        // A device is its own slider — carrying the name once,
                        // its own volume, and the tick when it is the default.
                        // Clicking the name row selects it; the track keeps the
                        // bottom of the row to itself so a drag never switches.
                        component DevSlider: Column {
                            id: ds
                            property var node: null
                            property bool current: false
                            readonly property var na: ds.node?.audio ?? null

                            width: audCol.width
                            spacing: 4

                            ValueSlider {
                                width: audCol.width
                                icon: "check"
                                iconOn: ds.current
                                label: Audio.devName(ds.node)
                                suffix: "%"
                                maxValue: 150
                                off: ds.na?.muted ?? false
                                value: ds.na ? Math.round(ds.na.volume * 100) : 0
                                onCommit: v => { if (ds.na) ds.na.volume = v / 100; }

                                // top strip only — the track keeps the bottom of
                                // the row so a drag never switches device
                                MouseArea {
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    height: 16
                                    enabled: !ds.current
                                    onClicked: Audio.setDefault(ds.node)
                                }
                            }
                            // only the selected device carries signal
                            Meter { visible: ds.current; node: ds.node }
                        }

                        // a live level bar; the monitor is a real pipewire
                        // stream, so it is created only while the panel is open
                        component Meter: Rectangle {
                            id: mt
                            property var node: null

                            // quickshell always opens a stereo capture, so a mono
                            // node (most voice apps record mono) reads a flat zero
                            // and logs an error per attempt. Nothing to draw, so
                            // draw nothing rather than a bar that never moves.
                            readonly property bool meterable:
                                (mt.node?.audio?.channels?.length ?? 0) >= 2

                            visible: mt.meterable
                            width: audCol.width
                            height: 4
                            radius: 2
                            color: Theme.track

                            PwNodePeakMonitor {
                                id: mon
                                node: mt.meterable ? mt.node : null
                                enabled: Audio.panelOpen && mt.meterable
                            }
                            Rectangle {
                                width: parent.width * Math.min(1, mon.peak)
                                height: parent.height
                                radius: 2
                                color: mon.peak > 0.9 ? Theme.urgent : Theme.ok
                                Behavior on width { NumberAnimation { duration: 80 } }
                            }
                        }

                        // an application stream: what it is, and its own volume
                        component AppRow: Column {
                            id: ar
                            property var node: null
                            readonly property var na: ar.node?.audio ?? null

                            width: audCol.width
                            spacing: 4

                            Item {
                                width: parent.width
                                height: 20

                                Text {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                    width: parent.width - 24
                                    elide: Text.ElideRight
                                    text: Audio.appName(ar.node)
                                        + (Audio.appDetail(ar.node) ? "  \u00b7  " + Audio.appDetail(ar.node) : "")
                                    font.family: Theme.font; font.pixelSize: 12
                                    color: Theme.text
                                }
                                Icon {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    visible: ar.na !== null
                                    name: ar.na && ar.na.muted ? "volume-off" : "volume-high"
                                    size: 14
                                    color: ar.na && ar.na.muted ? Theme.urgent : Theme.dim
                                    MouseArea {
                                        anchors { fill: parent; margins: -6 }
                                        onClicked: if (ar.na) ar.na.muted = !ar.na.muted
                                    }
                                }
                            }
                            ValueSlider {
                                visible: ar.na !== null
                                width: audCol.width
                                label: ""
                                suffix: "%"
                                maxValue: 150
                                value: ar.na ? Math.round(ar.na.volume * 100) : 0
                                onCommit: v => { if (ar.na) ar.na.volume = v / 100; }
                            }
                            Meter { node: ar.node }
                        }

                        // ---- output ----
                        AudHead { label: "output"; target: Audio.sink }

                        Repeater {
                            model: Audio.sinks
                            DevSlider { node: modelData; current: modelData === Audio.sink }
                        }

                        AudDiv {}

                        // ---- input ----
                        AudHead { label: "input"; target: Audio.source }

                        Repeater {
                            model: Audio.sources
                            DevSlider { node: modelData; current: modelData === Audio.source }
                        }

                        // ---- apps playing ----
                        AudDiv { visible: Audio.playing.length > 0 }
                        Item {
                            visible: Audio.playing.length > 0
                            width: audCol.width
                            height: 20

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "playing"
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.dim
                            }
                            PillBtn {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: "reset"
                                onPressed: Audio.resetAppLevels()
                            }
                        }
                        Repeater {
                            model: Audio.playing
                            AppRow { node: modelData }
                        }

                        // ---- apps on the mic ----
                        AudDiv { visible: Audio.capturing.length > 0 }
                        Text {
                            visible: Audio.capturing.length > 0
                            text: "using mic"
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.warn
                        }
                        Repeater {
                            model: Audio.capturing
                            AppRow { node: modelData }
                        }
                    }
                }
            }

            // ---- network panel (click net cell) ----
            PanelWindow {
                id: networkPopout

                readonly property real sourceX: panel.pos(rightRow) + panel.pos(powerIsland) + panel.pos(netCell)
                readonly property real sourceWidth: panel.ext(netCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: netPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                // Keyboard only while a passphrase field is actually showing.
                // Asking for it whenever the panel was open made this the one
                // popout that did not close on a second click of its cell:
                // Hyprland focuses a layer that wants keys the moment it maps,
                // and with the pointer parked on the cell that focus stayed on
                // the panel — the second click never reached the bar. OnDemand,
                // not Exclusive, so the compositor's own bindings keep working
                // while the field is up.
                // Hyprland only hands an OnDemand layer focus on map or on a click
                // into it; flipping the mode after the row click is ignored, so the
                // grab is what actually moves the keyboard here.
                property bool wantKeys: false
                WlrLayershell.keyboardFocus: netPopout.open && wantKeys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                HyprlandFocusGrab {
                    windows: [networkPopout]
                    active: netPopout.open && networkPopout.wantKeys
                    onCleared: netPopout.open = false
                }
                implicitWidth: 320
                implicitHeight: netCol.implicitHeight + 28
                color: "transparent"

                // five-step strength glyph, same ladder as the bar cell
                function bars(v) {
                    if (v >= 0.75) return "wifi-strength-4";
                    if (v >= 0.5) return "wifi-strength-3";
                    if (v >= 0.25) return "wifi-strength-2";
                    if (v > 0) return "wifi-strength-1";
                    return "wifi-strength-outline";
                }

                AttachedPanel {
                    anchors.fill: parent
                    shown: netPopout.open
                    neckX: networkPopout.sourceX - networkPopout.popupX
                    neckWidth: networkPopout.sourceWidth

                    Column {
                        id: netCol
                        width: parent.width
                        spacing: 8

                        Text {
                            text: Sys.netLabel
                            font.family: Theme.font; font.pixelSize: 15
                            color: Theme.bright
                        }
                        Text {
                            text: Sys.netUp
                                ? [Sys.netIp,
                                   Sys.wifiNetwork ? WifiSecurityType.toString(Sys.wifiNetwork.security) : "wired",
                                   Sys.wifiNetwork ? Math.round(Sys.wifiNetwork.signalStrength * 100) + "%" : ""
                                  ].filter(x => x).join("  ·  ")
                                : "no connection"
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                        }

                        // a wired-only box has nothing below the header worth drawing
                        Rectangle {
                            visible: Sys.wifiDevice !== null
                            width: netCol.width; height: 1; color: Theme.islandBorder
                        }

                        ToggleRow {
                            visible: Sys.wifiDevice !== null
                            label: "wifi"
                            checked: Networking.wifiEnabled
                            onToggled: value => Networking.wifiEnabled = value
                        }

                        Rectangle {
                            visible: Sys.wifiDevice !== null && Networking.wifiEnabled
                            width: netCol.width; height: 1; color: Theme.islandBorder
                        }

                        Text {
                            visible: Networking.wifiEnabled && Sys.wifiList.length === 0
                            text: "scanning…"
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                        }

                        // capped height with a scroll rather than a truncated list:
                        // a crowded band can turn up 30 APs and the weak one at the
                        // bottom is often exactly the one being looked for
                        Flickable {
                            id: netScroll
                            width: netCol.width
                            height: Math.min(contentHeight, 260)
                            contentHeight: netList.implicitHeight
                            clip: true
                            SmoothScroll { flick: netScroll }

                            Column {
                                id: netList
                                width: parent.width
                                spacing: 4

                                Repeater {
                                    model: Sys.wifiList

                                    Column {
                                        id: netRow

                                        readonly property var net: modelData
                                        readonly property bool secured: net.security !== WifiSecurityType.Open
                                        readonly property bool unfolded: netPopout.expanded === net.name
                                        readonly property bool secretShown: Sys.secretSsid === net.name
                                        property string pskText: ""
                                        property bool qrShown: false
                                        property bool reveal: false
                                        property string failMsg: ""

                                        // NM rejects a bad key asynchronously; without this the row
                                        // just flickers back to disconnected and says nothing
                                        Connections {
                                            target: netRow.net
                                            function onConnectionFailed(reason) {
                                                netRow.failMsg = ConnectionFailReason.toString(reason);
                                            }
                                            function onConnectedChanged() {
                                                if (netRow.net.connected) netRow.failMsg = "";
                                            }
                                        }

                                        width: netList.width
                                        spacing: 6

                                        function join(psk) {
                                            if (!psk) return;
                                            netRow.failMsg = "";
                                            netRow.net.connectWithPsk(psk);
                                        }

                                        Item {
                                            width: parent.width
                                            height: 24

                                            Row {
                                                anchors { left: parent.left; right: marks.left; verticalCenter: parent.verticalCenter; rightMargin: 6 }
                                                spacing: 8

                                                Icon {
                                                    name: networkPopout.bars(netRow.net.signalStrength)
                                                    size: 15
                                                    color: netRow.net.connected ? Theme.accent : Theme.text
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    width: Math.max(0, parent.width - 26)
                                                    text: netRow.net.name
                                                    elide: Text.ElideRight
                                                    font.family: Theme.font; font.pixelSize: 12
                                                    color: netRow.net.connected ? Theme.bright : Theme.text
                                                }
                                            }
                                            Row {
                                                id: marks
                                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                                spacing: 6

                                                Text {
                                                    visible: netRow.net.stateChanging
                                                    text: "…"
                                                    font.family: Theme.font; font.pixelSize: 12
                                                    color: Theme.warn
                                                }
                                                Icon {
                                                    visible: netRow.secured
                                                    name: "lock"
                                                    size: 13
                                                    color: netRow.net.known ? Theme.text : Theme.dim
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Icon {
                                                    name: netRow.unfolded ? "chevron-up" : "chevron-down"
                                                    size: 13
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: Theme.dim
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    const name = netRow.net.name;
                                                    netPopout.expanded = netPopout.expanded === name ? "" : name;
                                                    netRow.reveal = false;
                                                    netRow.qrShown = false;
                                                    netRow.failMsg = "";
                                                    Sys.loadSecret("");
                                                }
                                            }
                                        }

                                        // ---- detail ----
                                        Column {
                                            visible: netRow.unfolded
                                            width: parent.width - 22
                                            x: 22
                                            spacing: 6

                                            // passphrase — only when there is no saved key to reuse
                                            Row {
                                                visible: netRow.secured && !netRow.net.known
                                                spacing: 6

                                                Rectangle {
                                                    width: 140; height: 24; radius: 4
                                                    color: Theme.track

                                                    TextInput {
                                                        anchors { fill: parent; margins: 6 }
                                                        font.family: Theme.font; font.pixelSize: 11
                                                        color: Theme.bright
                                                        echoMode: netRow.reveal ? TextInput.Normal : TextInput.Password
                                                        clip: true
                                                        // the surface takes focus on click, but nothing
                                                        // hands it to the field inside the delegate
                                                        onVisibleChanged: {
                                                            networkPopout.wantKeys = visible;
                                                            if (visible) forceActiveFocus();
                                                        }
                                                        onTextChanged: netRow.pskText = text
                                                        Keys.onReturnPressed: netRow.join(netRow.pskText)
                                                        Keys.onEscapePressed: panel.closeIslandPopouts()
                                                    }
                                                }
                                                PillBtn {
                                                    text: netRow.reveal ? "hide" : "show"
                                                    onPressed: netRow.reveal = !netRow.reveal
                                                }
                                                PillBtn {
                                                    text: "join"
                                                    active: netRow.pskText !== ""
                                                    onPressed: netRow.join(netRow.pskText)
                                                }
                                            }

                                            // saved key, revealed on request
                                            Row {
                                                visible: netRow.net.known && netRow.secured
                                                spacing: 6

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: netRow.secretShown && netRow.reveal
                                                        ? (Sys.secretPsk || "no saved key")
                                                        : "••••••••"
                                                    font.family: Theme.font; font.pixelSize: 11
                                                    color: Theme.text
                                                }
                                                PillBtn {
                                                    text: netRow.secretShown && netRow.reveal ? "hide" : "password"
                                                    onPressed: {
                                                        if (netRow.secretShown && netRow.reveal) {
                                                            netRow.reveal = false;
                                                        } else {
                                                            netRow.reveal = true;
                                                            Sys.loadSecret(netRow.net.name);
                                                        }
                                                    }
                                                }
                                                PillBtn {
                                                    visible: Sys.hasQrencode
                                                    text: "qr"
                                                    active: netRow.qrShown
                                                    onPressed: {
                                                        netRow.qrShown = !netRow.qrShown;
                                                        if (netRow.qrShown) Sys.loadSecret(netRow.net.name);
                                                    }
                                                }
                                            }

                                            Image {
                                                visible: netRow.qrShown && netRow.secretShown && Sys.qrPath !== ""
                                                source: Sys.qrPath ? "file://" + Sys.qrPath : ""
                                                // the path is stable across regenerations, so the
                                                // cache would keep serving the previous network's code
                                                cache: false
                                                fillMode: Image.PreserveAspectFit
                                                width: 150; height: 150
                                                smooth: false
                                            }

                                            Text {
                                                visible: netRow.failMsg !== ""
                                                width: parent.width
                                                wrapMode: Text.WordWrap
                                                text: netRow.failMsg
                                                font.family: Theme.font; font.pixelSize: 11
                                                color: Theme.urgent
                                            }

                                            Row {
                                                spacing: 6

                                                PillBtn {
                                                    text: netRow.net.connected ? "disconnect" : "connect"
                                                    active: netRow.net.connected
                                                    visible: netRow.net.known || !netRow.secured
                                                    onPressed: netRow.net.connected ? netRow.net.disconnect() : netRow.net.connect()
                                                }
                                                PillBtn {
                                                    visible: netRow.net.known
                                                    text: "forget"
                                                    onPressed: {
                                                        netRow.net.forget();
                                                        netPopout.expanded = "";
                                                        Sys.loadSecret("");
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    }
                }
            }

            // ---- resource panel (click resource island) ----
            PanelWindow {
                id: resourcePopout

                readonly property real sourceX: panel.pos(leftRow) + panel.pos(svcWrap) + panel.pos(sysCells)
                readonly property real sourceWidth: panel.ext(sysCells)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: sysPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 320
                implicitHeight: resourceCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: sysPopout.open
                    neckX: resourcePopout.sourceX - resourcePopout.popupX
                    neckWidth: resourcePopout.sourceWidth

                    Column {
                        id: resourceCol

                        width: parent.width
                        spacing: 8

                        component ResourceMeter: Item {
                            property string label
                            property real value // 0..1
                            property string detail: Math.round(value * 100) + "%"

                            width: resourceCol.width
                            height: 18

                            Text {
                                text: label
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                anchors { right: rvalue.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 100; height: 4; radius: 2
                                color: Theme.track
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, value))
                                    height: parent.height; radius: 2
                                    color: Theme.accent
                                }
                            }
                            Text {
                                id: rvalue
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: detail
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.dim
                            }
                        }

                        component ResourceInfoRow: Item {
                            property string label
                            property string value

                            width: resourceCol.width
                            height: 16

                            Text {
                                text: label
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.text
                            }
                            Text {
                                anchors.right: parent.right
                                text: value
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.dim
                            }
                        }

                        ResourceMeter { label: "cpu"; value: Sys.cpu }
                        ResourceInfoRow { label: "mem"; value: Sys.memText }
                        ResourceInfoRow { visible: Sys.swapText !== ""; label: "swap"; value: Sys.swapText }
                        ResourceInfoRow { label: "disk free"; value: Sys.diskFree }
                        ResourceInfoRow { label: "net"; value: Sys.netText }
                    }
                }
            }

            // ---- clanker panel (click the robot cell) ----
            // omarchy's agents panel, in this bar's idiom: tab chips per
            // agent, plan line, limit meters with reset countdowns, then
            // tokens by day and by model. Hover a token row for the split.
            PanelWindow {
                id: clankerPanel

                readonly property real sourceX: panel.pos(leftRow) + panel.pos(svcWrap) + panel.pos(clankerCell)
                readonly property real sourceWidth: panel.ext(clankerCell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)
                readonly property var a: Clanker.agent

                visible: clankerPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 340
                implicitHeight: clankerCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: clankerPopout.open
                    neckX: clankerPanel.sourceX - clankerPanel.popupX
                    neckWidth: clankerPanel.sourceWidth

                    Column {
                        id: clankerCol
                        width: parent.width
                        spacing: 8

                        // label left, bar + value right; hover text swaps the value
                        component TokenRow: Item {
                            property string label
                            property real value       // 0..1 of the heaviest row
                            property string detail
                            property string hover: ""
                            property bool bold: false
                            width: clankerCol.width
                            height: 16
                            Text {
                                text: label
                                font.family: Theme.font; font.pixelSize: 11; font.bold: bold
                                color: Theme.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                anchors { right: tvalue.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                width: 90; height: 4; radius: 2
                                color: Theme.track
                                Rectangle { width: parent.width * Math.max(0, Math.min(1, value)); height: parent.height; radius: 2; color: Theme.accent }
                            }
                            Text {
                                id: tvalue
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: tHover.containsMouse && hover !== "" ? hover : detail
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.dim
                            }
                            MouseArea { id: tHover; anchors.fill: parent; hoverEnabled: true }
                        }
                        component SectionHead: Text {
                            font.family: Theme.font; font.pixelSize: 10
                            color: Theme.dim
                            topPadding: 4
                        }

                        // tab chips: only when there is something to switch between
                        Item {
                            visible: Clanker.agents.length > 1
                            width: clankerCol.width; height: 22
                            Row {
                                spacing: 14
                                Repeater {
                                    model: Clanker.agents
                                    Item {
                                        required property var modelData
                                        required property int index
                                        readonly property bool on: index === Clanker.current
                                        width: tabText.width; height: 22
                                        Text {
                                            id: tabText
                                            text: modelData.name || modelData.id
                                            font.family: Theme.font; font.pixelSize: 11; font.bold: on
                                            color: on ? Theme.bright : Theme.dim
                                        }
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width; height: 2
                                            color: Theme.accent
                                            visible: on
                                        }
                                        MouseArea { anchors.fill: parent; onClicked: Clanker.select(modelData.id) }
                                    }
                                }
                            }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.track }
                        }

                        // hero: name + plan, or the auth problem in its place
                        Item {
                            width: clankerCol.width; height: 30
                            Icon { id: heroIcon; name: clankerPanel.a ? "agent-" + clankerPanel.a.id : "robot"; size: 22; color: Theme.bright; anchors.verticalCenter: parent.verticalCenter }
                            Column {
                                anchors { left: heroIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                Text {
                                    text: clankerPanel.a ? clankerPanel.a.name : ""
                                    font.family: Theme.font; font.pixelSize: 13; font.bold: true
                                    color: Theme.bright
                                }
                                Text {
                                    readonly property string status: clankerPanel.a ? (clankerPanel.a.usageStatusText || "") : ""
                                    text: status !== "" ? status : (clankerPanel.a ? (clankerPanel.a.tierLabel || "") : "")
                                    font.family: Theme.font; font.pixelSize: 11
                                    color: status !== "" ? Theme.warn : Theme.dim
                                }
                            }
                            Icon {
                                name: "refresh"; size: 14; color: Theme.dim
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                MouseArea { anchors.fill: parent; onClicked: Clanker.refresh() }
                            }
                        }

                        // limits could not be fetched: say how to fix it
                        Rectangle {
                            readonly property string help: clankerPanel.a && clankerPanel.a.usageStatusText ? (clankerPanel.a.authHelpText || "") : ""
                            visible: help !== ""
                            width: clankerCol.width; height: helpText.height + 12; radius: 6
                            color: Theme.track
                            Text {
                                id: helpText
                                x: 8; y: 6; width: parent.width - 16
                                text: parent.help
                                wrapMode: Text.WordWrap
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.warn
                            }
                        }

                        // limits: % of each allowance and the time to reset
                        Repeater {
                            model: clankerPanel.a ? (clankerPanel.a.limits || []) : []
                            TokenRow {
                                required property var modelData
                                readonly property real pct: Number(modelData.percent)
                                readonly property string reset: Clanker.untilText(modelData.resetsAt)
                                label: modelData.title || modelData.label
                                value: pct
                                detail: (pct >= 0 ? Math.round(pct * 100) + "%" : "--") + (reset !== "" ? "  ·  " + reset : "")
                            }
                        }

                        // prepaid agents report a balance instead of limits
                        TokenRow {
                            readonly property var b: clankerPanel.a ? clankerPanel.a.balance : null
                            visible: !!b
                            label: "balance"
                            value: b && b.funded > 0 ? b.remaining / b.funded : 0
                            detail: b ? b.remaining.toFixed(2) + " " + (b.currency || "") + (b.estimated ? " ~" : "") : ""
                            hover: b ? b.spent.toFixed(2) + " of " + b.funded.toFixed(2) + " spent" : ""
                        }

                        // tokens by day, last week, today bold at the bottom
                        SectionHead {
                            visible: dayRep.count > 0
                            readonly property var hosts: clankerPanel.a ? (clankerPanel.a.hosts || []) : []
                            text: "tokens by day" + (hosts.length > 1 ? "  ·  " + hosts.join(" + ") : "")
                        }
                        Repeater {
                            id: dayRep
                            readonly property var days: clankerPanel.a ? (clankerPanel.a.recentDays || []) : []
                            readonly property real peak: days.reduce((m, d) => Math.max(m, Number(d.messageCount) || 0), 0)
                            model: days
                            TokenRow {
                                required property var modelData
                                required property int index
                                readonly property bool today: modelData.date === Clanker.todayStr()
                                label: new Date(modelData.date + "T00:00").toLocaleDateString(Qt.locale(), "ddd d")
                                bold: today
                                value: dayRep.peak > 0 ? (Number(modelData.messageCount) || 0) / dayRep.peak : 0
                                detail: Clanker.tokText(modelData.messageCount)
                                hover: today && clankerPanel.a ? clankerPanel.a.todayPrompts + " prompts · " + clankerPanel.a.todaySessions + " sessions" : ""
                            }
                        }

                        // tokens by model, heaviest first, hover for the split
                        SectionHead { visible: modelRep.count > 0; text: "tokens by model" }
                        Repeater {
                            id: modelRep
                            readonly property var rows: {
                                const mu = clankerPanel.a ? (clankerPanel.a.modelUsage || {}) : {};
                                const out = [];
                                for (const k in mu) {
                                    const u = mu[k];
                                    const total = (u.inputTokens || 0) + (u.outputTokens || 0) + (u.cacheCreationInputTokens || 0) + (u.cacheReadInputTokens || 0);
                                    out.push({ model: k, total: total, u: u });
                                }
                                out.sort((x, y) => y.total - x.total);
                                return out;
                            }
                            readonly property real peak: rows.length ? rows[0].total : 0
                            model: rows
                            TokenRow {
                                required property var modelData
                                label: modelData.model
                                value: modelRep.peak > 0 ? modelData.total / modelRep.peak : 0
                                detail: Clanker.tokText(modelData.total)
                                hover: "in " + Clanker.tokText(modelData.u.inputTokens) + " · out " + Clanker.tokText(modelData.u.outputTokens)
                                    + " · cache " + Clanker.tokText((modelData.u.cacheCreationInputTokens || 0) + (modelData.u.cacheReadInputTokens || 0))
                            }
                        }
                    }
                }
            }

            // ---- docker / vm popouts (click their cells) ----
            // Same list shape for both: name left, status right, a line of
            // dim text when there is nothing to list.
            component ListPopout: PanelWindow {
                id: lp
                property bool open: false
                property Item cell
                property string title
                property var rows: []      // [{ name, status }]
                property string empty: "nothing running"

                readonly property real sourceX: panel.pos(leftRow) + panel.pos(svcWrap) + panel.pos(cell)
                readonly property real sourceWidth: panel.ext(cell)
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, panel.vertical ? implicitHeight : implicitWidth)

                visible: open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.popoutTop(popupX, implicitWidth, implicitHeight); left: panel.popoutLeft(popupX, implicitWidth, implicitHeight) }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 320
                implicitHeight: lpCol.implicitHeight + 28
                color: "transparent"

                AttachedPanel {
                    anchors.fill: parent
                    shown: lp.open
                    neckX: lp.sourceX - lp.popupX
                    neckWidth: lp.sourceWidth

                    Column {
                        id: lpCol
                        width: parent.width
                        spacing: 6

                        Text {
                            text: lp.title
                            font.family: Theme.font; font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Theme.bright
                        }
                        Text {
                            visible: lp.rows.length === 0
                            text: lp.empty
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
                        }
                        Repeater {
                            model: lp.rows
                            // Two lines: the name is what you opened this for
                            // and container names run long, so it gets the
                            // whole width; the status sits under it.
                            Column {
                                required property var modelData
                                width: lpCol.width
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    font.family: Theme.font; font.pixelSize: 11
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.status
                                    font.family: Theme.font; font.pixelSize: 10
                                    color: Theme.dim
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

            ListPopout {
                open: dockerPopout.open
                cell: dockerCell
                title: "docker"
                rows: Sys.dockerList
                empty: Sys.dockerUp ? "no containers running" : "daemon is down"
            }
            ListPopout {
                open: vmPopout.open
                cell: vmCell
                title: "virtual machines"
                rows: Sys.vmList
                empty: "no vms running"
            }

        }
            // ---- bezel chrome: band, stubs, concave corner fillets ----
            // Own layer surface so hyprglass (which whitelists "quickshell")
            // never refracts the thin chrome; input-masked to stay click-through.
            PanelWindow {
                id: bezelWin

                visible: panel.bezelMapped
                screen: panel.screen
                anchors {
                    top: panel.vertical || ShellState.side === "top"
                    bottom: panel.vertical || ShellState.side === "bottom"
                    left: !panel.vertical || ShellState.side === "left"
                    right: !panel.vertical || ShellState.side === "right"
                }
                implicitHeight: panel.barHeight
                implicitWidth: panel.barHeight
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell-frame"
                mask: Region {}

                Item {
                    id: bezelChrome
                    // full edge length: this window reaches the screen corners
                    width: panel.vertical ? bezelWin.height : bezelWin.width
                    height: panel.barHeight
                    transform: Matrix4x4 { matrix: panel.chromeMatrix }
                    readonly property real bT: Theme.frameT
                    readonly property real bf: Theme.frameFillet
                    readonly property real bW: width
                    // the bar panel is inset by the other strips' exclusive zones;
                    // this window is not, so island positions shift by the inset
                    readonly property real off: (bW - panel.along) / 2
                    readonly property real bH: panel.barHeight

                    // band line segments between the hanging capsules
                    readonly property var bandSegs: {
                        const nf = panel.notchFillet;
                        const gaps = panel.islandGeom.filter(i => i[2])
                            .map(i => [i[0] - nf + off, i[0] + i[1] + nf + off])
                            .sort((a, b) => a[0] - b[0]);
                        const merged = [];
                        for (const g of gaps) {
                            if (merged.length && g[0] <= merged[merged.length - 1][1])
                                merged[merged.length - 1][1] = Math.max(merged[merged.length - 1][1], g[1]);
                            else
                                merged.push(g);
                        }
                        const segs = [];
                        let x = bT + bf;
                        for (const g of merged) {
                            if (g[0] > x) segs.push([x, Math.min(g[0], bW - bT - bf)]);
                            x = Math.max(x, g[1]);
                        }
                        if (x < bW - bT - bf) segs.push([x, bW - bT - bf]);
                        return segs;
                    }

                    // band + stubs
                    Rectangle { width: bezelChrome.bW; height: bezelChrome.bT; color: Theme.island }
                    Rectangle { width: bezelChrome.bT; height: bezelChrome.bH; color: Theme.island }
                    Rectangle { x: bezelChrome.bW - bezelChrome.bT; width: bezelChrome.bT; height: bezelChrome.bH; color: Theme.island }

                    // stub walls
                    Rectangle { x: bezelChrome.bT - 1; y: bezelChrome.bT + bezelChrome.bf; width: 1; height: bezelChrome.bH - bezelChrome.bT - bezelChrome.bf; color: Theme.islandBorder }
                    Rectangle { x: bezelChrome.bW - bezelChrome.bT; y: bezelChrome.bT + bezelChrome.bf; width: 1; height: bezelChrome.bH - bezelChrome.bT - bezelChrome.bf; color: Theme.islandBorder }

                    // band line with gaps where the capsules hang
                    Repeater {
                        model: bezelChrome.bandSegs
                        Rectangle {
                            required property var modelData
                            x: modelData[0]; y: bezelChrome.bT; width: modelData[1] - modelData[0]; height: 1
                            color: Theme.islandBorder
                        }
                    }

                    // concave corner fillets
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: "transparent"; fillColor: Theme.island
                            startX: bezelChrome.bT; startY: bezelChrome.bT + bezelChrome.bf
                            PathArc { x: bezelChrome.bT + bezelChrome.bf; y: bezelChrome.bT; radiusX: bezelChrome.bf; radiusY: bezelChrome.bf }
                            PathLine { x: bezelChrome.bT; y: bezelChrome.bT }
                        }
                        ShapePath {
                            strokeColor: Theme.islandBorder; strokeWidth: 1; fillColor: "transparent"
                            startX: bezelChrome.bT; startY: bezelChrome.bT + bezelChrome.bf
                            PathArc { x: bezelChrome.bT + bezelChrome.bf; y: bezelChrome.bT; radiusX: bezelChrome.bf; radiusY: bezelChrome.bf }
                        }
                        ShapePath {
                            strokeColor: "transparent"; fillColor: Theme.island
                            startX: bezelChrome.bW - bezelChrome.bT - bezelChrome.bf; startY: bezelChrome.bT
                            PathArc { x: bezelChrome.bW - bezelChrome.bT; y: bezelChrome.bT + bezelChrome.bf; radiusX: bezelChrome.bf; radiusY: bezelChrome.bf }
                            PathLine { x: bezelChrome.bW - bezelChrome.bT; y: bezelChrome.bT }
                        }
                        ShapePath {
                            strokeColor: Theme.islandBorder; strokeWidth: 1; fillColor: "transparent"
                            startX: bezelChrome.bW - bezelChrome.bT - bezelChrome.bf; startY: bezelChrome.bT
                            PathArc { x: bezelChrome.bW - bezelChrome.bT; y: bezelChrome.bT + bezelChrome.bf; radiusX: bezelChrome.bf; radiusY: bezelChrome.bf }
                        }
                    }
                }

            }
        }
    }
}
