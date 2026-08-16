import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import "../common"

// Bottom-center OSD. Volume shows on any sink change (pipewire events);
// brightness shows when the keybind pings `qs ipc call osd brightness`.
PanelWindow {
    id: root

    // decoupled from hideTimer.running: restart() flips running false→true,
    // which would remap the surface and replay the compositor popin per press
    visible: shown
    property bool shown: false
    anchors { bottom: true }
    margins { bottom: 80 }
    implicitWidth: 220
    implicitHeight: 44
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"

    property string mode: "vol" // "vol" | "bright"

    readonly property PwNode sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [root.sink] }

    // suppress the initial property flurry when pipewire binds
    property bool armed: false
    Timer { interval: 1500; running: true; onTriggered: root.armed = true }
    Timer { id: hideTimer; interval: 1400; onTriggered: root.shown = false }

    function show(m) {
        mode = m;
        shown = true;
        hideTimer.restart();
    }

    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { if (root.armed) root.show("vol"); }
        function onMutedChanged() { if (root.armed) root.show("vol"); }
    }

    IpcHandler {
        target: "osd"
        function brightness(): void {
            Sys.refreshBacklight();
            root.show("bright");
        }
    }

    readonly property bool muted: mode === "vol" && (sink?.audio?.muted ?? false)
    readonly property real level: mode === "vol" ? (sink?.audio?.volume ?? 0)
                                                 : Math.max(0, Sys.backlight)

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.surface
        border.color: Theme.islandBorder
        border.width: 1

        Text {
            id: label
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            text: root.mode === "bright" ? "☀ " + Math.round(root.level * 100) + "%"
                : root.muted ? "muted"
                : "vol " + Math.round(root.level * 100) + "%"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            color: Theme.bright
        }
        Rectangle {
            anchors { left: label.right; right: parent.right; leftMargin: 12; rightMargin: 14; verticalCenter: parent.verticalCenter }
            height: 4
            radius: 2
            color: Theme.track
            Rectangle {
                width: parent.width * Math.min(1, root.level)
                height: parent.height
                radius: 2
                color: root.muted ? Theme.dim : Theme.accent
            }
        }
    }
}
