import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
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

            function closeIslandPopouts() {
                Notifs.centerOpen = false;
                calPopout.open = false;
                sysPopout.open = false;
            }

            function clamp(v, lo, hi) {
                return Math.max(lo, Math.min(hi, v));
            }

            function attachedPanelX(sourceX, sourceWidth, popupWidth) {
                const gutter = Theme.frameT + Theme.frameFillet + 8;
                return clamp(sourceX + sourceWidth / 2 - popupWidth / 2,
                             gutter,
                             panel.width - popupWidth - gutter);
            }

            component Cell: Text {
                topPadding: 7
                bottomPadding: 7
                leftPadding: 8
                rightPadding: 8
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.text
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

                Island {
                    id: wsIsland
                    Cell {
                        text: Sys.layout
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
                                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + parent.modelData.id + " })")
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

                        Cell { visible: Sys.docker !== ""; text: Sys.docker }
                        Cell { visible: Sys.tailscale !== ""; text: Sys.tailscale }
                        Cell { visible: Sys.vm !== ""; text: Sys.vm }
                        Cell { text: "📊 " + Math.round(Sys.cpu * 100) + "%" }
                        Cell { visible: Sys.memText !== ""; text: "🧠 " + Sys.memText }
                        Cell { visible: Sys.diskFree !== ""; text: "💾 " + Sys.diskFree }
                    }
                }
            }

            // ---- center: active window title ----
            Island {
                id: titleIsland
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Theme.frameT }
                visible: opacity > 0 && (ToplevelManager.activeToplevel?.title ?? "") !== ""
                opacity: panel.islandFade
                transform: Translate { y: panel.islandLift }

                Cell {
                    text: ToplevelManager.activeToplevel?.title ?? ""
                    color: Theme.bright
                    elide: Text.ElideMiddle
                    width: Math.min(implicitWidth, panel.width * 0.4)
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

                        Cell {
                            text: "●"
                            color: Sys.netUp ? Theme.ok : Theme.urgent
                            rightPadding: 0
                        }
                        Cell { text: "net"; leftPadding: 5 }
                        Cell {
                            visible: Sys.corne !== ""
                            text: "⌨ " + Sys.corne
                            color: Theme.bright
                        }
                        Cell { visible: Sys.latency !== ""; text: "⏱ " + Sys.latency }
                    }
                }

                Island {
                    id: powerIsland
                    // battery
                    Cell {
                        readonly property var dev: UPower.displayDevice
                        visible: (dev?.isLaptopBattery ?? false)
                        readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 0
                        readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false
                        text: (charging ? "⚡" : "bat ") + Math.round(pct) + "%"
                        color: !charging && pct <= 15 ? Theme.urgent : Theme.text
                    }
                    // backlight
                    Cell {
                        visible: Sys.backlight >= 0
                        text: "☀ " + Math.round(Sys.backlight * 100) + "%"
                    }
                    // volume: click = mute, scroll = adjust
                    Cell {
                        readonly property var audio: panel.sink?.audio ?? null
                        text: audio ? (audio.muted ? "vol –" : "vol " + Math.round(audio.volume * 100) + "%") : ""
                        color: audio?.muted ? Theme.dim : Theme.text
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (parent.audio) parent.audio.muted = !parent.audio.muted; }
                            onWheel: w => {
                                if (!parent.audio) return;
                                const d = w.angleDelta.y > 0 ? 0.05 : -0.05;
                                parent.audio.volume = Math.max(0, Math.min(1.5, parent.audio.volume + d));
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

                        readonly property int count: Notifs.server.trackedNotifications.values.length
                        text: count > 0 ? "󰂚 " + count : "󰂚"
                        color: count > 0 ? Theme.bright : Theme.dim
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
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
                visible: calPopout.open || sysPopout.open
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
                margins { top: panel.barHeight; left: popupX }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 250
                implicitHeight: calCol.implicitHeight + 37
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

            // ---- resource panel (click resource island) ----
            PanelWindow {
                id: resourcePopout

                readonly property real sourceX: leftRow.x + svcWrap.x
                readonly property real sourceWidth: svcWrap.width
                readonly property real popupX: panel.attachedPanelX(sourceX, sourceWidth, implicitWidth)

                visible: sysPopout.open
                screen: panel.screen
                anchors { top: true; left: true }
                margins { top: panel.barHeight; left: popupX }
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-popout"
                implicitWidth: 320
                implicitHeight: resourceCol.implicitHeight + 37
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
                        ResourceInfoRow { label: "tailscale"; value: Sys.tailscale }
                        ResourceInfoRow { label: "vm"; value: Sys.vm }
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
