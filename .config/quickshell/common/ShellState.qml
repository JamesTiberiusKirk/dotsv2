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
            { name: "system",    title: "system",         island: "left island", group: "sys" }
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
            docker: true, vms: true, system: true, network: true,
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
        return name === "docker" || name === "vms" || name === "services" || name === "system"
            || name === "clanker" || name === "cc-sys"
            || name.startsWith("clanker:") ? "sys" : "status";
    }
    // panelName of a group's control center page
    function ccName(group) { return group === "sys" ? "cc-sys" : "cc"; }

    // Every present indicator always sits in its group's control center, so the one switch is
    // whether it also shows in the bar. Nothing can be unreachable, so anything may be unpinned.
    // Reassigned whole so bindings see the change.
    // No "clanker" in the default pins: an agent seen for the first time stays in the center only.
    property var pins: ["network", "power", "audio", "docker", "vms", "system", "tray", "calendar"]
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

    IpcHandler {
        target: "shell"
        function side(s: string): void { root.side = s; }
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
