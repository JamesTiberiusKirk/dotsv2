import QtQuick
import "."
import QtQuick.Layouts

// BRIDGE station. Page 0: ship status, quick systems, levels, media.
// Page 1: big button grid (the old Deck).
Item {
    id: bridge
    required property var ship
    property alias page: tabs.page

    PageTabs { id: tabs; pages: ["STATUS", "COMMAND DECK"] }

    // status page shows the away team count: tell LiveData so it polls gtmux
    readonly property string want: page === 0 ? "bridge.status" : "bridge.deck"
    onWantChanged: ship.view = want
    Component.onCompleted: ship.view = want
    Component.onDestruction: if (String(ship.view).indexOf("bridge.") === 0) ship.view = ""

    // ---- page 0: status ----
    ColumnLayout {
        visible: bridge.page === 0
        anchors { top: tabs.bottom; topMargin: 18; left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 30

        GridLayout {
            Layout.fillWidth: true
            columns: 4; columnSpacing: 26; rowSpacing: 16
            Readout {
                Layout.fillWidth: true
                label: "WARP CORE (BATTERY)"
                value: bridge.ship.battery < 0 ? "--" : Math.round(bridge.ship.battery) + "%"
                note: bridge.ship.batteryNote
                level: bridge.ship.battery < 0 ? -1 : bridge.ship.battery / 100
                tint: bridge.ship.battery >= 0 && bridge.ship.battery < 15 ? Lc.red : Lc.orange
            }
            Readout { Layout.fillWidth: true; label: "CPU LOAD"; value: Math.round(bridge.ship.cpu * 100) + "%"; level: bridge.ship.cpu; tint: Lc.blue }
            Readout { Layout.fillWidth: true; label: "MEMORY"; value: Math.round(bridge.ship.mem * 100) + "%"; level: bridge.ship.mem; tint: Lc.blue }
            Readout {
                Layout.fillWidth: true
                label: "DILITHIUM (" + (bridge.ship.claudeName || "AGENT") + ")"
                value: bridge.ship.claude < 0 ? "--" : Math.round(bridge.ship.claude * 100) + "%"
                note: bridge.ship.claudeNote
                level: bridge.ship.claude < 0 ? -1 : bridge.ship.claude
                tint: bridge.ship.claude >= 0.9 ? Lc.red : Lc.green
            }
        }

        SectionHead { text: "QUICK SYSTEMS" }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Pill { text: "WIFI"; toggle: true; on: bridge.ship.wifi; tint: Lc.orange; onClicked: bridge.ship.setWifi(!on) }
            Pill { text: "BLUETOOTH"; toggle: true; on: bridge.ship.bt; tint: Lc.orange; onClicked: bridge.ship.setBt(!on) }
            Pill { text: "DND"; toggle: true; on: bridge.ship.dnd; tint: Lc.lilac; onClicked: bridge.ship.setDnd(!on) }
            Pill { text: "NIGHT LIGHT"; toggle: true; on: bridge.ship.night; tint: Lc.lilac; onClicked: bridge.ship.setNight(!on) }
            Pill { text: "TAILSCALE"; toggle: true; on: bridge.ship.tailscale; tint: Lc.orange; onClicked: bridge.ship.setTailscale(!on) }
            Pill { text: "ULTRA SAVE"; toggle: true; on: bridge.ship.ultra; tint: Lc.tan; onClicked: bridge.ship.setUltra(!on) }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 30
            ColumnLayout {
                Layout.fillWidth: true
                Label { text: "VOLUME " + Math.round(bridge.ship.volume * 100); color: Lc.lilac; font.pixelSize: 16 }
                Meter { Layout.fillWidth: true; implicitHeight: 34; value: bridge.ship.volume; interactive: true; onMoved: v => bridge.ship.setVolume(v) }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Label { text: "BRIGHTNESS " + Math.round(bridge.ship.brightness * 100) + (bridge.ship.brightnessLabel ? " (" + bridge.ship.brightnessLabel + ")" : ""); color: Lc.lilac; font.pixelSize: 16 }
                Meter { Layout.fillWidth: true; implicitHeight: 34; value: bridge.ship.brightness; tint: Lc.blue; interactive: true; onMoved: v => bridge.ship.setBrightness(Math.max(0.05, v)) }
            }
        }

        SectionHead { text: "NOW PLAYING" }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: bridge.ship.hasMedia ? bridge.ship.mediaTitle : "NO TRANSMISSION"
                    font.pixelSize: 28
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Lc.lilac
                    font.pixelSize: 18
                    visible: bridge.ship.hasMedia
                    text: [bridge.ship.mediaArtist, bridge.ship.mediaPlayer].filter(x => x).join(" \u00b7 ")
                }
            }
            Pill { Layout.alignment: Qt.AlignVCenter; text: "PREV"; height: 56; labelSize: 18; implicitWidth: 110; onClicked: bridge.ship.prev() }
            Pill { Layout.alignment: Qt.AlignVCenter; text: bridge.ship.playing ? "PAUSE" : "PLAY"; tint: Lc.orange; height: 56; labelSize: 18; implicitWidth: 110; onClicked: bridge.ship.playPause() }
            Pill { Layout.alignment: Qt.AlignVCenter; text: "NEXT"; height: 56; labelSize: 18; implicitWidth: 110; onClicked: bridge.ship.next() }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 26
            Readout { Layout.fillWidth: true; label: "SUBSPACE MESSAGES"; value: String(bridge.ship.messages); note: "IN HISTORY" }
            Readout { Layout.fillWidth: true; label: "OVERRIDES"; value: String(bridge.ship.overrideCount); note: "ACTIVE"; tint: Lc.sky }
            Readout { Layout.fillWidth: true; label: "AWAY TEAMS"; value: String(bridge.ship.crew.length); note: "DEPLOYED"; tint: Lc.lilac }
            Readout { Layout.fillWidth: true; label: "SHIP TIME"; value: Qt.formatTime(bridge.ship.now, "HH:mm"); note: Qt.formatDate(bridge.ship.now, "ddd d MMM") }
            Readout { Layout.fillWidth: true; label: "STARDATE"; value: Lc.stardate(bridge.ship.now); tint: Lc.blue }
            Rectangle {
                readonly property bool red: bridge.ship.alert !== "CONDITION GREEN"
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: 35
                color: red ? Lc.red : Lc.green
                Label {
                    anchors.centerIn: parent
                    width: parent.width - 40; horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap; maximumLineCount: 2; lineHeight: 0.85
                    text: parent.red ? (bridge.ship.alertAcked ? "ACKNOWLEDGED" : "ACKNOWLEDGE ALERT") : bridge.ship.alert
                    color: "black"; font.pixelSize: 20
                }
                MouseArea { anchors.fill: parent; onClicked: bridge.ship.ackAlert() }
            }
        }
        Item { Layout.fillHeight: true }
    }

    // ---- page 1: command deck ----
    GridLayout {
        visible: bridge.page === 1
        anchors { top: tabs.bottom; topMargin: 18; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 40 }
        columns: 5; columnSpacing: 12; rowSpacing: 12
        Repeater {
            model: [
                { t: "TERMINAL", c: Lc.orange, cmd: ["wezterm"] },
                { t: "BROWSER", c: Lc.blue, cmd: ["brave"] },
                { t: "SCREENSHOT", c: Lc.lilac, cmd: ["sh", "-c", "~/.scripts/screenshot.sh"] },
                { t: "RECORD", c: Lc.red, hold: true, cmd: ["sh", "-c", "~/.scripts/record.sh"] },
                { t: "MIC MUTE", c: Lc.tan, cmd: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"] },
                { t: "WS 1", c: Lc.blue, d: "hl.dsp.focus({ workspace = 1 })" },
                { t: "WS 2", c: Lc.blue, d: "hl.dsp.focus({ workspace = 2 })" },
                { t: "WS 3", c: Lc.blue, d: "hl.dsp.focus({ workspace = 3 })" },
                { t: "WS 4", c: Lc.blue, d: "hl.dsp.focus({ workspace = 4 })" },
                { t: "THEME", c: Lc.peach, cmd: ["sh", "-c", "~/.scripts/theme-toggle"] },
                { t: "SEND WINDOW UP", c: Lc.lilac, d: "hl.dsp.window.move({ direction = \"u\" })" },
                { t: "SEND WINDOW DOWN", c: Lc.lilac, d: "hl.dsp.window.move({ direction = \"d\" })" },
                { t: "PLAY / PAUSE", c: Lc.sky, play: true },
                { t: "LAUNCHER", c: Lc.sky, cmd: ["qs", "ipc", "call", "launcher", "toggle"] },
                { t: "LOCK", c: Lc.blue, hold: true, cmd: ["loginctl", "lock-session"] }
            ]
            Pill {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1      // equal columns regardless of label length
                Layout.preferredHeight: 1
                radius: 26
                text: modelData.t
                tint: modelData.c
                labelSize: 22
                holdMs: modelData.hold ? 600 : 0
                onClicked: {
                    if (modelData.play) bridge.ship.playPause();
                    else if (modelData.d) bridge.ship.dispatch(modelData.d);
                    else bridge.ship.run(modelData.cmd);
                }
            }
        }
    }

    component SectionHead: RowLayout {
        property alias text: t.text
        Layout.fillWidth: true
        spacing: 12
        Label { id: t; color: Lc.orange; font.pixelSize: 24 }
        Rectangle { Layout.fillWidth: true; height: 6; radius: 3; color: Lc.dim }
    }
}
