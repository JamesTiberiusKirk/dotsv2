pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Shell-wide UI state (`qs ipc call shell toggle`). Hiding drops the bar's
// exclusive zone to the frame thickness so windows reclaim the bar body.
Singleton {
    id: root

    property bool hidden: false

    // Which screen edge the bar sits on: top | bottom | left | right.
    // Persisted outside the repo, read back on start.
    property string side: "top"
    readonly property bool vertical: side === "left" || side === "right"
    readonly property bool far: side === "right" || side === "bottom"
    // a vertical bar is one column of stacked/rotated cells; wider than the band
    readonly property int barBody: vertical ? 44 : Theme.barBody

    // OSD capsule per screen name: [width, protrusion] of the bottom-centre
    // card. The chrome (bar/Chrome.qml) draws it as part of the one screen
    // shape; the OSD window only paints its content. Reassigned whole so
    // bindings see the change.
    property var osd: ({})
    function setOsd(screen, g) { const o = Object.assign({}, osd); o[screen] = g; osd = o; }

    FileView {
        id: sideFile
        path: Quickshell.env("HOME") + "/.local/state/qs-bar-side"
        printErrors: false
        property bool ready: false
        onLoaded: {
            const t = text().trim();
            if (["top", "bottom", "left", "right"].includes(t)) root.side = t;
            ready = true;
        }
        onLoadFailed: ready = true
    }
    onSideChanged: if (sideFile.ready) sideFile.setText(side)

    IpcHandler {
        target: "shell"
        function side(s: string): void { root.side = s; }
        function toggle(): void {
            root.hidden = !root.hidden;
            if (root.hidden)
                Notifs.centerOpen = false;
        }
    }
}
