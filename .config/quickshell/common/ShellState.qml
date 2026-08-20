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

    IpcHandler {
        target: "shell"
        function toggle(): void {
            root.hidden = !root.hidden;
            if (root.hidden)
                Notifs.centerOpen = false;
        }
        // layout-switcher.sh changes layouts via `hyprctl eval`, which emits no
        // socket2 event, so it pokes us to refetch workspace data (tiledLayout)
        function refreshLayout(): void {
            Hyprland.refreshWorkspaces();
        }
    }
}
