import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick
import "../common"

// Critical-battery guard: at ≤7% discharging, centered 10s countdown then
// hibernate. Cancel (or a completed hibernate) suppresses it until the
// battery charges or climbs back above the threshold. Batteryless systems
// never show it (isLaptopBattery guard).
PanelWindow {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property real pct: dev ? (dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 100
    readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false
    // ponytail: 7% not 5 — this battery's readings skip from 6 straight to 2
    // near empty, so 5 can never be observed; UPower's 2% action is the backstop
    readonly property bool critical: (dev?.isLaptopBattery ?? false) && !charging && pct <= 7

    // one-shot low warning: fires on the ≤10% crossing while discharging,
    // re-arms when charging or back above 10%. Routed through our own
    // notif daemon (NotifPopups) via notify-send.
    readonly property bool low: (dev?.isLaptopBattery ?? false) && !charging && pct <= 10
    onLowChanged: if (low)
        Quickshell.execDetached(["notify-send", "-u", "critical", "Battery low", Math.round(pct) + "% remaining"])

    property bool dismissed: false
    property int remaining: 10

    visible: critical && !dismissed
    onCriticalChanged: if (!critical) dismissed = false
    onVisibleChanged: if (visible) remaining = 10

    implicitWidth: 340
    implicitHeight: 100
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-batteryguard"

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: {
            root.remaining--;
            if (root.remaining <= 0) {
                // suppress before hibernating so resume at ≤5% doesn't
                // instantly re-fire the countdown loop
                root.dismissed = true;
                // ponytail: sudo zzz -Z (proven path, passwordless sudo); loginctl hibernate if elogind polkit ever gets set up
                Quickshell.execDetached(["sudo", "zzz", "-Z"]);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.surface
        border.color: Theme.urgent
        border.width: 2

        Column {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "battery critical — hibernating in " + root.remaining + "s"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                color: Theme.bright
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 90
                height: 28
                radius: 8
                color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: "cancel"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: Theme.accentText
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.dismissed = true
                }
            }
        }
    }
}
