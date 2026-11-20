import Quickshell
import Quickshell.Io
import QtQuick
import "."

// Shell side of the COMPUTER station's MCP server (computer/mcp.py): `qs ipc call computer <fn> <args>`.
// One instance in Lcars.qml (live) and dev.qml (fake data). Everything is validated here again: mcp.py is
// not the only possible caller, and its inputs come from a model that reads web pages. Reads return JSON
// strings. Only fields that stay live while no station page is open are used here.
Scope {
    id: root
    required property var ship
    required property var ui

    readonly property var pageNames: ({
        BRIDGE: ["STATUS", "COMMAND DECK"], CREW: ["AWAY TEAMS", "DILITHIUM"],
        SYSTEMS: ["HARDWARE", "POWER", "STORAGE", "SYSTEM"], COMMS: ["MESSAGES", "AUDIO", "BLUETOOTH", "NETWORK"],
        SETTINGS: ["DISPLAY", "INPUT", "LOOK", "OVERRIDES"], COMPUTER: ["CHAT", "CONFIG"] })
    readonly property var nameRe: /^[A-Za-z0-9_.][A-Za-z0-9_.-]*$/

    function _p(x) { return Math.round(Number(x) * 100); }
    function _ok(what) { console.log("computer ipc:", what); return "ok"; }
    function _no(why) { console.log("computer ipc: refused:", why); return "error: " + why; }

    // a page request nobody consumed (no loader active) must not fire on some later station change
    Timer { id: wantClear; interval: 1500; onTriggered: root.ui.wantPage = -1 }

    IpcHandler {
        id: h
        target: "computer"

        function status(): string {
            const s = root.ship;
            return JSON.stringify({
                battery_pct: Math.round(s.battery), battery_state: s.batteryState, battery_note: s.batteryNote,
                cpu_pct: _p(s.cpu), memory_pct: _p(s.mem), memory: s.memText, power_profile: s.profile,
                wifi_on: s.wifi, wifi_network: s.netText, bluetooth_on: s.bt, tailscale_on: s.tailscale,
                do_not_disturb: s.dnd, night_light: s.night, ultra_save: s.ultra, alert: s.alert, hostname: s.hostname,
                volume_pct: _p(s.volume), muted: s.muted, brightness_pct: _p(s.brightness),
                audio_outputs: s.audioSinks.map(n => ({ name: n.name, current: n.current, muted: n.muted })),
                bluetooth_devices: s.btDevices.map(d => ({ name: d.name, connected: d.connected, battery_pct: d.battery })),
                media: { title: s.mediaTitle, artist: s.mediaArtist, player: s.mediaPlayer, playing: s.playing },
                notifications: s.messages });
        }
        function usage(): string {
            return JSON.stringify({ shown_pct: Math.round(root.ship.claude * 100), note: root.ship.claudeNote,
                agents: root.ship.agents.map(a => ({ name: a.name, tier: a.tier, status: a.status,
                    limits: a.limits.map(l => ({ title: l.title, pct: Math.round(l.pct * 100), resets_in: l.reset })) })) });
        }
        function workspaces(): string {
            return JSON.stringify(root.ship.workspaces.map(w => ({ id: w.id, monitor: w.monitor, active: w.active, urgent: w.urgent })));
        }

        function toggle(name: string, on: bool): string {
            const s = root.ship;
            if (name === "wifi") s.setWifi(on);
            else if (name === "bluetooth") s.setBt(on);
            else if (name === "dnd") s.setDnd(on);
            else if (name === "mute") s.setMute(on);
            else return _no("unknown switch");
            return _ok(name + " " + on);
        }
        function level(name: string, pct: int): string {
            const v = Math.max(name === "brightness" ? 1 : 0, Math.min(100, pct)) / 100;
            if (name === "volume") root.ship.setVolume(v);
            else if (name === "brightness") root.ship.setBrightness(v);
            else return _no("unknown level");
            return _ok(name + " " + v);
        }
        function media(action: string): string {
            if (action === "play_pause") root.ship.playPause();
            else if (action === "next") root.ship.next();
            else if (action === "previous") root.ship.prev();
            else return _no("unknown media action");
            return _ok("media " + action);
        }
        function profile(p: string): string {
            if (p !== "power-saver" && p !== "balanced" && !(p === "performance" && root.ship.hasPerformance)) return _no("unknown profile");
            root.ship.setProfile(p);
            return _ok("profile " + p);
        }
        function workspace(n: int): string {
            root.ship.dispatch("hl.dsp.focus({ workspace = " + Math.max(1, Math.min(99, Math.round(n))) + " })");
            return _ok("workspace " + n);
        }
        // page is a name from pageNames ("" = leave the first page). Station first, then page: the loaders apply wantPage to the item they just built.
        function station(name: string, page: string): string {
            const pages = root.pageNames[name];
            if (!pages) return _no("unknown station");
            const idx = page === "" ? 0 : pages.indexOf(page.toUpperCase());
            if (idx < 0) return _no("unknown page, use one of " + pages.join(", "));
            root.ui.station = name;
            if (root.ui.screenPresent) root.ui.released = false; else root.ui.panelOpen = true;
            root.ui.poke();
            root.ui.wantPage = idx;
            const shown = root.ui.wantPage < 0;      // a loader took it synchronously
            if (!shown) wantClear.restart();
            return _ok("station " + name + " page " + pages[idx]) + (shown ? "" : ": console not showing, page may not apply");
        }

        // ---- permission and confirm cards. There is NO function here that sets an answer: only a tap on the card does (Computer.qml -> brain.settle).
        // mcp.py asks, then polls answer(). A leading space on title/detail (added by mcp.py so qs never reads them as options) is removed.
        function ask(id: string, kind: string, always: bool, title: string, detail: string): string {
            if (!/^[0-9a-f]{32}$/.test(id) || (kind !== "tap" && kind !== "ask" && kind !== "slide")) return _no("bad ask");
            if (!root.ship.computer.ask(id, kind, always, title.replace(/^ /, ""), detail.replace(/^ /, ""))) return _no("ask refused");
            root.ui.station = "COMPUTER";
            if (root.ui.screenPresent) root.ui.released = false; else root.ui.panelOpen = true;
            root.ui.poke();
            root.ui.wantPage = 0;
            wantClear.restart();
            return _ok("ask " + kind);
        }
        function answer(id: string): string {
            return /^[0-9a-f]{32}$/.test(id) ? root.ship.computer.peek(id) : "gone";
        }
        // gives up on a card (mcp.py timed out): can only turn pending into expired, never into allow
        function askDone(id: string): string {
            return /^[0-9a-f]{32}$/.test(id) ? root.ship.computer.settle(id, "expired") : "gone";
        }

        // ---- follow-up watch (the state lives in ComputerBrain). watchAdd is called by mcp.py only inside claude_tell after the user's tap; the brain checks every value again and caps the list at 6.
        // The tools watch_status / watch_set / watch_cancel change nothing outside the Computer, so they need no card. Nothing here can make a card answer.
        function watchAdd(sid: string, id: string, name: string, folder: string, sess: string, sent: string, marker: string): string {
            const r = root.ship.computer.watchAdd(sid, id, name, folder, sess, sent, marker);
            return r === "ok" ? _ok("watch add") : _no(r.replace(/^error: /, ""));
        }
        function watchList(): string { return root.ship.computer.watchList(); }
        function watchSet(ref: string, on: bool): string {
            const r = root.ship.computer.watchSet(ref, on);
            return r.startsWith("ok") ? _ok("watch set " + on) + r.slice(2) : _no(r.replace(/^error: /, ""));
        }
        function watchCancel(ref: string): string {
            const r = root.ship.computer.watchCancel(ref);
            return r.startsWith("ok") ? _ok("watch cancel") + r.slice(2) : _no(r.replace(/^error: /, ""));
        }

        // same launch as Crew.qml: GTMUX stripped, gtmux refuses a nested attach
        function openTeam(name: string): string {
            if (!nameRe.test(name)) return _no("bad session name");
            root.ship.run(["wezterm", "start", "--", "env", "-u", "GTMUX", "gtmux", "attach", name]);
            root.ship.crewSoon();
            return _ok("attach " + name);
        }
        // mcp.py has already matched the id against installed .desktop files; no arguments, no free command
        function launchApp(id: string): string {
            if (!/^[A-Za-z0-9_.][A-Za-z0-9_.@+ -]*\.desktop$/.test(id)) return _no("bad desktop id");
            root.ship.run(["gtk-launch", id]);
            return _ok("launch " + id);
        }
    }
}
