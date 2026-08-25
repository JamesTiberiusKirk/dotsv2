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
            anchors { top: true; left: true; right: true }
            readonly property int barBodyHeight: Theme.barBody
            readonly property int barHeight: barBodyHeight + Theme.frameT

            implicitHeight: barHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Normal
            // hidden: islands slide up into the band and fade, windows reclaim
            // the bar body; the thin frame stays (bezelWin), like the bottom strip
            exclusiveZone: ShellState.hidden ? Theme.frameT : barHeight
            // hidden: windows reclaim the bar body, so drop the input region
            // too — otherwise the invisible surface eats clicks in that strip
            mask: Region {
                width: ShellState.hidden ? 0 : panel.width
                height: ShellState.hidden ? 0 : panel.barHeight
            }

            // shared island entrance/exit: transform + opacity only (GPU),
            // no Canvas repaints during the animation
            property real islandFade: ShellState.hidden ? 0 : 1
            Behavior on islandFade { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            property real islandLift: ShellState.hidden ? -(barBodyHeight * 0.7) : 0
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
            QtObject { id: sysPopout; property bool open: false }
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
                dispPopout.open = false;
                pwrPopout.open = false;
                netPopout.open = false;
                audPopout.open = false;
                btPopout.open = false;
                tsPopout.open = false;
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

            function attachedPanelX(sourceX, sourceWidth, popupWidth) {
                const gutter = Theme.frameT + Theme.frameFillet + 8;
                return clamp(sourceX + sourceWidth / 2 - popupWidth / 2,
                             gutter,
                             panel.width - popupWidth - gutter);
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
            component Cell: Item {
                id: cell

                property string icon: ""
                property alias text: cellLabel.text
                property alias font: cellLabel.font
                property color color: Theme.text
                property int leftPadding: 8
                property int rightPadding: 8

                implicitWidth: cellRow.implicitWidth + leftPadding + rightPadding
                implicitHeight: Theme.fontSize + 14

                Row {
                    id: cellRow

                    anchors {
                        left: parent.left
                        leftMargin: cell.leftPadding
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 5

                    Icon {
                        name: cell.icon
                        color: cell.color
                        // Row drops invisible children and their spacing, so a
                        // label-only Cell costs no leading gap
                        visible: cell.icon !== ""
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id: cellLabel

                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: cell.color
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // [x, width, visible] per island in panel coords — reactive,
            // shared by the capsule canvas (this window) and the bezel window
            readonly property var islandGeom: [
                [leftRow.x + wsIsland.x, wsIsland.width, wsIsland.visible],
                [leftRow.x + svcWrap.x, svcWrap.width, svcWrap.visible],
                [titleIsland.x, titleIsland.width, titleIsland.visible],
                [rightRow.x + statusWrap.x, statusIsland.width, true],
                [rightRow.x + powerIsland.x, powerIsland.width, powerIsland.visible],
                [rightRow.x + trayIsland.x, trayIsland.width, trayIsland.visible]
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
                transform: Translate { y: panel.islandLift }
                width: panel.width
                height: panel.implicitHeight

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
            Row {
                id: leftRow
                visible: opacity > 0
                opacity: panel.islandFade
                transform: Translate { y: panel.islandLift }
                anchors { left: parent.left; top: parent.top; leftMargin: Theme.frameT + Theme.frameFillet + 12; topMargin: Theme.frameT }
                spacing: 10

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
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
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
                        visible: panel.submap !== ""
                        text: panel.submap.toUpperCase()
                        color: Theme.urgent
                    }
                }

                // services + system stats (the old inline waybar modules)
                MouseArea {
                    id: svcWrap

                    width: svcIsland.implicitWidth
                    height: svcIsland.implicitHeight
                    onClicked: {
                        const next = !sysPopout.open;
                        panel.closeIslandPopouts();
                        sysPopout.open = next;
                    }

                    Island {
                        id: svcIsland

                        width: svcWrap.width
                        height: panel.barBodyHeight

                        // Both always shown. Greyed docker means the daemon is
                        // down; normal colour with a 0 means it is up and idle.
                        Cell { icon: "docker"; text: Sys.docker; color: Sys.dockerUp ? Theme.text : Theme.dim }
                        // server, not the memory chip it used to be — that glyph
                        // sat next to the CPU and RAM cells reading as a third one
                        Cell { icon: "server"; text: Sys.vm }
                        Cell { icon: "cpu-64-bit"; text: Math.round(Sys.cpu * 100) + "%" }
                        Cell { visible: Sys.memText !== ""; icon: "memory"; text: Sys.memText }
                        Cell { visible: Sys.diskFree !== ""; icon: "harddisk"; text: Sys.diskFree }
                    }
                }
            }

            // ---- center: window carousel ----
            // All windows on this screen's active workspace as pills; the
            // focused one is highlighted and the strip slides to keep it
            // centered. Clicking a pill focuses that window.
            Island {
                id: titleIsland
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Theme.frameT }
                visible: opacity > 0 && carousel.wins.length > 0
                opacity: panel.islandFade
                transform: Translate { y: panel.islandLift }

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

                    width: Math.min(strip.width, panel.width * 0.4)
                    height: panel.barBodyHeight
                    clip: true

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
                            strip.x = width / 2 - (it.x + it.width / 2);
                        else if (wins.length === 0)
                            strip.x = 0;
                    }
                    onActiveIndexChanged: recenter()
                    onWidthChanged: recenter()

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

            // ---- right: status cluster + audio/power + tray/clock ----
            Row {
                id: rightRow
                visible: opacity > 0
                opacity: panel.islandFade
                transform: Translate { y: panel.islandLift }
                anchors { right: parent.right; top: parent.top; rightMargin: Theme.frameT + Theme.frameFillet + 12; topMargin: Theme.frameT }
                spacing: 10

                Item {
                    id: statusWrap

                    width: statusIsland.implicitWidth
                    height: statusIsland.implicitHeight

                    Island {
                        id: statusIsland

                        width: statusWrap.width
                        height: statusWrap.height

                        // network — click opens the wifi panel
                        Cell {
                            id: netCell
                            icon: Sys.netIcon
                            text: Sys.netLabel
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
                            text: Sys.tsUp ? Sys.tsNode : ""
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
                            color: Theme.bright
                        }
                        Cell { visible: Sys.latency !== ""; icon: "timer-outline"; text: Sys.latency }
                    }
                }

                Island {
                    id: powerIsland
                    // battery — click opens the power-profile panel
                    Cell {
                        id: batteryCell
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
                        visible: Sys.backlight >= 0
                        // On the Duo the sun becomes two stacked halves, one per
                        // panel, so the bar says at a glance whether the bottom
                        // screen is still lit under the keyboard. Drawn, not a
                        // glyph: Theme.font is a Nerd Font that is not actually
                        // installed here, and half-block characters are exactly
                        // the kind of thing a fallback face renders wrong.
                        leftPadding: Sys.isDuo ? 22 : 8
                        icon: Sys.isDuo ? "" : "white-balance-sunny"
                        text: Math.round(Sys.backlight * 100) + "%"

                        Item {
                            visible: Sys.isDuo
                            width: 10
                            height: 14
                            anchors {
                                left: parent.left
                                leftMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
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
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        leftPadding: 8
                        Repeater {
                            model: SystemTray.items.values
                            IconImage {
                                id: trayIcon
                                required property var modelData
                                width: 16; height: 16
                                anchors.verticalCenter: parent.verticalCenter
                                source: modelData.icon
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: e => {
                                        panel.closeIslandPopouts();
                                        if (e.button === Qt.LeftButton) {
                                            trayIcon.modelData.activate();
                                        } else if (trayIcon.modelData.hasMenu) {
                                            trayMenu.menu = trayIcon.modelData.menu;
                                            trayMenu.anchor.rect.x = trayIcon.mapToItem(null, 0, 0).x;
                                            trayMenu.anchor.rect.y = panel.implicitHeight;
                                            trayMenu.open();
                                        } else {
                                            trayIcon.modelData.secondaryActivate();
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // notification bell → history panel
                    Cell {
                        id: notifBellCell

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

                        text: Qt.formatDateTime(clock.date, "ddd d · HH:mm")
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
                visible: calPopout.open || sysPopout.open || dispPopout.open || pwrPopout.open || netPopout.open || audPopout.open || btPopout.open || tsPopout.open
                screen: panel.screen
                anchors { top: true; left: true; right: true; bottom: true }
                margins { top: panel.barHeight }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "quickshell-backdrop"

                MouseArea {
                    anchors.fill: parent
                    onClicked: panel.closeIslandPopouts()
                }
            }

            // ---- calendar popout (click clock) ----
            // layer surface (not xdg popup) so hyprland's blur layerrule applies
            PanelWindow {
                id: calPopout

                property bool open: false
                property date shown: new Date()
                readonly property real sourceX: rightRow.x + trayIsland.x + clockCell.x
                readonly property real sourceWidth: clockCell.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)
                onOpenChanged: if (open) shown = new Date()

                visible: open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
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

                readonly property real sourceX: rightRow.x + powerIsland.x + backlightCell.x
                readonly property real sourceWidth: backlightCell.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                visible: dispPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
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

                readonly property real sourceX: rightRow.x + powerIsland.x + batteryCell.x
                readonly property real sourceWidth: batteryCell.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                readonly property var dev: Sys.batteryDevice
                readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false

                visible: pwrPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
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

                readonly property real sourceX: rightRow.x + statusWrap.x + tsCell.x
                readonly property real sourceWidth: tsCell.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                visible: tsPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
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

                        ToggleRow {
                            label: "tailscale"
                            checked: Sys.tsUp
                            onToggled: value => Sys.tsSetUp(value)
                        }
                        Text {
                            visible: Sys.tsUp
                            width: tsCol.width
                            elide: Text.ElideRight
                            text: Sys.tsNode + "  \u00b7  " + Sys.tsIp
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.dim
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

                                        Text {
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            width: parent.width - 120
                                            elide: Text.ElideRight
                                            text: (pRow.peer.on ? "\u25cf  " : "\u25cb  ") + pRow.peer.n
                                            font.family: Theme.font; font.pixelSize: 12
                                            color: pRow.peer.on ? Theme.text : Theme.dim
                                        }
                                        Text {
                                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                            text: pRow.peer.ip
                                            font.family: Theme.font; font.pixelSize: 11
                                            color: Theme.dim
                                        }
                                        // no other way to get an address out of
                                        // here, and typing 100.x by hand is worse
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                Quickshell.execDetached(["sh", "-c",
                                                    "printf %s " + pRow.peer.ip + " | wl-copy"]);
                                                panel.closeIslandPopouts();
                                            }
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

                readonly property real sourceX: rightRow.x + powerIsland.x + btCell.x
                readonly property real sourceWidth: btCell.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                visible: btPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
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

                readonly property real sourceX: rightRow.x + powerIsland.x + volCell.x
                readonly property real sourceWidth: volCell.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                visible: audPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
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

                readonly property real sourceX: rightRow.x + statusWrap.x + netCell.x
                readonly property real sourceWidth: netCell.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                visible: netPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                // OnDemand, not Exclusive: keys are only wanted while a passphrase
                // field has focus, and Exclusive would swallow the compositor's own
                // bindings for as long as the list is open.
                WlrLayershell.keyboardFocus: netPopout.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
                                                        onVisibleChanged: if (visible) forceActiveFocus()
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

                readonly property real sourceX: leftRow.x + svcWrap.x
                readonly property real sourceWidth: svcWrap.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                visible: sysPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight + Theme.popoutGap; left: popupX }
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
                        ResourceInfoRow { label: "docker"; value: Sys.docker }
                        Repeater {
                            model: Sys.dockerList
                            ResourceInfoRow { label: "  " + modelData.name; value: modelData.status }
                        }
                        ResourceInfoRow { label: "vm"; value: Sys.vm }
                        Repeater {
                            model: Sys.vmList
                            ResourceInfoRow { label: "  " + modelData.name; value: modelData.status }
                        }
                    }
                }
            }

        }
            // ---- bezel chrome: band, stubs, concave corner fillets ----
            // Own layer surface so hyprglass (which whitelists "quickshell")
            // never refracts the thin chrome; input-masked to stay click-through.
            PanelWindow {
                id: bezelWin

                screen: panel.screen
                anchors { top: true; left: true; right: true }
                implicitHeight: panel.barHeight
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell-frame"
                mask: Region {}

                Item {
                    id: bezelChrome
                    anchors.fill: parent
                    readonly property real bT: Theme.frameT
                    readonly property real bf: Theme.frameFillet
                    readonly property real bW: bezelWin.width
                    readonly property real bH: panel.barHeight

                    // band line segments between the hanging capsules
                    readonly property var bandSegs: {
                        const nf = panel.notchFillet;
                        const gaps = panel.islandGeom.filter(i => i[2])
                            .map(i => [i[0] - nf, i[0] + i[1] + nf])
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
