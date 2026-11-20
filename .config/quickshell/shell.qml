//@ pragma UseQApplication
import Quickshell
import QtQuick
import "bar"
import "notifs"
import "launcher"
import "osd"
import "wallpaper"
import "screenshot"
import "common"
import "lcars" as LcarsDir  // makes the shell watch quickshell-lcars/ (needed for the runtime createComponent)

// dshell — quickshell replacement for waybar + dunst + wofi.
// Piloted via `hyprx --shell` (HYPR_SHELL=quickshell); see base.lua autostart.
ShellRoot {
    Frame {}
    Bar {}
    NotifPopups {}
    NotifCenter {}
    Launcher {}
    Osd {}
    Submap {}
    Picker {}
    RegionPicker {}
    Info {}
    BatteryGuard {}

    // LCARS mode: lives in ../quickshell-lcars (symlinked as lcars/). Created
    // and destroyed by hand: nothing is loaded while off, and a broken LCARS
    // file only logs a warning instead of failing the whole shell.
    // (LazyLoader with a source URL preloads even while inactive.)
    Scope {
        id: lcarsHost
        property var obj: null
        // shell start: clear flag files a crash may have left, so the hooks stop writing. LCARS itself
        // comes back via ShellState (saved qs-lcars state + crash guard); the load-failure paths below
        // set lcars=false, which ShellState persists as "off".
        Component.onCompleted: { const rt = Quickshell.env("XDG_RUNTIME_DIR"); if (rt) Quickshell.execDetached(["rm", "-rf", rt + "/lcars-on", rt + "/lcars-agents"]); }
        Connections {
            target: ShellState
            function onLcarsChanged() {
                if (lcarsHost.obj) { lcarsHost.obj.destroy(); lcarsHost.obj = null; }
                if (!ShellState.lcars) return;
                const c = Qt.createComponent(Qt.resolvedUrl("lcars/Lcars.qml"));
                if (c.status !== Component.Ready) { console.warn("LCARS failed to load:", c.errorString()); ShellState.lcars = false; return; }
                lcarsHost.obj = c.createObject(lcarsHost);
                if (!lcarsHost.obj) { console.warn("LCARS createObject failed:", c.errorString()); ShellState.lcars = false; }
            }
        }
    }
}
