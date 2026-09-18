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

// ---- bluetooth panel (click bt cell) ----
Popout {
    id: btPanel

    panelName: "bluetooth"
    iconName: "bluetooth"
    implicitWidth: 300
    onOpenChanged: Bt.panelOpen = open

    ToggleRow {
        label: "bluetooth"
        checked: Bt.enabled
        onToggled: value => Bt.setEnabled(value)
    }

    Rectangle {
        visible: Bt.enabled
        width: btPanel.contentWidth; height: 1; color: Theme.islandBorder
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
            // Busy for the whole retry window, not just
            // bluez's Connecting flicker — the row is the
            // only feedback that the retry is still running.
            readonly property bool busy:
                dev.state === BluetoothDeviceState.Connecting
                || Bt.connecting === dev
                || dev.state === BluetoothDeviceState.Disconnecting

            width: btPanel.contentWidth
            height: 24
            activeFocusOnTab: !btRow.busy
            Keys.onReturnPressed: Bt.toggle(btRow.dev)

            Rectangle {
                anchors { fill: parent; margins: -2 }
                radius: 5
                color: btRow.activeFocus ? Theme.track : "transparent"
            }
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

                // AirPods publish nothing over bluez — battery
                // rides Apple's own protocol, which the
                // librepods daemon speaks. Three cells, so
                // the text replaces the single % rather than
                // sitting next to it.
                //
                // Not gated on Pods.connected: battery keeps
                // arriving over the BLE advertisement after
                // the audio link drops, which is exactly the
                // back-in-the-case state where the case level
                // is the number worth showing.
                Text {
                    readonly property bool pods:
                        Bt.isPods(btRow.dev) && Pods.hasBattery
                    visible: pods || btRow.dev.batteryAvailable
                    // Each pod carries its own colour, so the
                    // markup sets them and `color` is only the
                    // single-value bluez case.
                    textFormat: Text.StyledText
                    text: pods
                        ? Pods.batteryMarkup(Theme.text, Theme.dim, Theme.warn, Theme.urgent)
                        : Math.round(btRow.dev.battery * 100) + "%"
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
        width: btPanel.contentWidth; height: 1; color: Theme.islandBorder
    }
    // pairing needs an agent to answer passkey prompts, which
    // this panel has no way to show — blueman already does it
    Text {
        id: btPair
        visible: Bt.enabled
        text: "pair a new device\u2026"
        font.family: Theme.font; font.pixelSize: 11
        font.underline: btPair.activeFocus
        color: Theme.accent
        activeFocusOnTab: true
        Keys.onReturnPressed: btPair.launch()
        function launch() {
            Quickshell.execDetached(["blueman-manager"]);
            bar.closeIslandPopouts();
        }
        MouseArea {
            anchors.fill: parent
            onClicked: btPair.launch()
        }
    }
}
