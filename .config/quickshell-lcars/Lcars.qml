import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import QtQuick
import "."
import "../common"

// LCARS root, created by the real shell (quickshell/shell.qml) through the
// quickshell/lcars symlink. Never loaded by dev.qml.
Scope {
    id: root
    ConsoleState { id: uiState; screenPresent: Quickshell.screens.some(s => s.name === "eDP-2") }
    LiveData { id: live; consoleShown: uiState.consoleShown || uiState.panelOpen; attended: uiState.attended }
    ComputerIpc { ship: live; ui: uiState }   // target "computer": the COMPUTER station's MCP server (computer/mcp.py) drives the shell through it
    // keyboard focus is requested only while the COMPUTER input is being typed in (live.computer.typing); anything that moves the UI drops it
    Connections {
        target: uiState
        function onStationChanged() { live.computer.typing = false; }
        function onReleasedChanged() { live.computer.typing = false; }
        function onPanelOpenChanged() { live.computer.typing = false; }
        function onAttendedChanged() { if (!uiState.attended) live.computer.typing = false; }
    }

    // a password must never go into the chat box: a polkit prompt takes the keyboard back
    Connections {
        target: polkit
        function onIsActiveChanged() { if (polkit.isActive) live.computer.typing = false; }
    }

    // Sanity line: "shared state: true" means LCARS sees the shell's own
    // singletons (a duplicated ShellState would still read false here).
    // The lcars-on flag file gates the Claude Code hooks (~/.scripts/lcars-hook.sh): they do nothing without it.
    readonly property string rt: Quickshell.env("XDG_RUNTIME_DIR")
    Component.onCompleted: {
        console.log("LCARS online. shared state:", ShellState.lcars,
            "| messages:", live.messages, "| battery:", Math.round(live.battery));
        if (rt) Quickshell.execDetached(["touch", rt + "/lcars-on"]);
    }
    Component.onDestruction: {
        if (rt) Quickshell.execDetached(["rm", "-rf", rt + "/lcars-on", rt + "/lcars-agents"]);
        // the COMPUTER's leftovers: server config (holds env), opening prompts, microphone scratch folders
        if (rt) Quickshell.execDetached(["sh", "-c", 'cd "$1/lcars-computer" 2>/dev/null && rm -rf mcp*.json mcp*.json.tmp prompts listen.*', "sh", rt]);
        Lc.alert = false; Lc.pulse = 1;   // the Binding does not restore on destroy; the pulse Timer stops with alert
    }

    // red alert: palette flips while an unacknowledged alert stands; Lc runs the one 500ms pulse timer
    Binding { target: Lc; property: "alert"; value: live.alert !== "CONDITION GREEN" && !live.alertAcked }
    // klaxon once when the alert rises from green (not under DND)
    property string prevAlert: "CONDITION GREEN"
    Connections {
        target: live
        function onAlertChanged() {
            if (root.prevAlert === "CONDITION GREEN" && live.alert !== "CONDITION GREEN" && !live.dnd)
                Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"]);
            root.prevAlert = live.alert;
        }
    }

    // polkit: this agent exists only while LCARS is on. Registered = the privileged pills go live.
    PolkitAgent { id: polkit }
    Binding { target: live; property: "authReady"; value: polkit.isRegistered }
    AuthPrompt { agent: polkit }

    // Bottom screen (eDP-2) only; absent while the keyboard is docked. Two windows with CONSTANT anchors
    // (changing anchors or exclusive zone on a mapped layer surface crashed Hyprland): the full console,
    // and a narrow stub that keeps only the spine while released. Only `visible` flips.
    Variants {
        model: Quickshell.screens.filter(s => s.name === "eDP-2")
        Scope {
            id: lowScope
            required property var modelData
            // black backdrop + desk readout; Bottom = above the wallpaper, below app windows. Input only on the DeckInfo pills.
            PanelWindow {
                screen: lowScope.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                color: "black"
                mask: Region { item: desk.pillArea }
                WlrLayershell.namespace: "lcars-backdrop"
                WlrLayershell.layer: WlrLayer.Bottom
                DeskInfo { id: desk; anchors.fill: parent; ship: live; mon: lowScope.modelData.name; topInset: 0 }
            }
            PanelWindow {
                screen: lowScope.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                visible: !uiState.released
                color: "transparent"
                WlrLayershell.namespace: "lcars-console"
                WlrLayershell.layer: WlrLayer.Top
                // typing in the COMPUTER station needs keyboard focus on tap; every other station takes none
                WlrLayershell.keyboardFocus: live.computer.typing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                Console { anchors.fill: parent; ship: live; ui: uiState }
            }
            PanelWindow {
                screen: lowScope.modelData
                anchors { top: true; bottom: true; left: true }
                implicitWidth: Lc.pad + Lc.topSpine
                exclusionMode: ExclusionMode.Normal
                exclusiveZone: implicitWidth
                visible: uiState.released
                color: "transparent"
                WlrLayershell.namespace: "lcars-console-stub"
                WlrLayershell.layer: WlrLayer.Top
                Console { anchors.fill: parent; stubOnly: true; ship: live; ui: uiState }
            }
        }
    }

    // Popout keybinds (Sys.openPanel/togglePanel): the normal bar is gone on eDP-1 while LCARS is on,
    // so when eDP-1 is focused map the panel to its station on the console. Unmapped names are ignored.
    Connections {
        target: Sys
        function onTogglePanel(name) {
            if (Hyprland.focusedMonitor?.name === "eDP-1") uiState.showPanel(name);
        }
        function onCloseAll() { uiState.panelOpen = false; }
    }

    // Top screen (eDP-1): one painted window (mask = bar + spine only, clicks elsewhere pass through)
    // plus two invisible space reservers so windows tile inside the frame. Anchors are never changed
    // on a mapped surface.
    Variants {
        model: Quickshell.screens.filter(s => s.name === "eDP-1")
        Scope {
            id: topScope
            required property var modelData
            // spine runs on to the lower screen only when that screen sits directly below (or is dark)
            readonly property var lower: Quickshell.screens.find(s => s.name === "eDP-2") ?? null
            readonly property bool hinge: !lower || (lower.x === modelData.x && lower.y === modelData.y + modelData.height)

            // docked fallback: the current station as a panel while eDP-2 is off. Constant anchors, only
            // `visible` flips. No click-outside backdrop; close via CLOSE or the station tap (panel takes no keyboard focus, so no Esc).
            PanelWindow {
                screen: topScope.modelData
                anchors { top: true; bottom: true; left: true }
                margins { left: 76; top: 72; bottom: 20 }
                implicitWidth: Math.min(1100, topScope.modelData.width - 92)
                exclusionMode: ExclusionMode.Ignore
                visible: uiState.panelOpen && !uiState.screenPresent
                color: "transparent"
                WlrLayershell.namespace: "lcars-panel"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: live.computer.typing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                StationPanel { anchors.fill: parent; ship: live; ui: uiState }
            }
            // black backdrop + desk readout; Bottom = above the wallpaper, below app windows. Input only on the DeckInfo pills.
            PanelWindow {
                screen: topScope.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                color: "black"
                mask: Region { item: desk.pillArea }
                WlrLayershell.namespace: "lcars-backdrop"
                WlrLayershell.layer: WlrLayer.Bottom
                DeskInfo { id: desk; anchors.fill: parent; ship: live; mon: topScope.modelData.name; topInset: Lc.pad + Lc.topBar }
            }
            PanelWindow {
                screen: topScope.modelData
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                WlrLayershell.namespace: "lcars-top"
                WlrLayershell.layer: WlrLayer.Top
                mask: Region { item: frame.barArea; Region { item: frame.spineArea } Region { item: frame.elbowArea } }
                TopFrame { id: frame; anchors.fill: parent; ship: live; ui: uiState; hinge: topScope.hinge }
            }
            PanelWindow {
                screen: topScope.modelData
                anchors { top: true; left: true; right: true }
                implicitHeight: Lc.pad + Lc.topBar
                exclusionMode: ExclusionMode.Normal
                exclusiveZone: implicitHeight
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "lcars-frame"
            }
            PanelWindow {
                screen: topScope.modelData
                anchors { top: true; bottom: true; left: true }
                implicitWidth: Lc.pad + Lc.topSpine
                exclusionMode: ExclusionMode.Normal
                exclusiveZone: implicitWidth
                color: "transparent"
                mask: Region {}
                WlrLayershell.namespace: "lcars-frame"
            }
        }
    }
}

