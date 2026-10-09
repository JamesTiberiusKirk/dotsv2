import Quickshell
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import QtQuick
import "../common"

// ---- control center (click the sliders cell) ----
// One tile per indicator of this group, always, pinned or not, in bar
// order. A tile's body opens that indicator's page (hung off this cell,
// with a back row); its knob flips the quick switch where there is one.
// Right-click, the hover pin, or p on a focused tile toggles whether it
// also shows in the bar.
// Two of these exist, one per group ("status" and "sys"); Bar.qml sets the
// group and the panelName, the default is the status one.
Popout {
    id: cc

    property string group: "status"
    panelName: "cc"
    implicitWidth: 360
    rowSpacing: 8

    // battery, same source and ladder as batteryCell in Bar.qml
    readonly property var dev: UPower.displayDevice
    readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 0
    readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false
    // volume lives on the node's audio object, null until pipewire has a sink
    readonly property var av: Audio.sink?.audio ?? null

    // a tile shows here only for this card's group, and only while folded in
    function show(name) { return ShellState.groupOf(name) === cc.group && ShellState.inCC(name); }

    // the docker and vm tiles show live cpu/mem, polled only while a sys card is up (Sys.statsWanted)
    readonly property bool wantsStats: open && group === "sys"
    onWantsStatsChanged: Sys.statsWanted += wantsStats ? 1 : -1
    Component.onDestruction: if (wantsStats) Sys.statsWanted -= 1

    // still loading: the same spinning refresh glyph the docker stop button uses
    component Spinner: Icon {
        name: "refresh"
        color: Theme.dim
        RotationAnimator on rotation {
            running: parent.visible
            from: 0; to: 360; duration: 900
            loops: Animation.Infinite
        }
    }

    // thin meter bar: accent, warn when it gets full
    component Track: Rectangle {
        property real frac: 0   // 0..1
        height: 6; radius: 3
        color: Theme.track
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.frac))
            height: parent.height; radius: 3
            color: parent.frac > 0.75 ? Theme.warn : Theme.accent
        }
    }

    component Tile: Rectangle {
        id: t

        required property string name
        property string icon
        property string title: ShellState.indicators.find(i => i.name === t.name)?.title ?? t.name
        property string sub: ""
        property bool wide: false
        property bool on: false
        property color iconColor: t.on ? Theme.accentText : Theme.text
        // function or null: the knob's quick switch. null = the knob opens the page.
        property var toggle: null
        // wide tiles only: the slider under the title
        property int sliderValue: 0
        property int sliderMin: 0
        property bool sliderOff: false
        property var commit: null
        // wide tiles that draw their own body (children land under the title
        // row) instead of a slider; tall is then their height
        property bool custom: false
        property int tall: 66
        // click opens the indicator's own page by default; agent tiles open
        // the shared clanker page on their agent
        property string page: t.name
        property string agentId: ""
        // the page's tab to open on (docker and vms share the services page)
        property string tab: ""
        // half tiles: an optional third line, and their height (tiles sharing a row match)
        property string sub2: ""
        property bool sub2Loading: false
        property int halfTall: 56
        default property alias body: bodyItem.data
        // the last half tile of an odd count takes the full row, no hole
        readonly property bool lone: !t.wide && cc.halfShown.length % 2 === 1
            && cc.halfShown[cc.halfShown.length - 1] === t.name
        readonly property bool pinned: ShellState.pins.includes(t.name)

        visible: cc.show(t.name)
        width: t.wide || t.lone ? grid.width : grid.half
        height: t.wide ? t.tall : t.halfTall
        radius: 10
        color: hover.hovered || t.activeFocus ? Theme.track : Qt.alpha(Theme.track, 0.45)
        border.width: 1
        border.color: t.activeFocus ? Theme.bright : Theme.islandBorder

        // kbd has no page, so Return flips the light instead
        function open() {
            if (t.name === "kbd") t.toggle();
            else {
                if (t.agentId !== "") Clanker.select(t.agentId);
                if (t.tab !== "") cc.bar.popoutsByName[t.page].currentTab = t.tab;
                cc.bar.showPage(t.page, true);
            }
        }
        // h/l on a wide tile drive its slider; the slider itself is not a tab stop
        function hstep(d) { if (t.wide) slider.hstep(d); }

        activeFocusOnTab: true
        Keys.onReturnPressed: t.open()
        // p: the keyboard's right-click. Everything else bubbles up to
        // AttachedPanel's j/k/h/l/Esc.
        Keys.onPressed: e => { if (e.key === Qt.Key_P) { ShellState.togglePin(t.name); e.accepted = true; } }

        // first, so the knob, pin and slider (later siblings) win their own pixels
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => m.button === Qt.RightButton ? ShellState.togglePin(t.name) : t.open()
        }
        HoverHandler { id: hover }

        // ---- half tile: knob + two lines ----
        Rectangle {
            id: knob
            visible: !t.wide
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: 14
            color: t.on ? Theme.accent : Theme.track
            Icon {
                anchors.centerIn: parent
                name: t.icon
                size: 15
                color: t.iconColor
            }
            MouseArea {
                anchors.fill: parent
                onClicked: t.toggle ? t.toggle() : t.open()
            }
        }
        Column {
            visible: !t.wide
            x: 48
            width: t.width - 48 - 10
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: t.title
                elide: Text.ElideRight
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.bright
            }
            Text {
                width: parent.width
                visible: t.sub !== ""
                text: t.sub
                elide: Text.ElideRight
                font.family: Theme.font; font.pixelSize: 10
                color: Theme.dim
            }
            // a third line (docker/vms cpu and mem): one line was too narrow for it
            Text {
                width: parent.width
                visible: t.sub2 !== "" && !t.sub2Loading
                text: t.sub2
                elide: Text.ElideRight
                font.family: Theme.font; font.pixelSize: 10
                color: Theme.text
            }
            // its first numbers take a poll to arrive (docker stats is ~2s)
            Spinner { visible: t.sub2Loading; size: 10 }
        }

        // ---- wide tile: title row over a slider ----
        Item {
            visible: t.wide
            x: 10; y: 8
            width: t.width - 20; height: 18
            Icon {
                id: wideIcon
                anchors.verticalCenter: parent.verticalCenter
                name: t.icon
                size: 15
                color: Theme.text
            }
            Text {
                x: wideIcon.width + 8
                anchors.verticalCenter: parent.verticalCenter
                text: t.title
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.bright
            }
            // leaves room on the right for the pin
            Text {
                anchors { right: parent.right; rightMargin: 36; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.5
                horizontalAlignment: Text.AlignRight
                text: t.sub
                elide: Text.ElideRight
                font.family: Theme.font; font.pixelSize: 10
                color: Theme.dim
            }
            Icon {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                name: "arrow-right"
                size: 12
                color: Theme.dim
            }
        }
        // custom wide tiles put their rows here
        Item {
            id: bodyItem
            visible: t.wide && t.custom
            x: 10; y: 32
            width: t.width - 20; height: t.height - 32 - 8
        }
        ValueSlider {
            id: slider
            visible: t.wide && !t.custom
            x: 10
            anchors { bottom: parent.bottom; bottomMargin: 6 }
            width: t.width - 20
            activeFocusOnTab: false
            label: ""
            value: t.sliderValue
            minValue: t.sliderMin
            off: t.sliderOff
            onCommit: v => { if (t.commit) t.commit(v); }
        }

        // ---- pin: hover or focus only, so the grid stays calm ----
        Icon {
            anchors { top: parent.top; right: parent.right; topMargin: 6; rightMargin: 6 }
            name: t.pinned ? "pin" : "pin-outline"
            size: 12
            visible: hover.hovered || t.activeFocus
            color: t.pinned ? Theme.accent : Theme.dim
            MouseArea {
                anchors { fill: parent; margins: -4 }
                onClicked: ShellState.setPin(t.name, !t.pinned)
            }
        }
    }

    // half tiles shown, in order; Tile.lone reads the last one
    readonly property var halfShown: ["docker", "vms", "network", "tailscale", "power", "kbd", "bluetooth", "tray", "calendar"]
        .filter(n => cc.show(n))

    Flow {
        id: grid
        width: cc.contentWidth
        spacing: 8
        readonly property real half: (width - spacing) / 2
        // Flow fills rows in order, so a wide tile after an odd half tile
        // leaves a hole. Half tiles go first, the wide tiles last, and a lone
        // last half tile spans the row (Tile.lone).

        // docker and vms: two half tiles, first in the grid, so they share a row
        Tile {
            name: "docker"
            icon: "docker"
            sub: Sys.docker + " running"
            sub2: Sys.usageText(Sys.dockerTotal)
            // no spinner with the daemon down: no poll is coming
            sub2Loading: Sys.dockerUp && !Sys.dockerStatsReady
            // docker and vms share a row: same height whether or not either has usage yet
            halfTall: 64
            on: Sys.dockerUp
            page: "services"; tab: "docker"
        }
        Tile {
            name: "vms"
            icon: "server"
            sub: Sys.vm + " running"
            sub2: Sys.usageText(Sys.vmTotal)
            sub2Loading: Sys.vm !== "0" && !Sys.vmStatsReady
            halfTall: 64
            on: Sys.vm !== "0"
            page: "services"; tab: "vms"
        }
        Tile {
            name: "network"
            icon: Sys.netIcon
            sub: Sys.netLabel
            on: Networking.wifiEnabled
            toggle: () => Networking.wifiEnabled = !Networking.wifiEnabled
        }
        Tile {
            name: "tailscale"
            icon: "lock-outline"
            sub: Sys.tsUp ? Sys.tsNode : "down"
            on: Sys.tsUp
            toggle: () => Sys.tsSetUp(!Sys.tsUp)
        }
        Tile {
            name: "power"
            icon: cc.charging ? "battery-charging"
                : cc.pct > 87 ? "battery"
                : cc.pct > 62 ? "battery-70"
                : cc.pct > 37 ? "battery-50"
                : cc.pct > 12 ? "battery-30"
                : "battery-10"
            sub: Math.round(cc.pct) + "%"
        }
        Tile {
            name: "kbd"
            icon: "keyboard"
            sub: Sys.kbdBacklight === 0 ? "off" : Sys.kbdBacklight + "/3"
            on: Sys.kbdBacklight > 0
            // same cycle as the bar cell: off, 1, 2, 3, off
            toggle: () => Quickshell.execDetached(["sh", "-c", "~/go/bin/duo kbd backlight " + ((Sys.kbdBacklight + 1) % 4)])
        }
        Tile {
            name: "bluetooth"
            icon: Bt.icon
            sub: Bt.connectedDevices.length > 0 ? Bt.connectedDevices.map(d => d.name).join(", ")
                : Bt.enabled ? "on" : "off"
            on: Bt.enabled
            toggle: () => Bt.setEnabled(!Bt.enabled)
        }
        Tile {
            name: "tray"
            icon: "dots-horizontal"
            sub: SystemTray.items.values.length + " apps"
        }
        Tile {
            name: "calendar"
            icon: "calendar"
            sub: Qt.formatDateTime(cc.bar.clockDate, "ddd d MMM  ·  HH:mm")
        }

        // wide tiles go last, see above
        Tile {
            name: "system"
            wide: true; custom: true; tall: 72
            icon: "cpu-64-bit"
            Row {
                width: parent.width
                spacing: 10
                Repeater {
                    model: [
                        { label: "cpu", frac: Sys.cpu, text: Math.round(Sys.cpu * 100) + "%" },
                        { label: "mem", frac: Sys.memUsed, text: Sys.memText },
                        { label: "disk", frac: Sys.diskUsed, text: Sys.diskFree + " free" }
                    ]
                    Column {
                        required property var modelData
                        width: (parent.width - 20) / 3
                        spacing: 4
                        Item {
                            width: parent.width; height: 14
                            Text {
                                text: modelData.label
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.dim
                            }
                            Text {
                                anchors.right: parent.right
                                width: parent.width - 28
                                horizontalAlignment: Text.AlignRight
                                text: modelData.text
                                elide: Text.ElideLeft
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.bright
                            }
                        }
                        Track { width: parent.width; frac: modelData.frac }
                    }
                }
            }
        }
        // one wide tile per agent, a bar per limit (balance-only agents get
        // one bar from the headline); clicking opens the clanker page on it
        // Before the first agent list there is no telling which agent tiles
        // will exist, so one stand-in spins where they will go.
        Rectangle {
            visible: cc.group === "sys" && !Clanker.loaded
            width: grid.width; height: 56
            radius: 10
            color: Qt.alpha(Theme.track, 0.45)
            border.width: 1
            border.color: Theme.islandBorder
            Row {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 10
                Spinner { size: 15; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ai usage  ·  loading"
                    font.family: Theme.font; font.pixelSize: 11
                    color: Theme.dim
                }
            }
        }
        // keyed on ids (Bar.qml agentIds), not Clanker.agents: that array is
        // republished every refresh, and a new array rebuilds every tile
        Repeater {
            model: cc.bar.agentIds
            Tile {
                id: at
                required property string modelData
                readonly property var a: Clanker.agents.find(x => x.id === modelData) ?? null
                readonly property var rows: (a?.limits || []).length > 0
                    ? a.limits.map(l => ({ label: l.title || l.label, frac: Number(l.percent) }))
                    : [{ label: "balance", frac: Clanker.headline(a) }]
                name: "clanker:" + modelData
                agentId: modelData
                page: "clanker"
                wide: true; custom: true
                tall: 40 + rows.length * 18
                icon: "agent-" + modelData
                sub: Clanker.headline(a) >= 0 ? "worst: " + Math.round(Clanker.headline(a) * 100) + "%" : ""
                Column {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: at.rows
                        Item {
                            required property var modelData
                            width: parent.width; height: 14
                            Text {
                                id: rowLabel
                                width: 64
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                elide: Text.ElideRight
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.text
                            }
                            Text {
                                id: rowPct
                                width: 34
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                horizontalAlignment: Text.AlignRight
                                text: modelData.frac >= 0 ? Math.round(modelData.frac * 100) + "%" : "--"
                                font.family: Theme.font; font.pixelSize: 10
                                color: Theme.bright
                            }
                            Track {
                                anchors { left: rowLabel.right; leftMargin: 6; right: rowPct.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                frac: modelData.frac
                            }
                        }
                    }
                }
            }
        }
        Tile {
            name: "display"
            wide: true
            icon: "white-balance-sunny"
            sub: Sys.brightnessRows.length ? Sys.brightnessRows[0].label : ""
            // first row only; the page has the rest
            sliderValue: Sys.brightnessRows.length > 0
                ? (Sys.brightnessPct[Sys.brightnessRows[0].name] ?? Sys.brightnessRows[0].pct) : 0
            // never 0, same reason as DisplayPopout: dark looks dead
            sliderMin: 1
            sliderOff: Sys.brightnessRows.length > 0 ? Sys.brightnessRows[0].off : false
            commit: v => { if (Sys.brightnessRows.length > 0) Sys.setBrightness(Sys.brightnessRows[0].name, v); }
        }
        Tile {
            name: "audio"
            wide: true
            icon: Audio.volIcon(cc.av?.volume ?? 0, cc.av?.muted ?? false)
            sub: Audio.devName(Audio.sink)
            sliderValue: cc.av ? Math.round(cc.av.volume * 100) : 0
            sliderOff: cc.av?.muted ?? false
            commit: v => { if (cc.av) cc.av.volume = v / 100; }
        }
    }

    Text {
        text: "right-click or p = pin to bar"
        font.family: Theme.font; font.pixelSize: 10
        color: Theme.dim
    }
}
