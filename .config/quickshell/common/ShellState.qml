pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import QtQuick

// Shell-wide UI state (`qs ipc call shell toggle`). Hiding drops a bar's
// exclusive zone to the frame thickness so windows reclaim the bar body.
Singleton {
    id: root

    // Screen names (Hyprland connector, e.g. "HDMI-A-1") whose bar is hidden.
    // Per screen, persisted outside the repo. Reassigned whole so bindings see the change.
    property var hiddenOn: []
    function isHidden(screen) { return hiddenOn.includes(screen); }

    FileView {
        id: hiddenFile
        path: Quickshell.env("HOME") + "/.local/state/qs-bar-hidden"
        printErrors: false
        property bool ready: false
        onLoaded: {
            try {
                const t = JSON.parse(text());
                if (Array.isArray(t)) root.hiddenOn = t.filter(n => typeof n === "string");
            } catch (e) { console.warn("ShellState: bad qs-bar-hidden:", e); }
            ready = true;
        }
        onLoadFailed: ready = true
    }
    onHiddenOnChanged: if (hiddenFile.ready) hiddenFile.setText(JSON.stringify(hiddenOn))

    // wl-screenrec running: "" | "mp4" | "gif", and when it started (ms).
    // ~/.scripts/record.sh sets both via `qs ipc call region recStart/recStop`.
    property string recording: ""
    property real recStarted: 0
    // pulse source names record/video records as audio (ticked in the menu, session only)
    property var recSources: []
    function toggleRecSource(src) {
        recSources = recSources.includes(src) ? recSources.filter(s => s !== src) : recSources.concat([src]);
    }

    // Which screen edge the bar sits on: top | bottom | left | right.
    // Persisted outside the repo, read back on start.
    property string side: "left"
    readonly property bool vertical: side === "left" || side === "right"
    readonly property bool far: side === "right" || side === "bottom"
    // frame band thickness on an edge: full where the bar sits, thin elsewhere
    function bandT(edge) { return edge === side ? Theme.frameT : Theme.frameTEdge; }
    // a vertical bar is one column of stacked/rotated cells; wider than the band
    readonly property int barBody: vertical ? 44 : Theme.barBody

    // OSD capsule per screen name: [width, protrusion] of the bottom-centre
    // card. The chrome (bar/Chrome.qml) draws it as part of the one screen
    // shape; the OSD window only paints its content. Reassigned whole so
    // bindings see the change.
    property var osd: ({})
    function setOsd(screen, g) { const o = Object.assign({}, osd); o[screen] = g; osd = o; }
    // same for the submap chip on the top edge (osd/Submap.qml)
    property var top: ({})
    function setTop(screen, g) { const o = Object.assign({}, top); o[screen] = g; top = o; }

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

    // ---- which indicator shows where ----
    // Every bar indicator that can fold into a control center, in bar order. Not here: the mic dot
    // (privacy), the bell (its drawer is not a popout yet), the control center cells themselves.
    // `group` picks the control center it folds into: "sys" (the left island's) or "status".
    // Each AI agent is its own indicator, "clanker:<id>", so the list follows Clanker.agents.
    readonly property var indicators: {
        const agentRows = Clanker.agents.map(a => ({ name: "clanker:" + a.id, title: a.name || a.id,
                                                      island: "left island", group: "sys", agent: a.id }));
        return [
            { name: "docker",    title: "docker",         island: "left island", group: "sys" },
            { name: "vms",       title: "vms",            island: "left island", group: "sys" },
            { name: "system",    title: "system",         island: "left island", group: "sys" },
            { name: "jobs",      title: "cron jobs",      island: "left island", group: "sys" }
        ].concat(agentRows, [
            { name: "network",   title: "wifi",           island: "status", group: "status" },
            { name: "tailscale", title: "tailscale",      island: "status", group: "status" },
            { name: "power",     title: "battery",        island: "status", group: "status" },
            { name: "display",   title: "display",        island: "status", group: "status" },
            { name: "kbd",       title: "keyboard light", island: "status", group: "status" },
            { name: "audio",     title: "sound",          island: "status", group: "status" },
            { name: "bluetooth", title: "bluetooth",      island: "status", group: "status" },
            { name: "tray",      title: "tray",           island: "tray island", group: "status" },
            { name: "calendar",  title: "calendar",       island: "tray island", group: "status" }
        ]);
    }
    readonly property var names: indicators.map(i => i.name)
    // Does the thing behind an indicator exist on this host. The gate the bar cells used to carry each.
    // An agent is present while Clanker lists it.
    readonly property var present: {
        const m = {
            docker: true, vms: true, system: true, jobs: Jobs.count > 0, network: true,
            tailscale: Sys.tsPresent, power: UPower.displayDevice?.isLaptopBattery ?? false,
            display: Sys.backlight >= 0, kbd: Sys.duoKbd, audio: true, bluetooth: Bt.present,
            tray: SystemTray.items.values.length > 0, calendar: true
        };
        for (const a of Clanker.agents) m["clanker:" + a.id] = true;
        return m;
    }
    // Which control center a panel belongs to. "services" is docker's and the vms' shared popout,
    // "clanker" the agents' one, "cc-sys" the sys page itself.
    function groupOf(name) {
        return name === "docker" || name === "vms" || name === "services" || name === "system" || name === "jobs"
            || name === "clanker" || name === "cc-sys"
            || name.startsWith("clanker:") ? "sys" : "status";
    }
    // panelName of a group's control center page
    function ccName(group) { return group === "sys" ? "cc-sys" : "cc"; }

    // Every present indicator always sits in its group's control center, so the one switch is
    // whether it also shows in the bar. Nothing can be unreachable, so anything may be unpinned.
    // Reassigned whole so bindings see the change.
    // No "clanker" in the default pins: an agent seen for the first time stays in the center only.
    property var pins: ["network", "power", "audio", "docker", "vms", "system", "jobs", "tray", "calendar"]
    function inBar(n) { return pins.includes(n) && present[n] === true; }
    function inCC(n) { return present[n] === true; }
    function anyInCC(group) { return indicators.some(i => i.group === group && inCC(i.name)); }
    // Is the popout called `panelName` reachable from the bar itself? The agents' popout is one page
    // for every agent, so for "clanker" any pinned agent counts.
    function inBarPanel(panelName) {
        return panelName === "clanker" ? indicators.some(i => i.agent !== undefined && inBar(i.name)) : inBar(panelName);
    }
    function setPin(n, on) {
        pins = on ? pins.filter(x => x !== n).concat([n]) : pins.filter(x => x !== n);
    }
    function togglePin(n) { setPin(n, !pins.includes(n)); }
    // right-click on a bar cell: off the bar (it is still in its control center)
    function fold(n) { setPin(n, false); }

    // The one place pins is made consistent; pure, so scratchpad/pins-test3.js runs this very text.
    //  - names nobody knows are dropped, except "clanker" and "clanker:*": agents arrive from Clanker
    //    after this file loads, so an agent not listed yet must not be forgotten.
    //  - the old single "clanker" entry becomes every agent. With no agents known yet it stays as it
    //    is (and is written back as it is) until they show up.
    //  - the old "services" entry (docker and vms were one cell) becomes both.
    // norm:begin
    function norm(p, names, ids) {
        const agents = ids.map(i => "clanker:" + i);
        const keep = n => names.includes(n) || n === "clanker" || n.startsWith("clanker:");
        const expand = a => [].concat(...a.map(n => n === "services" ? ["docker", "vms"]
                                                  : n === "clanker" && ids.length ? agents : [n]));
        return expand((Array.isArray(p) ? p : []).filter(n => typeof n === "string"))
                   .filter(keep).filter((n, i, all) => all.indexOf(n) === i);
    }
    // norm:end
    function sameList(a, b) { return a.length === b.length && a.every((n, i) => n === b[i]); }
    // Assign only what differs: pins feeds the bar's visibility bindings and the save handler,
    // and Clanker re-publishes its agents every refresh, which re-runs this with nothing to change.
    function normalise() {
        const r = norm(pins, names, Clanker.agents.map(a => a.id));
        if (!sameList(r, pins)) pins = r;
    }
    onNamesChanged: normalise()

    // Same shape as sideFile. Loading assigns pins before ready flips, so the first load
    // never writes the file back; a missing file keeps the defaults above. Older files also
    // carry a "cc" list from when tiles could be removed; it is ignored and dropped on the next write.
    FileView {
        id: pinsFile
        path: Quickshell.env("HOME") + "/.local/state/qs-bar-pins"
        printErrors: false
        property bool ready: false
        onLoaded: {
            try {
                const t = JSON.parse(text());
                root.pins = Array.isArray(t.pins) ? t.pins : [];
            } catch (e) { console.warn("ShellState: bad qs-bar-pins:", e); }
            // also after a bad file or a missing one: agents may already be listed, and
            // names only signals a change, not its first value
            root.normalise();
            ready = true;
        }
        onLoadFailed: { root.normalise(); ready = true; }
    }
    onPinsChanged: if (pinsFile.ready) pinsFile.setText(JSON.stringify({ pins: pins }))

    // LCARS mode (quickshell-lcars/, loaded by shell.qml). Persisted in qs-lcars ("on"/"off"),
    // same shape as sideFile, and only ever auto-enabled on the Duo.
    // Crash guard: $XDG_RUNTIME_DIR/qs-lcars-booting is created when a start brings LCARS up and
    // removed 15s later. If it is still there at the next start, that bring-up died: start normal,
    // save "off" and say so. The runtime dir is wiped on reboot, so a reboot never trips it.
    property bool lcars: false
    readonly property string lcarsBootMarker: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-lcars-booting"
    FileView {
        id: lcarsFile
        path: Quickshell.env("HOME") + "/.local/state/qs-lcars"
        printErrors: false
        property bool ready: false
        onLoaded: {
            ready = true;
            root.lcarsSavedOn = text().trim() === "on";
            root.lcarsRestore();
        }
        onLoadFailed: ready = true
    }
    // Sys.hostname comes from its own async FileView, so isDuo may still be false when
    // qs-lcars loads. Restore once, when both the saved state and the hostname are known.
    property bool lcarsSavedOn: false
    property bool lcarsRestored: false
    function lcarsRestore() {
        if (lcarsRestored || !lcarsFile.ready || Sys.hostname === "") return;
        lcarsRestored = true;
        if (lcarsSavedOn && Sys.isDuo) lcarsMarkerCheck.running = true;
    }
    Connections {
        target: Sys
        function onHostnameChanged() { root.lcarsRestore(); }
    }
    // exit 0 = marker left by ANOTHER qs process = the last bring-up crashed. The marker holds our
    // pid, so a config reload inside the 15s (same process, timer lost with the old generation) is not a crash.
    Process {
        id: lcarsMarkerCheck
        command: ["sh", "-c", '[ -e "$1" ] && [ "$(cat "$1")" != "$2" ]', "sh", root.lcarsBootMarker, String(Quickshell.processId)]
        onExited: code => {
            if (code === 0) {
                lcarsFile.setText("off");
                Quickshell.execDetached(["rm", "-f", root.lcarsBootMarker]);
                Quickshell.execDetached(["notify-send", "LCARS skipped after a crash", "Run lcars to re-enable"]);
            } else {
                Quickshell.execDetached(["sh", "-c", 'echo "$2" > "$1"', "sh", root.lcarsBootMarker, String(Quickshell.processId)]);
                lcarsMarkerClear.restart();
                root.lcars = true;
            }
        }
    }
    Timer {
        id: lcarsMarkerClear
        interval: 15000
        onTriggered: Quickshell.execDetached(["rm", "-f", root.lcarsBootMarker])
    }
    // also persists the "off" from shell.qml's load-failure path
    onLcarsChanged: if (lcarsFile.ready) lcarsFile.setText(lcars ? "on" : "off")
    // Screens that keep the normal bar: LCARS owns both built-in panels while on.
    readonly property var lcarsScreens: lcars ? Quickshell.screens.filter(s => !s.name.startsWith("eDP")) : Quickshell.screens

    function toggleLcars() { if (Sys.isDuo) { Sys.closeAll(); lcars = !lcars; } }

    IpcHandler {
        target: "shell"
        function side(s: string): void { root.side = s; }
        // closeAll first: popout flags must not stick when the eDP bars are destroyed
        function lcars(): void { root.toggleLcars(); }
        // flips the bar on the focused monitor
        function toggle(): void {
            const n = Hyprland.focusedMonitor?.name;
            if (!n) return;
            const hide = !root.isHidden(n);
            root.hiddenOn = hide ? root.hiddenOn.concat([n]) : root.hiddenOn.filter(x => x !== n);
            if (hide)
                Notifs.centerOpen = false;
        }
    }
}
