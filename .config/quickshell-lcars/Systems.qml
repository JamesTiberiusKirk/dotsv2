import Quickshell
import QtQuick
import QtQuick.Layouts
import "."

// SYSTEMS station: HARDWARE, POWER, STORAGE, SYSTEM. All data and actions via `ship`.
// Root-only items (snapper, scrub, service restart) go through pkexec and stay "AUTH REQUIRED" until the
// LCARS polkit agent is registered (ship.authReady). Destructive ones need a slide to confirm.
Item {
    id: st
    required property var ship
    property alias page: tabs.page

    PageTabs { id: tabs; pages: ["HARDWARE", "POWER", "STORAGE", "SYSTEM"] }

    // tells LiveData which page is on screen; it polls only for that one
    readonly property string want: "systems." + ["hardware", "power", "storage", "system"][page]
    onWantChanged: ship.view = want
    Component.onCompleted: ship.view = want
    Component.onDestruction: if (String(ship.view).indexOf("systems.") === 0) ship.view = ""

    readonly property real pageTop: tabs.height + 16
    // root action button: live once the polkit agent is registered
    component Auth: Pill {
        property string label: "RUN"
        text: st.ship.authReady ? label : "AUTH REQUIRED"; toggle: true; on: st.ship.authReady; enabled: st.ship.authReady && !st.ship.privBusy
        tint: Lc.rose; height: 48; labelSize: 20
    }
    // output of the last privileged command
    component PrivOut: ColumnLayout {
        Layout.fillWidth: true
        visible: st.ship.privTitle !== ""
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: st.ship.privTitle + (st.ship.privBusy ? "  RUNNING" : ""); color: Lc.orange; font.pixelSize: 22; elide: Text.ElideRight }
            Pill { text: "CLEAR"; height: 40; implicitWidth: 100; labelSize: 18; tint: Lc.lilac; onClicked: st.ship.privClear() }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: Math.min(260, out.implicitHeight + 24)
            color: Lc.track; border.width: 2; border.color: Lc.dim; clip: true
            Label { id: out; x: 12; y: 12; width: parent.width - 24; wrapMode: Text.WrapAnywhere; text: st.ship.privOut; color: Lc.peach; font.pixelSize: 16 }
        }
    }
    property string svSel: ""
    function heat(c, max) { return c / max > 0.85 ? Lc.red : c / max > 0.7 ? Lc.orange : Lc.blue; }

    // ================= HARDWARE =================
    Loader {
        active: st.page === 0
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30

                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "WARP CORE"; code: Lc.code("warp") }
                    Readout {
                        Layout.fillWidth: true
                        label: "BATTERY"
                        value: st.ship.battery < 0 ? "--" : Math.round(st.ship.battery) + "%"
                        note: st.ship.batteryNote
                        level: st.ship.battery < 0 ? -1 : st.ship.battery / 100
                        tint: st.ship.battery >= 0 && st.ship.battery < 15 ? Lc.red : Lc.orange
                    }
                    CodedRow { Layout.fillWidth: true; label: "STATE"; value: st.ship.batteryState; tint: Lc.orange }
                    CodedRow { Layout.fillWidth: true; label: st.ship.batteryState === "CHARGING" ? "CHARGE RATE" : "POWER DRAW"; value: st.ship.batteryWatts.toFixed(1) + " W"; tint: Lc.orange }
                    CodedRow {
                        Layout.fillWidth: true; visible: st.ship.batteryHealth >= 0
                        label: "CELL HEALTH"; value: Math.round(st.ship.batteryHealth) + "%"; level: st.ship.batteryHealth / 100; tint: Lc.green
                    }
                    SectHead { text: "COMPUTE"; code: Lc.code("compute") }
                    CodedRow { Layout.fillWidth: true; label: "CPU LOAD"; value: Math.round(st.ship.cpu * 100) + "%"; level: st.ship.cpu; tint: Lc.blue }
                    CodedRow { Layout.fillWidth: true; label: "MEMORY"; note: st.ship.memText; value: Math.round(st.ship.mem * 100) + "%"; level: st.ship.mem; tint: Lc.blue }
                    CodedRow { Layout.fillWidth: true; visible: st.ship.swapText !== ""; label: "SWAP"; value: st.ship.swapText; tint: Lc.blue }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "THERMAL"; code: Lc.code("thermal") }
                    Repeater {
                        model: st.ship.temps
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name; value: Math.round(modelData.c) + "°C"
                            level: modelData.c / modelData.max; tint: st.heat(modelData.c, modelData.max)
                        }
                    }
                    Label { visible: st.ship.temps.length === 0; text: "NO SENSOR DATA"; color: Lc.lilac; font.pixelSize: 22 }
                    SectHead { text: "COOLING"; code: Lc.code("cooling") }
                    Repeater {
                        model: st.ship.fans
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name; value: modelData.rpm + " RPM"; level: modelData.rpm / 6000; tint: Lc.sky
                        }
                    }
                    Label { visible: st.ship.fans.length === 0; text: "NO FAN DATA"; color: Lc.lilac; font.pixelSize: 22 }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "PERIPHERALS"; code: Lc.code("periph") }
                    Repeater {
                        model: st.ship.peripherals
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name; note: modelData.status
                            value: modelData.pct < 0 ? "--" : modelData.pct + "%"
                            level: modelData.pct < 0 ? -1 : modelData.pct / 100
                            tint: modelData.pct >= 0 && modelData.pct < 20 ? Lc.red : Lc.tan
                        }
                    }
                    Label { visible: st.ship.peripherals.length === 0; text: "NO PERIPHERAL CELLS"; color: Lc.lilac; font.pixelSize: 22 }
                    SectHead { text: "DISPLAY LUMINANCE"; code: Lc.code("luminance") }
                    Repeater {
                        model: ScriptModel { values: st.ship.brightRows; objectProp: "name" }
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            Label { text: modelData.label + "  " + modelData.pct + "%" + (modelData.off ? "  (OFF)" : ""); color: Lc.lilac; font.pixelSize: 20 }
                            Meter {
                                Layout.fillWidth: true
                                value: modelData.pct / 100; tint: Lc.blue; interactive: !modelData.off
                                onMoved: v => st.ship.setBrightnessDev(modelData.name, v)
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= POWER =================
    Loader {
        active: st.page === 1
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30

                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "POWER PROFILE"; code: Lc.code("profile") }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2; columnSpacing: 12; rowSpacing: 12
                        Repeater {
                            model: [
                                { t: "ULTRA SAVE", p: "ultra", c: Lc.tan }, { t: "POWER SAVER", p: "power-saver", c: Lc.green },
                                { t: "BALANCED", p: "balanced", c: Lc.blue }, { t: "PERFORMANCE", p: "performance", c: Lc.orange }]
                            Pill {
                                required property var modelData
                                visible: modelData.p !== "performance" || st.ship.hasPerformance
                                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.preferredHeight: 84
                                radius: 30
                                text: modelData.t; labelSize: 26; sub: Lc.code(modelData.p)
                                toggle: true; on: st.ship.profile === modelData.p; tint: modelData.c
                                onClicked: st.ship.setProfile(modelData.p)
                            }
                        }
                    }
                    CodedRow {
                        Layout.fillWidth: true; visible: st.ship.throttled !== ""
                        label: "PERFORMANCE THROTTLED"; value: st.ship.throttled; valueColor: Lc.red; tint: Lc.red
                    }
                    SectHead { text: "CHARGE CEILING"; code: Lc.code("ceiling") }
                    CodedRow {
                        Layout.fillWidth: true
                        label: st.ship.chargeLimit < 0 ? "NOT SUPPORTED" : "CHARGE LIMIT 80%"
                        note: st.ship.chargeLimit < 0 ? "" : "APPLIED CEILING " + st.ship.chargeLimit + "%"
                        tint: Lc.orange
                        Pill {
                            visible: st.ship.chargeLimit >= 0
                            text: st.ship.chargeLimitOn ? "ON" : "OFF"; toggle: true; on: st.ship.chargeLimitOn; tint: Lc.orange
                            height: 48; implicitWidth: 120; labelSize: 20
                            onClicked: st.ship.setChargeLimit(!st.ship.chargeLimitOn)
                        }
                    }
                    CodedRow {
                        Layout.fillWidth: true
                        label: "BATTERY"; note: st.ship.batteryState + "  " + st.ship.batteryWatts.toFixed(1) + " W"
                        value: st.ship.battery < 0 ? "--" : Math.round(st.ship.battery) + "%"
                        level: st.ship.battery < 0 ? -1 : st.ship.battery / 100; tint: Lc.orange
                    }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "IDLE LADDER"; code: Lc.code("idle") }
                    CodedRow {
                        Layout.fillWidth: true
                        label: "KEEP AWAKE"; note: "SUSPENDS THE IDLE TIMERS"; tint: Lc.lilac
                        Pill {
                            text: st.ship.idleAwake ? "AWAKE" : "AUTO"; toggle: true; on: st.ship.idleAwake; tint: Lc.lilac
                            height: 48; implicitWidth: 130; labelSize: 20
                            onClicked: st.ship.setIdleAwake(!st.ship.idleAwake)
                        }
                    }
                    Repeater {
                        model: st.ship.idleStages
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name; value: modelData.min + " MIN"; tint: Lc.lilac
                            Pill {
                                text: modelData.on ? "ON" : "OFF"; toggle: true; on: modelData.on; tint: Lc.lilac
                                height: 48; implicitWidth: 100; labelSize: 20
                                onClicked: st.ship.setIdleStage(modelData.key, !modelData.on)
                            }
                        }
                    }
                    SectHead { text: "TOP CPU CONSUMERS"; code: Lc.code("topcpu") }
                    Repeater {
                        model: st.ship.topProcs
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name.toUpperCase(); value: modelData.pct.toFixed(1) + "%"
                            level: Math.min(1, modelData.pct / 100); tint: Lc.blue
                        }
                    }
                    Label { visible: st.ship.topProcs.length === 0; text: "SAMPLING..."; color: Lc.lilac; font.pixelSize: 22 }
                }
            }
        }
    }

    // ================= STORAGE =================
    Loader {
        active: st.page === 2
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30

                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "VOLUMES"; code: Lc.code("volumes") }
                    Repeater {
                        model: st.ship.filesystems
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.source.replace("/dev/", "").toUpperCase()
                            note: modelData.fs.toUpperCase() + "  " + modelData.used + " / " + modelData.size + "  FREE " + modelData.avail
                            value: modelData.pct + "%"; level: modelData.pct / 100
                            tint: modelData.pct > 90 ? Lc.red : Lc.tan
                            implicitHeight: 76
                        }
                    }
                    SectHead { text: "BTRFS ALLOCATION"; code: Lc.code("btrfs") }
                    Repeater {
                        model: st.ship.btrfsRows
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name; note: modelData.used + " OF " + modelData.size
                            value: modelData.pct + "%"; level: modelData.pct / 100
                            tint: modelData.pct > 92 ? Lc.orange : Lc.blue
                            implicitHeight: 76
                        }
                    }
                    CodedRow { Layout.fillWidth: true; visible: st.ship.btrfsFree !== ""; label: "FREE (ESTIMATED)"; value: st.ship.btrfsFree; tint: Lc.green }
                    SectHead { text: "SNAPSHOTS"; code: Lc.code("snap") }
                    CodedRow {
                        Layout.fillWidth: true; label: "SNAPPER LIST"; note: "NEEDS ROOT"; tint: Lc.rose
                        Auth { label: "LIST"; onClicked: st.ship.priv("SNAPPER LIST", ["snapper", "list"]) }
                    }
                    CodedRow { Layout.fillWidth: true; label: "BTRFS SCRUB"; note: "NEEDS ROOT, STARTS A SCRUB OF /"; tint: Lc.rose; visible: !st.ship.authReady; Auth {} }
                    ConfirmSlider {
                        Layout.fillWidth: true; visible: st.ship.authReady && !st.ship.privBusy
                        text: "SLIDE TO SCRUB /"
                        onConfirmed: st.ship.priv("BTRFS SCRUB START /", ["btrfs", "scrub", "start", "/"])
                    }
                    PrivOut {}
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "SUBVOLUMES"; code: Lc.code("subvol") }
                    Repeater {
                        model: st.ship.subvols
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.mount; value: modelData.sub; tint: Lc.sky
                            implicitHeight: 56
                        }
                    }
                    Label { visible: st.ship.subvols.length === 0; text: "NO BTRFS MOUNTS"; color: Lc.lilac; font.pixelSize: 22 }
                    SectHead { text: "DOCKER"; code: Lc.code("docker") }
                    CodedRow { Layout.fillWidth: true; label: "DAEMON"; value: st.ship.dockerUp ? "ONLINE" : "DOWN"; valueColor: st.ship.dockerUp ? Lc.green : Lc.red; tint: Lc.lilac }
                    Repeater {
                        model: st.ship.containers
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name.toUpperCase(); note: modelData.status; value: modelData.use; tint: Lc.lilac
                            implicitHeight: 72
                        }
                    }
                    Label { visible: st.ship.dockerUp && st.ship.containers.length === 0; text: "NO CONTAINERS RUNNING"; color: Lc.lilac; font.pixelSize: 22 }
                }
            }
        }
    }

    // ================= SYSTEM =================
    Loader {
        active: st.page === 3
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30

                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "SHIP"; code: Lc.code("ship") }
                    CodedRow { Layout.fillWidth: true; label: "HOSTNAME"; value: st.ship.hostname.toUpperCase(); tint: Lc.tan }
                    CodedRow { Layout.fillWidth: true; label: "KERNEL"; value: st.ship.kernel.toUpperCase(); tint: Lc.tan }
                    CodedRow { Layout.fillWidth: true; label: "UPTIME"; value: st.ship.uptime; tint: Lc.tan }
                    SectHead { text: "PACKAGES"; code: Lc.code("pkgs") }
                    CodedRow {
                        Layout.fillWidth: true
                        label: "PENDING UPDATES"; note: "CHECKED HOURLY"
                        value: st.ship.updates < 0 ? "UNKNOWN" : st.ship.updates === 0 ? "UP TO DATE" : String(st.ship.updates)
                        valueColor: st.ship.updates > 0 ? Lc.orange : Lc.green; tint: Lc.orange
                    }
                    SectHead { text: "DOTFILES"; code: Lc.code("dots") }
                    CodedRow { Layout.fillWidth: true; label: "BRANCH"; value: st.ship.dotBranch.toUpperCase(); tint: Lc.lilac }
                    CodedRow {
                        Layout.fillWidth: true
                        label: "UNCOMMITTED"; value: String(st.ship.dotChanges)
                        valueColor: st.ship.dotChanges > 0 ? Lc.orange : Lc.green; tint: Lc.lilac
                    }
                    Pill { Layout.fillWidth: true; Layout.preferredHeight: 72; radius: 30; text: "OPEN LAZYGIT"; labelSize: 26; tint: Lc.lilac; onClicked: st.ship.openLazygit() }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "SERVICES (RUNIT)"; code: Lc.code("runit") }
                    Repeater {
                        model: st.ship.services
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name.toUpperCase()
                            value: modelData.state === "?" ? "UNKNOWN" : modelData.state
                            valueColor: modelData.state === "RUN" ? Lc.green : modelData.state === "?" ? Lc.tan : Lc.red
                            tint: Lc.sky; implicitHeight: 56
                            hot: st.svSel === modelData.name
                            onClicked: if (st.ship.authReady) st.svSel = modelData.name
                        }
                    }
                    Label { visible: st.ship.services.length === 0; text: "NO SERVICES LISTED"; color: Lc.lilac; font.pixelSize: 22 }
                    CodedRow {
                        Layout.fillWidth: true; label: "RESTART SERVICE"; tint: Lc.rose
                        note: st.ship.authReady ? (st.svSel === "" ? "PICK A SERVICE ABOVE" : "SELECTED: " + st.svSel.toUpperCase()) : "RESTART NEEDS ROOT"
                                                Auth { visible: !st.ship.authReady }
                    }
                    ConfirmSlider {
                        Layout.fillWidth: true; visible: st.ship.authReady && st.svSel !== "" && !st.ship.privBusy
                        text: "SLIDE TO RESTART " + st.svSel.toUpperCase()
                        onConfirmed: { st.ship.priv("RESTART " + st.svSel.toUpperCase(), ["sv", "restart", "/run/runit/service/" + st.svSel]); st.svSel = ""; }
                    }
                    PrivOut {}
                }
            }
        }
    }
}
