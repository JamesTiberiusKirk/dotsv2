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

// ---- power panel (click the battery cell) ----
// Battery detail plus the profile selector. Profiles bind straight
// to PowerProfiles (Quickshell.Services.UPower) — the daemon is the
// state, so there is nothing local to keep in sync.
Popout {
    id: powerPopout

    panelName: "power"
    implicitWidth: 360
    rowSpacing: 6
    onOpenChanged: Sys.powerPanelOpen = open

    readonly property var dev: Sys.batteryDevice
    readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false
    // seconds -> "4h 18m" / "18m". 0 means UPower has no estimate yet
    // (it needs a rate sample) rather than "empty right now".
    function dur(s) {
        if (!(s > 0)) return "—";
        const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    // label left, value right — the whole panel is this shape
    component StatRow: Item {
        id: sr
        property string label
        property string value
        property color valueColor: Theme.text
        property real indent: 0
        // optional leading icon (the top-cpu rows use it)
        property string icon: ""
        width: powerPopout.contentWidth
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
        width: powerPopout.contentWidth; height: 1
        color: Theme.islandBorder
    }

    // ---- battery ----
    Item {
        width: powerPopout.contentWidth
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
        width: powerPopout.contentWidth
        spacing: 4

        // "ultra" is not a daemon profile: it runs ~/.scripts/powersave
        // (power-saver + turbo off + 60Hz + no eye-candy), see Sys.ultraSave.
        readonly property var profiles: ["ultra"].concat(PowerProfiles.hasPerformanceProfile
            ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
            : [PowerProfile.PowerSaver, PowerProfile.Balanced])

        Repeater {
            model: profRow.profiles
            Rectangle {
                id: seg
                readonly property bool ultra: modelData === "ultra"
                readonly property bool active: ultra ? Sys.ultraSave
                    : !Sys.ultraSave && PowerProfiles.profile === modelData
                readonly property string icon:
                    ultra ? "sleep"
                    : modelData === PowerProfile.PowerSaver ? "leaf"
                    : modelData === PowerProfile.Performance ? "rocket-launch"
                    : "scale-balance"
                readonly property string name:
                    ultra ? "ultra"
                    : modelData === PowerProfile.PowerSaver ? "saver"
                    : modelData === PowerProfile.Performance ? "turbo"
                    : "balanced"
                property bool hovered: false
                function select() {
                    if (seg.ultra) { Sys.setUltraSave(true); return; }
                    if (Sys.ultraSave) {
                        Sys.setUltraSave(false, modelData === PowerProfile.PowerSaver ? "power-saver"
                            : modelData === PowerProfile.Performance ? "performance" : "balanced");
                        return;
                    }
                    PowerProfiles.profile = modelData;
                }

                width: (profRow.width - profRow.spacing * (profRow.profiles.length - 1))
                    / profRow.profiles.length
                height: 26
                radius: 4
                activeFocusOnTab: true
                Keys.onReturnPressed: seg.select()
                color: active ? Theme.accent : (hovered || seg.activeFocus ? Theme.track : "transparent")
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
                    onClicked: seg.select()
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
            icon: bar.procIcon(modelData.name)
            label: modelData.name
            value: modelData.pct.toFixed(1) + "%"
        }
    }
}
