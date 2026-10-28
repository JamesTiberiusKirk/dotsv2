pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import QtQuick

// The central menu tree (SUPER+SPACE). Rows are declared here, in memory, so
// opening the menu never waits on a process. Live state ("night light ✓") is
// bound to Sys, which the bar already keeps current.
//
// Row: { path, icon, cmd? | run?, confirm? }
//  - path is the tree: "display/rotate/left-up" nests two deep, and a segment
//    is a submenu purely because other rows continue past it.
//  - cmd runs via sh -c; run is a JS function (for Sys setters).
//  - confirm asks before running.
// A leaf must not also be a prefix of another row; onCompleted warns if it is.
Singleton {
    id: root

    function mark(on) { return on ? "✓" : "✗"; }

    // scripts: every file in ~/.scripts/menu/common and ~/.scripts/menu/<host>
    readonly property string home: Quickshell.env("HOME")
    FolderListModel { id: commonScripts; folder: "file://" + root.home + "/.scripts/menu/common"; showDirs: false; showHidden: false }
    // never "": an empty folder means cwd, which listed ~/.dots while hostname was still loading
    FolderListModel { id: hostScripts; folder: "file://" + root.home + "/.scripts/menu/" + (Sys.hostname || "-"); showDirs: false; showHidden: false }
    // A FolderListModel on a folder that does not exist (no ~/.scripts/menu/<host>)
    // falls back to cwd — $HOME under hypr — and every home file became a
    // script row. So a row only counts if its file sits in the folder asked
    // for; endsWith, since `common` is a symlink and may come back resolved.
    function scriptRows() {
        const rows = {};
        for (const [m, dir] of [[commonScripts, "/.scripts/menu/common"], // host last, so it wins on name clash
                                [hostScripts, "/.scripts/menu/" + (Sys.hostname || "-")]])
            for (let i = 0; i < m.count; i++) {
                const f = m.get(i, "filePath"), name = m.get(i, "fileName").replace(/\.sh$/, "");
                if (!f.slice(0, f.lastIndexOf("/")).endsWith(dir)) continue;
                rows[name] = { path: "scripts/" + name, icon: "console",
                               cmd: root.home + "/.scripts/menu-run '" + f + "'" };
            }
        return Object.keys(rows).sort().map(k => rows[k]);
    }

    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    function profileRow(p) {
        const name = p === PowerProfile.PowerSaver ? "power-saver" : p === PowerProfile.Performance ? "performance" : "balanced";
        const icon = p === PowerProfile.PowerSaver ? "leaf" : p === PowerProfile.Performance ? "rocket-launch" : "scale-balance";
        return { path: "power/profile/" + name + " " + mark(PowerProfiles.profile === p), icon: icon,
                 run: () => PowerProfiles.profile = p };
    }

    // Submenu icons, by path. Submenus are not rows (a row is a leaf), so
    // their icons live apart from items.
    readonly property var groupIcons: ({
        "scripts": "console",
        "display": "monitor",
        "display/rotate": "rotate-right",
        "display/layout": "view-grid",
        "display/night light temp": "white-balance-sunny",
        "power": "power",
        "record": "video",
        "record/sound": "speaker",
        "power/profile": "flash",
        "notifications": "bell",
        "notifications/mute": "bell-off",
        "bar": "view-dashboard",
    })

    readonly property var items: {
        const duo = root.home + "/go/bin/duo";
        const rows = scriptRows();

        if (Sys.isDuo) {
            rows.push(
                { path: "display/sub screen " + mark(Sys.subScreen), icon: "television", run: () => Sys.setSubScreen(!Sys.subScreen) },
                { path: "display/auto-rotate " + mark(Sys.autoRotate), icon: "refresh", run: () => Sys.setAutoRotate(!Sys.autoRotate) },
                { path: "display/brightness lock " + mark(Sys.brightnessSync), icon: "white-balance-sunny", run: () => Sys.setBrightnessSync(!Sys.brightnessSync) },
                { path: "display/rotate/normal", icon: "arrow-up", cmd: duo + " rotate normal" },
                { path: "display/rotate/left-up", icon: "rotate-left", cmd: duo + " rotate left-up" },
                { path: "display/rotate/right-up", icon: "rotate-right", cmd: duo + " rotate right-up" },
                { path: "display/rotate/bottom-up", icon: "arrow-down", cmd: duo + " rotate bottom-up" },
                { path: "display/layout/stacked", icon: "view-sequential", cmd: duo + " layout stacked" },
                { path: "display/layout/mirror", icon: "monitor-multiple", cmd: duo + " layout mirror" },
                { path: "display/layout/mirror-flip", icon: "flip-horizontal", cmd: duo + " layout mirror-flip" },
                { path: "display/layout/top-only", icon: "monitor", cmd: duo + " layout top-only" });
        }

        // Records what is on screen as this monitor set's saved layout
        // (~/.local/state/hypr/layouts/). No "arrange" editor: nwg-displays
        // writes a monitors.conf the lua config never reads, then reloads,
        // which re-applies the saved layout — it could never change anything.
        const monLayout = root.home + "/.config/hypr/scripts/monitor-layout.sh";
        rows.push({ path: "display/save arrangement", icon: "view-grid", cmd: monLayout + " save" });

        rows.push(
            { path: "display/glass " + mark(Sys.glassOn), icon: "palette", run: () => Sys.setLook("glass", !Sys.glassOn) },
            { path: "display/transparency " + mark(Sys.transparencyOn), icon: "eye", run: () => Sys.setLook("transparency", !Sys.transparencyOn) });
        rows.push({ path: "display/night light " + mark(Sys.nightLight), icon: "weather-night", run: () => Sys.setNightLight(!Sys.nightLight) });
        for (const k of [2700, 3500, 4500, 5500])
            rows.push({ path: "display/night light temp/" + k + "K " + mark(Sys.nightTemp === k), icon: "white-balance-sunny", run: () => Sys.setNightTemp(k) });

        // record.sh toggles: run the same row again to stop. video records the
        // sound sources ticked under record/sound (several get mixed); gif has none.
        rows.push(
            { path: "record/video", icon: "video", cmd: root.home + "/.scripts/record.sh mp4 " + ShellState.recSources.join(" ") },
            { path: "record/gif", icon: "image-multiple", cmd: root.home + "/.scripts/record.sh gif" });
        // pulse names: a sink's monitor is what plays through it
        for (const [kind, nodes, suffix, icon] of [["desktop", Audio.sinks, ".monitor", "speaker"],
                                                   ["mic", Audio.sources, "", "microphone"]])
            for (const n of nodes) {
                const src = n.name + suffix;
                rows.push({ path: "record/sound/" + kind + ": " + Audio.devName(n).replace(/\//g, "-") + " " + mark(ShellState.recSources.includes(src)),
                            icon: icon, stay: true, run: () => ShellState.toggleRecSource(src) });
            }

        // Suspend stays unguarded: instant and harmless by accident. The rest ask.
        rows.push(
            { path: "power/suspend", icon: "weather-night", cmd: "loginctl suspend" },
            { path: "power/hibernate", icon: "flash", cmd: "loginctl hibernate", confirm: true },
            { path: "power/reboot", icon: "refresh", cmd: "loginctl reboot", confirm: true },
            { path: "power/power off", icon: "power", cmd: "loginctl poweroff", confirm: true },
            { path: "power/exit hyprland", icon: "logout", cmd: 'hyprctl dispatch "hl.dsp.exit()"', confirm: true });
        for (const p of profiles)
            rows.push(profileRow(p));
        if (Sys.chargeLimit >= 0)
            rows.push({ path: "power/charge limit " + mark(Sys.chargeLimitOn), icon: "battery", run: () => Sys.setChargeLimit(!Sys.chargeLimitOn) });

        // Straight onto the singleton, like the rest: a `qs ipc call` here
        // would fork a process for what is one property flip.
        rows.push(
            { path: "notifications/open", icon: "bell", run: () => Notifs.toggle() },
            { path: "notifications/do not disturb " + mark(Notifs.dnd), icon: "bell-off", run: () => Notifs.dnd = !Notifs.dnd },
            { path: "notifications/clear all", icon: "close", run: () => Notifs.dismissAll() });
        // one per sender history has seen — same list the drawer's bottom shows
        for (const app of Notifs.apps)
            rows.push({ path: "notifications/mute/" + app + " " + mark(Notifs.isMuted(app)), icon: "bell-off",
                        run: () => Notifs.setMuted(app, !Notifs.isMuted(app)) });

        // Bar widgets, opened from the keyboard. Toggles, like clicking the
        // cell; the bar picks the panel on the focused screen (Sys.openPanel).
        // openPanel, not togglePanel: it flags the open as keyboard-driven, so
        // the popout takes focus and j/k/Return work inside it.
        // Spelled out rather than read off the bar: the bar's list used to be
        // mirrored into Sys at runtime, and a bar dying with its screen wiped
        // the mirror, so these rows vanished until the shell restarted. Names
        // must match each popout's `panelName` — openPanel silently does
        // nothing for a name no popout answers to.
        for (const [p, icon] of [["audio", "volume-high"], ["bluetooth", "bluetooth"],
                                 ["calendar", "calendar"], ["clanker", "robot"],
                                 ["display", "monitor"],
                                 ["network", "wifi-strength-4"], ["power", "battery"],
                                 ["system", "cpu-64-bit"], ["tailscale", "server"],
                                 ["tray", "dots-horizontal"]])
            rows.push({ path: "bar/" + p, icon: icon, run: () => Sys.openPanel(p) });
        rows.push({ path: "bar/control center", icon: "tune-variant", run: () => Sys.openPanel("cc") });
        rows.push({ path: "bar/system center", icon: "view-dashboard", run: () => Sys.openPanel("cc-sys") });
        // docker and the VMs are one tabbed popout; each keeps its own row so
        // searching "docker" or "vms" still lands on it, on the right tab
        for (const [tab, icon] of [["docker", "docker"], ["vms", "server"]])
            rows.push({ path: "bar/" + tab, icon: icon, run: () => Sys.openPanel("services:" + tab) });
        for (const [side, icon] of [["top", "arrow-up"], ["bottom", "arrow-down"], ["left", "arrow-left"], ["right", "arrow-right"]])
            rows.push({ path: "bar/side/" + side + " " + mark(ShellState.side === side), icon: icon, run: () => ShellState.side = side });

        return rows;
    }

    // A leaf that is also a prefix means one name does two things and the menu
    // shows whichever came first. Only checked once, at shell start.
    Component.onCompleted: {
        for (const l of items)
            if (items.some(r => r.path.startsWith(l.path + "/")))
                console.warn("Menu: leaf is also a submenu: " + l.path);
    }
}
