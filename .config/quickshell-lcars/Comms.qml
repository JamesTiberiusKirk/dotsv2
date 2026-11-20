import Quickshell
import QtQuick
import QtQuick.Layouts
import "."

// COMMS station: MESSAGES, AUDIO, BLUETOOTH, NETWORK. All data and actions via `ship`.
Item {
    id: st
    required property var ship
    property alias page: tabs.page

    PageTabs { id: tabs; pages: ["MESSAGES", "AUDIO", "BLUETOOTH", "NETWORK"] }

    readonly property string want: "comms." + ["messages", "audio", "bluetooth", "network"][page]
    onWantChanged: ship.view = want
    Component.onCompleted: ship.view = want
    Component.onDestruction: if (String(ship.view).indexOf("comms.") === 0) ship.view = ""

    readonly property real pageTop: tabs.height + 16
    function urgencyTint(u) { return u >= 2 ? Lc.red : u === 0 ? Lc.blue : Lc.lilac; }

    // ================= MESSAGES =================
    Loader {
        active: st.page === 0
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            ColumnLayout {
                anchors.fill: parent
                spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    Pill { text: "DO NOT DISTURB"; toggle: true; on: st.ship.dnd; tint: Lc.lilac; height: 56; labelSize: 20; onClicked: st.ship.setDnd(!st.ship.dnd) }
                    Label { text: st.ship.messageList.length + " IN HISTORY"; color: Lc.tan; font.pixelSize: 26 }
                    Item { Layout.fillWidth: true }
                    ConfirmSlider {
                        visible: st.ship.messageList.length > 0
                        implicitWidth: 460
                        text: "SLIDE TO CLEAR ALL"
                        onConfirmed: st.ship.clearMessages()
                    }
                }
                SectHead { text: "SUBSPACE MESSAGES"; code: Lc.code("subspace") }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: st.ship.messageList; objectProp: "key" }
                    delegate: CodedRow {
                        required property var modelData
                        width: ListView.view.width
                        height: 76
                        label: modelData.summary || modelData.app
                        note: modelData.app + (modelData.body ? "  /  " + modelData.body.replace(/\n/g, " ") : "")
                        value: modelData.ago
                        code: Lc.code(modelData.key)
                        tint: st.urgencyTint(modelData.urgency)
                        Pill {
                            text: "DISMISS"; height: 52; implicitWidth: 140; labelSize: 18; tint: Lc.orange
                            onClicked: st.ship.removeMessage(modelData.key)
                        }
                    }
                    Label { visible: parent.count === 0; anchors.centerIn: parent; text: "NO TRANSMISSIONS"; color: Lc.lilac; font.pixelSize: 30 }
                }
            }
        }
    }

    // ================= AUDIO =================
    Loader {
        active: st.page === 1
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                Repeater {
                    model: [
                        { head: "OUTPUT", code: "out", key: "audioSinks", tint: Lc.orange },
                        { head: "INPUT", code: "in", key: "audioSources", tint: Lc.blue }]
                    ColumnLayout {
                        id: col
                        required property var modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                        spacing: 12
                        SectHead { text: col.modelData.head; code: Lc.code(col.modelData.code) }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true; spacing: 10
                            boundsBehavior: Flickable.StopAtBounds
                            model: ScriptModel { values: st.ship[col.modelData.key]; objectProp: "id" }
                            delegate: Column {
                                id: nodeRow
                                required property var modelData
                                width: ListView.view.width
                                spacing: 0
                                CodedRow {
                                    width: parent.width; height: 60
                                    label: nodeRow.modelData.name
                                    note: nodeRow.modelData.current ? "DEFAULT" : "TAP TO MAKE DEFAULT"
                                    hot: nodeRow.modelData.current
                                    tint: col.modelData.tint
                                    onClicked: st.ship.setDefaultNode(nodeRow.modelData.id)
                                    Pill {
                                        text: nodeRow.modelData.muted ? "MUTED" : "MUTE"; toggle: true; on: nodeRow.modelData.muted
                                        tint: Lc.red; height: 48; implicitWidth: 130; labelSize: 18
                                        onClicked: st.ship.toggleNodeMute(nodeRow.modelData.id)
                                    }
                                }
                                Item {
                                    width: parent.width; height: 60
                                    Label { x: 82; anchors.verticalCenter: parent.verticalCenter; text: Math.round((st.ship.audioLevels[nodeRow.modelData.id] ?? 0) * 100) + "%"; color: Lc.tan; font.pixelSize: 20; width: 62 }
                                    Meter {
                                        x: 150; width: parent.width - 150 - 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 56
                                        value: st.ship.audioLevels[nodeRow.modelData.id] ?? 0
                                        tint: nodeRow.modelData.muted ? Lc.dim : col.modelData.tint; interactive: true
                                        onMoved: v => st.ship.setNodeVolume(nodeRow.modelData.id, v)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ================= BLUETOOTH =================
    Loader {
        active: st.page === 2
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                ColumnLayout {
                    Layout.fillWidth: true; Layout.preferredWidth: 3; Layout.fillHeight: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true; spacing: 20
                        Pill { text: "BLUETOOTH"; toggle: true; on: st.ship.bt; tint: Lc.orange; height: 56; labelSize: 20; enabled: st.ship.btPresent; onClicked: st.ship.setBt(!st.ship.bt) }
                        Label { text: st.ship.btDevices.filter(d => d.connected).length + " CONNECTED"; color: Lc.tan; font.pixelSize: 26 }
                    }
                    SectHead { text: "PAIRED DEVICES"; code: Lc.code("paired") }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: ScriptModel { values: st.ship.bt ? st.ship.btDevices : []; objectProp: "key" }
                        delegate: CodedRow {
                            required property var modelData
                            width: ListView.view.width
                            height: 68
                            label: modelData.name
                            note: modelData.icon.toUpperCase() + (modelData.battery >= 0 ? "  BATTERY " + modelData.battery + "%" : "")
                            value: modelData.busy ? "..." : modelData.connected ? "LINKED" : ""
                            valueColor: Lc.green
                            hot: modelData.connected
                            tint: modelData.pods ? Lc.rose : Lc.blue
                            Pill {
                                // connect = orange tap, disconnect = rose hold (a stray touch must not drop the keyboard)
                                text: modelData.connected ? "HOLD: DISCONNECT" : "CONNECT"
                                tint: modelData.connected ? Lc.rose : Lc.orange; holdMs: modelData.connected ? 800 : 0
                                height: 52; implicitWidth: 250; labelSize: 18
                                enabled: !modelData.busy
                                onClicked: st.ship.btToggle(modelData.key)
                            }
                        }
                        Label { visible: parent.count === 0; anchors.centerIn: parent; text: st.ship.bt ? "NO PAIRED DEVICES" : "BLUETOOTH IS OFF"; color: Lc.lilac; font.pixelSize: 28 }
                    }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 2; Layout.fillHeight: true
                    SectHead { text: "AIRPODS"; code: Lc.code("pods") }
                    CodedRow { Layout.fillWidth: true; visible: !st.ship.pods.present; label: "LIBREPODS DAEMON OFFLINE"; tint: Lc.dim }
                    CodedRow {
                        Layout.fillWidth: true; visible: st.ship.pods.present
                        label: st.ship.pods.name; note: st.ship.pods.up ? "LINK ACTIVE" : "NOT CONNECTED"
                        value: st.ship.pods.text; tint: Lc.rose; hot: st.ship.pods.up
                        implicitHeight: 76
                    }
                    SectHead { visible: st.ship.pods.present && st.ship.pods.up; text: "NOISE CONTROL"; code: Lc.code("noise") }
                    Repeater {
                        model: [
                            { t: "NOISE CANCEL", v: 1, c: "noise:anc" }, { t: "TRANSPARENCY", v: 2, c: "noise:transparency" },
                            { t: "ADAPTIVE", v: 3, c: "noise:adaptive" }]
                        Pill {
                            required property var modelData
                            visible: st.ship.pods.present && st.ship.pods.up && (modelData.v !== 3 || st.ship.pods.adaptive)
                            Layout.fillWidth: true; Layout.preferredHeight: 64
                            text: modelData.t; labelSize: 24; toggle: true; on: st.ship.pods.noise === modelData.v; tint: Lc.rose
                            onClicked: st.ship.podsCtl(modelData.c)
                        }
                    }
                    Pill {
                        visible: st.ship.pods.present && st.ship.pods.up && st.ship.pods.supportsCa
                        Layout.fillWidth: true; Layout.preferredHeight: 64
                        text: "CONVERSATION AWARENESS"; labelSize: 24; toggle: true; on: st.ship.pods.ca; tint: Lc.lilac
                        onClicked: st.ship.podsCtl("ca:" + (st.ship.pods.ca ? "off" : "on"))
                    }
                }
            }
        }
    }

    // ================= NETWORK =================
    Loader {
        active: st.page === 3
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                ColumnLayout {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true; spacing: 20
                        Pill { text: "WIFI"; toggle: true; on: st.ship.wifi; tint: Lc.orange; height: 56; labelSize: 20; onClicked: st.ship.setWifi(!st.ship.wifi) }
                        Label { Layout.fillWidth: true; elide: Text.ElideRight; text: st.ship.netUp ? st.ship.netText : "NO UPLINK"; color: st.ship.netUp ? Lc.tan : Lc.red; font.pixelSize: 22 }
                    }
                    SectHead { text: "WIRELESS NETWORKS"; code: Lc.code("wifi") }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: ScriptModel { values: st.ship.wifi ? st.ship.wifiNets : []; objectProp: "name" }
                        delegate: CodedRow {
                            required property var modelData
                            readonly property bool locked: modelData.secured && !modelData.known && !modelData.connected
                            width: ListView.view.width
                            height: 72
                            label: modelData.name.toUpperCase()
                            note: (modelData.secured ? "SECURED" : "OPEN") + (modelData.known ? "  SAVED" : "")
                            level: modelData.signal
                            hot: modelData.connected
                            tint: modelData.connected ? Lc.green : Lc.sky
                            Pill {
                                text: locked ? "KEY NEEDED" : modelData.connected ? "HOLD: DISCONNECT" : "CONNECT"
                                toggle: true; on: !locked; tint: modelData.connected ? Lc.rose : Lc.orange
                                holdMs: modelData.connected ? 800 : 0
                                height: 48; implicitWidth: 240; labelSize: 17
                                enabled: !locked && !modelData.busy
                                onClicked: st.ship.wifiToggle(modelData.name)
                            }
                        }
                        Label { visible: parent.count === 0; anchors.centerIn: parent; text: st.ship.wifi ? "SCANNING..." : "WIFI IS OFF"; color: Lc.lilac; font.pixelSize: 28 }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true; spacing: 20
                        Pill { text: st.ship.tailscale ? "HOLD: TAILSCALE DOWN" : "TAILSCALE UP"; toggle: true; on: st.ship.tailscale; tint: st.ship.tailscale ? Lc.rose : Lc.orange; holdMs: st.ship.tailscale ? 800 : 0; height: 56; labelSize: 20; enabled: st.ship.tsPresent; onClicked: st.ship.setTailscale(!st.ship.tailscale) }
                        Label { Layout.fillWidth: true; elide: Text.ElideRight; text: st.ship.tsPresent ? st.ship.tsNode.toUpperCase() + "  " + st.ship.tsIp : "NOT INSTALLED"; color: Lc.tan; font.pixelSize: 22 }
                    }
                    SectHead { text: "TAILNET PEERS"; code: Lc.code("tailnet") }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        model: ScriptModel { values: st.ship.tailscale ? st.ship.tsPeers : []; objectProp: "ip" }
                        delegate: CodedRow {
                            required property var modelData
                            width: ListView.view.width
                            height: 68
                            label: modelData.n.toUpperCase(); note: modelData.ip
                            value: modelData.on ? "" : "OFFLINE"; valueColor: Lc.dim
                            hot: modelData.ip === st.ship.tsExit
                            tint: modelData.on ? Lc.green : Lc.dim
                            Pill {
                                visible: modelData.ex
                                text: modelData.ip === st.ship.tsExit ? "EXIT NODE ON" : "USE AS EXIT"
                                toggle: true; on: modelData.ip === st.ship.tsExit; tint: Lc.orange
                                height: 48; implicitWidth: 190; labelSize: 17
                                onClicked: st.ship.setTsExit(modelData.ip === st.ship.tsExit ? "" : modelData.ip)
                            }
                        }
                        Label { visible: parent.count === 0; anchors.centerIn: parent; text: st.ship.tailscale ? "NO PEERS" : "TAILSCALE IS DOWN"; color: Lc.lilac; font.pixelSize: 28 }
                    }
                }
            }
        }
    }
}
