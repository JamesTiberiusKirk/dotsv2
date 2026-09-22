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

// ---- display panel (click the backlight cell) ----
// Built from what the machine actually has: one slider per DRM
// backlight, the sync lock only when there are two to lock, and the
// Duo-only rows only on the Duo. A desktop has no backlights at all,
// so the trigger cell is hidden and this never opens.
Popout {
    id: displayPopout

    panelName: "display"
    implicitWidth: 280
    rowSpacing: 10
    tabs: ["screen", "idle", "monitors"]
    onOpenChanged: Sys.panelOpen = open

    // Generalised out of the brightness slider so the
    // night-light temperature could reuse it: same drag
    // ownership, same 50ms write throttle, different range
    // and a caller-supplied commit.


    // Per-output scale as preset pills. 1.6 is in the list
    // because Hyprland coerces to it: a scale that would
    // give a non-integer logical size is refused and the
    // nearest workable one used instead, so 1.5 on a
    // 2560-wide panel comes back 1.6. Without the pill the
    // row would show nothing selected after a legal click.
    component ScaleRow: Item {
        id: sr
        property string name
        property real scale: 1
        readonly property var presets: [1, 1.25, 1.5, 1.6, 2, 3]
        // Local echo of the click, the same trick
        // ValueSlider plays with `shown`: Sys.monitors is
        // left alone so the Repeater does not rebuild this
        // delegate out from under the gesture. The probe
        // pushes the compositor's real answer back through
        // `scale`, which is how a coerced value corrects.
        property real shown: 0
        onScaleChanged: shown = scale
        Component.onCompleted: shown = scale

        width: displayPopout.contentWidth
        height: 20
        // arrows / h / l step presets, matching the sliders
        // and the idle steppers. Nearest-first, since the
        // live scale need not be one of ours.
        activeFocusOnTab: true
        Keys.onLeftPressed: sr.hstep(-1)
        Keys.onRightPressed: sr.hstep(1)
        function hstep(d) {
            let i = 0;
            for (let k = 1; k < sr.presets.length; k++)
                if (Math.abs(sr.presets[k] - sr.shown) < Math.abs(sr.presets[i] - sr.shown)) i = k;
            const n = Math.max(0, Math.min(sr.presets.length - 1, i + d));
            if (sr.presets[n] !== sr.shown) {
                sr.shown = sr.presets[n];
                Sys.setScale(sr.name, sr.presets[n]);
            }
        }

        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: 5
            color: sr.activeFocus ? Theme.track : "transparent"
        }
        Text {
            text: sr.name
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.text
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 4
            Repeater {
                model: sr.presets
                Rectangle {
                    required property var modelData
                    // hyprctl reports 1.5 as 1.50; compare loosely
                    readonly property bool on: Math.abs(modelData - sr.shown) < 0.01
                    width: pill.width + 10; height: 16; radius: 4
                    color: on ? Theme.accent
                         : (pillArea.containsMouse ? Theme.track : "transparent")
                    Text {
                        id: pill
                        anchors.centerIn: parent
                        text: String(modelData)
                        font.family: Theme.font; font.pixelSize: 10
                        color: parent.on ? Theme.accentText : Theme.dim
                    }
                    MouseArea {
                        id: pillArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            sr.shown = modelData;
                            Sys.setScale(sr.name, modelData);
                        }
                    }
                }
            }
        }
    }

    Column {
        visible: displayPopout.currentTab === "screen"
        width: displayPopout.contentWidth
        spacing: 10

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
            width: displayPopout.contentWidth; height: 1
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
    }

    // ---- idle ladder (hypridle) ----
    // One row per stage: label, 5-min-grid stepper, enable
    // switch. Stepping a disabled stage re-enables it
    // (matching the script: `set` implies on). "keep
    // awake" drops all the timeouts — the ladder greys.
    component StepBtn: Rectangle {
        id: sb
        property string glyph
        signal clicked
        width: 16; height: 16; radius: 4
        anchors.verticalCenter: parent.verticalCenter
        color: sbArea.containsMouse ? Theme.track : "transparent"
        Text {
            anchors.centerIn: parent
            text: sb.glyph
            font.family: Theme.font; font.pixelSize: 12
            color: Theme.text
        }
        MouseArea {
            id: sbArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: sb.clicked()
        }
    }
    component IdleRow: Item {
        id: ir
        property string label
        property int minutes
        property bool on
        signal toggled(bool v)
        signal setMinutes(int m)

        width: displayPopout.contentWidth
        height: 20
        opacity: (Sys.idleRunning && !Sys.idleAwake) ? 1 : 0.4
        // Return is the switch, arrows / h / l are the steppers
        activeFocusOnTab: true
        Keys.onReturnPressed: ir.toggled(!ir.on)
        Keys.onLeftPressed: ir.hstep(-1)
        Keys.onRightPressed: ir.hstep(1)
        // snap to the 5-min grid rather than ±5, so the 1-min
        // floor doesn't knock every later step off it (1→6→11)
        function hstep(d) {
            const m = ir.minutes;
            const v = d > 0 ? (Math.floor(m / 5) + 1) * 5 : (Math.ceil(m / 5) - 1) * 5;
            ir.setMinutes(Math.max(1, Math.min(180, v)));
        }

        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: 5
            color: ir.activeFocus ? Theme.track : "transparent"
        }
        Text {
            text: ir.label
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font; font.pixelSize: 11
            color: ir.on ? Theme.text : Theme.dim
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 6

            StepBtn {
                glyph: "−"
                onClicked: ir.hstep(-1)
            }
            Text {
                // fixed width so +/- don't shift as digits change
                width: 44
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                text: ir.minutes + " min"
                font.family: Theme.font; font.pixelSize: 11
                color: ir.on ? Theme.text : Theme.dim
            }
            StepBtn {
                glyph: "+"
                onClicked: ir.hstep(1)
            }
            // same switch as ToggleRow, its own hit area
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 16; radius: 8
                color: ir.on ? Theme.accent : Theme.track
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    x: ir.on ? parent.width - width - 2 : 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12; height: 12; radius: 6
                    color: ir.on ? Theme.accentText : Theme.bright
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: ir.toggled(!ir.on)
                }
            }
        }
    }

    Rectangle {
        width: displayPopout.contentWidth; height: 1
        color: Theme.islandBorder
    }
    Column {
        visible: displayPopout.currentTab === "idle"
        width: displayPopout.contentWidth
        spacing: 10

        ToggleRow {
            label: "keep awake"
            checked: Sys.idleAwake
            onToggled: v => Sys.setIdleAwake(v)
        }
        IdleRow {
            label: "lock"
            minutes: Sys.idleLock; on: Sys.idleLockOn
            onToggled: v => Sys.setIdleStage("lock", v)
            onSetMinutes: m => Sys.setIdleMinutes("lock", m)
        }
        IdleRow {
            label: "screen off"
            minutes: Sys.idleScreen; on: Sys.idleScreenOn
            onToggled: v => Sys.setIdleStage("screen", v)
            onSetMinutes: m => Sys.setIdleMinutes("screen", m)
        }
        IdleRow {
            label: "suspend"
            minutes: Sys.idleSuspend; on: Sys.idleSuspendOn
            onToggled: v => Sys.setIdleStage("suspend", v)
            onSetMinutes: m => Sys.setIdleMinutes("suspend", m)
        }
    }


    Column {
        visible: displayPopout.currentTab === "monitors"
        width: displayPopout.contentWidth
        spacing: 10

        Repeater {
            model: Sys.monitors
            ScaleRow {
                name: modelData.name
                scale: modelData.scale
            }
        }

        Rectangle {
            visible: Sys.isDuo
            width: displayPopout.contentWidth; height: 1
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
