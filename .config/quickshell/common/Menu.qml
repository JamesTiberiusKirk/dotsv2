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
    function scriptRows() {
        const rows = {};
        for (const m of [commonScripts, hostScripts]) // host last, so it wins on name clash
            for (let i = 0; i < m.count; i++) {
                const f = m.get(i, "filePath"), name = m.get(i, "fileName").replace(/\.sh$/, "");
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
        "power/profile": "flash",
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

        rows.push({ path: "display/night light " + mark(Sys.nightLight), icon: "weather-night", run: () => Sys.setNightLight(!Sys.nightLight) });
        for (const k of [2700, 3500, 4500, 5500])
            rows.push({ path: "display/night light temp/" + k + "K " + mark(Sys.nightTemp === k), icon: "white-balance-sunny", run: () => Sys.setNightTemp(k) });

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
