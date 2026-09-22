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
import "../../common"

// ---- audio panel (click volume cell) ----
Popout {
    id: audioPopout

    panelName: "audio"
    iconName: "volume-high"
    implicitWidth: 340
    // is the airpods settings fold open
    property bool podsOpen: false
    onOpenChanged: {
        Audio.panelOpen = open;
        if (!open) podsOpen = false;
    }

    component AudDiv: Rectangle {
        width: audioPopout.contentWidth; height: 1
        color: Theme.islandBorder
    }

    // section header: name on the left, mute on the right
    component AudHead: Item {
        id: ah
        property string label
        property var target: null       // the PwNode to mute
        readonly property var na: ah.target?.audio ?? null

        width: audioPopout.contentWidth
        height: 18
        activeFocusOnTab: ah.na !== null
        Keys.onReturnPressed: if (ah.na) ah.na.muted = !ah.na.muted

        Rectangle {
            anchors { fill: parent; margins: -2 }
            radius: 5
            color: ah.activeFocus ? Theme.track : "transparent"
        }
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
        // Output list only. AirPods are a capture device too,
        // and one set of controls in one place is the point.
        property bool podsFold: false
        readonly property bool pods: ds.podsFold && Pods.connected
            && Audio.devName(ds.node).toLowerCase().indexOf("airpods") >= 0

        width: audioPopout.contentWidth
        spacing: 4

        ValueSlider {
            width: audioPopout.contentWidth
            icon: "check"
            iconOn: ds.current
            leadIcon: Audio.devIcon(ds.node)
            label: Audio.devName(ds.node)
            note: ds.pods
                ? Pods.batteryMarkup(Theme.text, Theme.dim, Theme.warn, Theme.urgent)
                : ""
            trailIcon: !ds.pods ? ""
                     : audioPopout.podsOpen ? "chevron-up" : "chevron-down"
            onTrailPressed: audioPopout.podsOpen = !audioPopout.podsOpen
            suffix: "%"
            maxValue: 150
            off: ds.na?.muted ?? false
            value: ds.na ? Math.round(ds.na.volume * 100) : 0
            onCommit: v => { if (ds.na) ds.na.volume = v / 100; }
            // h/l is the volume, Return makes it the default
            Keys.onReturnPressed: if (!ds.current) Audio.setDefault(ds.node)

            // top strip only — the track keeps the bottom of
            // the row so a drag never switches device
            MouseArea {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 16
                enabled: !ds.current
                onClicked: Audio.setDefault(ds.node)
            }
            // hover-only ban: hides the device from the
            // list, retrievable under the "hidden" row
            HoverHandler { id: dsHover }
            Icon {
                anchors { right: parent.right; top: parent.top; rightMargin: parent.trailPad }
                visible: dsHover.hovered
                name: "eye-off"
                size: 13
                color: Theme.dim
                MouseArea {
                    anchors { fill: parent; margins: -4 }
                    onClicked: Audio.ban(ds.node)
                }
            }
        }
        // only the selected device carries signal
        Meter { visible: ds.current; node: ds.node }

        // AirPods settings, folded under their own row. Not a
        // section of its own: the device is already named and
        // drawn here, and repeating it bought nothing.
        FoldCard {
            visible: ds.pods && audioPopout.podsOpen

            // Flow, not Row: four pills do not fit the panel
            // on a model that supports all four modes.
            Flow {
                visible: Pods.supportsNoiseControl
                width: parent.width
                spacing: 6

                // No "off": the daemon reports it supported on
                // a Pro 2, but these pods take the packet and
                // ignore it — measured three times in a row
                // with both pods in ear, while transparency
                // and anc applied in two seconds. A pill that
                // never does anything is worse than no pill.
                // Apple gates Off behind the noise-control
                // checkboxes on an iPhone; enable it there and
                // put mode 0 back in this list.
                Repeater {
                    model: [
                        { l: "anc",          v: 1, c: "noise:anc" },
                        { l: "transparency", v: 2, c: "noise:transparency" },
                        { l: "adaptive",     v: 3, c: "noise:adaptive" }
                    ]
                    PillBtn {
                        visible: modelData.v !== 3 || Pods.supportsAdaptive
                        text: modelData.l
                        active: Pods.noiseMode === modelData.v
                        onPressed: Pods.ctl(modelData.c)
                    }
                }
            }

            // The firmware only takes a level while adaptive
            // is the live mode; showing it otherwise is a
            // control that silently does nothing.
            ValueSlider {
                visible: Pods.supportsAdaptive && Pods.noiseMode === 3
                width: parent.width
                label: "adaptive"
                suffix: "%"
                value: Pods.adaptiveLevel
                onCommit: v => Pods.ctl("adaptive:" + v)
            }

            ToggleRow {
                visible: Pods.supportsCa
                label: "conversation awareness"
                checked: Pods.ca
                onToggled: value => Pods.ctl("ca:" + (value ? "on" : "off"))
            }
            ToggleRow {
                visible: Pods.supportsOneBud
                label: "one-bud anc"
                checked: Pods.oneBud
                onToggled: value => Pods.ctl("onebud:" + (value ? "on" : "off"))
            }

            Text {
                text: "pause when removed"
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.dim
            }
            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { l: "one",  v: 0, c: "ear:one" },
                        { l: "both", v: 1, c: "ear:both" },
                        { l: "off",  v: 2, c: "ear:off" }
                    ]
                    PillBtn {
                        text: modelData.l
                        active: Pods.earMode === modelData.v
                        onPressed: Pods.ctl(modelData.c)
                    }
                }
            }
        }
    }

    // banned devices, folded away under a count; each row
    // has an eye to bring it back
    component Hidden: Column {
        id: hd
        property var list: []
        property bool open: false

        visible: hd.list.length > 0
        width: audioPopout.contentWidth
        spacing: 4

        Item {
            id: hdHead
            width: audioPopout.contentWidth
            height: 18
            activeFocusOnTab: true
            Keys.onReturnPressed: hd.open = !hd.open
            Rectangle {
                anchors { fill: parent; margins: -2 }
                radius: 5
                color: hdHead.activeFocus ? Theme.track : "transparent"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "hidden (" + hd.list.length + ")"
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.dim
            }
            Icon {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                name: hd.open ? "chevron-up" : "chevron-down"
                size: 13
                color: Theme.dim
            }
            MouseArea {
                anchors.fill: parent
                onClicked: hd.open = !hd.open
            }
        }
        FoldCard {
            visible: hd.open
            spacing: 4

            Repeater {
                model: hd.open ? hd.list : []
                Item {
                    id: hdRow
                    width: parent.width
                    height: 18
                    activeFocusOnTab: true
                    Keys.onReturnPressed: Audio.unban(modelData)
                    Rectangle {
                        anchors { fill: parent; margins: -2 }
                        radius: 5
                        color: hdRow.activeFocus ? Theme.track : "transparent"
                    }
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: parent.width - 24
                        elide: Text.ElideRight
                        text: Audio.devName(modelData)
                        font.family: Theme.font; font.pixelSize: 11
                        color: Theme.dim
                    }
                    Icon {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        name: "eye"
                        size: 13
                        color: Theme.dim
                        MouseArea {
                            anchors { fill: parent; margins: -4 }
                            onClicked: Audio.unban(modelData)
                        }
                    }
                }
            }
        }
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
        width: audioPopout.contentWidth
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

        width: audioPopout.contentWidth
        spacing: 4

        Item {
            id: arHead
            width: parent.width
            height: 20
            activeFocusOnTab: ar.na !== null
            Keys.onReturnPressed: if (ar.na) ar.na.muted = !ar.na.muted

            Rectangle {
                anchors { fill: parent; margins: -2 }
                radius: 5
                color: arHead.activeFocus ? Theme.track : "transparent"
            }
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
            width: audioPopout.contentWidth
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
        DevSlider { node: modelData; current: modelData === Audio.sink; podsFold: true }
    }
    Hidden { list: Audio.bannedSinks }

    // Paired audio kit that is not connected. pipewire never
    // sees these — bluez has to connect one before a sink
    // exists at all — so the audio panel is the only place
    // that can get a headset back without a detour through
    // the bluetooth panel. Audio.wantBt makes it the default
    // once the sink turns up a moment later.
    Repeater {
        model: Bt.enabled ? Bt.audioDevices : []

        Item {
            id: btAud
            readonly property var dev: modelData
            // Busy for the whole retry window, not just
            // bluez's Connecting flicker — the row is the
            // only feedback that the retry is still running.
            readonly property bool busy:
                dev.state === BluetoothDeviceState.Connecting
                || Bt.connecting === dev

            width: audioPopout.contentWidth
            height: 22
            activeFocusOnTab: !btAud.busy
            Keys.onReturnPressed: btAud.go()
            function go() {
                Audio.wantBt(btAud.dev);
                Bt.toggle(btAud.dev);
            }

            Rectangle {
                anchors { fill: parent; margins: -2 }
                radius: 5
                color: btAud.activeFocus ? Theme.track : "transparent"
            }
            Row {
                anchors { left: parent.left; right: btAudMark.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 6

                Icon {
                    name: Bt.devIcon(btAud.dev)
                    size: 13
                    color: Theme.dim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: btAud.dev.name
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: 11
                    color: Theme.dim
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                id: btAudMark
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: btAud.busy ? "\u2026" : "connect"
                font.family: Theme.font; font.pixelSize: 10
                color: btAud.busy ? Theme.warn : Theme.accent
            }
            MouseArea {
                anchors.fill: parent
                enabled: !btAud.busy
                onClicked: btAud.go()
            }
        }
    }

    AudDiv {}

    // ---- input ----
    AudHead { label: "input"; target: Audio.source }

    Repeater {
        model: Audio.sources
        DevSlider { node: modelData; current: modelData === Audio.source }
    }
    Hidden { list: Audio.bannedSources }

    // ---- apps playing ----
    AudDiv { visible: Audio.playing.length > 0 }
    Item {
        visible: Audio.playing.length > 0
        width: audioPopout.contentWidth
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
