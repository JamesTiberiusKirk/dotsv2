import Quickshell
import QtQuick
import "Cmds.js" as Cmds
import "."

// Mock data for the dev copy (dev.qml). Same fields and functions as
// LiveData.qml; actions only log and flip local state, nothing touches the system.
// `active` false pauses the clock (hidden console polls nothing).
Scope {
    id: fd
    property bool active: true
    property bool live: false
    readonly property ComputerBrain computer: ComputerBrain { usage: fd.claude; demo: Quickshell.env("LCARS_COMPUTER_LIVE") !== "1" }   // COMPUTER station chat, lives as long as LCARS
    property bool consoleShown: true
    property bool attended: true
    property date now: new Date()
    property string alert: "CONDITION GREEN"
    property bool alertAcked: false
    function ackAlert() { alertAcked = true; log("acknowledge alert"); }
    property var workspaces: [
        { id: 1, name: "1", monitor: "eDP-1", active: false, urgent: false }, { id: 2, name: "2", monitor: "eDP-1", active: true, urgent: false },
        { id: 3, name: "3", monitor: "eDP-1", active: false, urgent: false }, { id: 4, name: "4", monitor: "eDP-1", active: false, urgent: true },
        { id: 7, name: "7", monitor: "DP-3", active: true, urgent: false }]
    property real battery: 63
    property string batteryNote: "2:41 LEFT"
    property real cpu: 0.18
    property real mem: 0.68
    property real claude: 0.41
    property string claudeName: "CLAUDE"
    property string claudeNote: "RESETS IN 2H 13M"
    property int messages: 5
    property bool wifi: true
    property bool bt: true
    property bool dnd: false
    property bool night: false
    property bool tailscale: true
    property bool ultra: false
    property real volume: 0.54
    property bool muted: false
    property real brightness: 0.7
    property string brightnessLabel: "BOTTOM PANEL"
    property bool hasMedia: true
    property string mediaTitle: "TRACK NAME"
    property string mediaArtist: "ARTIST"
    property string mediaPlayer: "BRAVE"
    property bool playing: true

    // ---- which station page is on screen (stations set it; LiveData gates pollers on it) ----
    property string view: ""

    // ---- SYSTEMS / HARDWARE ----
    property string batteryState: "CHARGING"
    property real batteryWatts: 12.4
    property real batteryHealth: 91
    property string memText: "21G/31G"
    property string swapText: "0.5G/8.0G"
    property var temps: [
        { name: "CPU PACKAGE", c: 50, max: 105 }, { name: "SSD", c: 40, max: 84 },
        { name: "ACPI ZONE 1", c: 43, max: 100 }, { name: "ACPI ZONE 2", c: 51, max: 100 },
        { name: "WIFI", c: 56, max: 100 }]
    property var fans: [{ name: "CPU FAN", rpm: 2900 }, { name: "GPU FAN", rpm: 2900 }]
    property var peripherals: [
        { name: "TOUCHPAD T650", pct: -1, status: "UNKNOWN" },
        { name: "BT KEYBOARD", pct: 82, status: "DISCHARGING" }]
    property var brightRows: [
        { name: "card1-eDP-2-backlight", label: "BOTTOM", pct: 70, off: false },
        { name: "intel_backlight", label: "TOP", pct: 55, off: false },
        { name: "DP-3", label: "DP-3", pct: 40, off: false }]
    function setBrightnessDev(name, v) {
        brightRows = brightRows.map(r => r.name === name ? Object.assign({}, r, { pct: Math.round(v * 100) }) : r);
        log("brightness " + name + " " + Math.round(v * 100));
    }

    // ---- SYSTEMS / POWER ----
    property string profile: "balanced"        // ultra | power-saver | balanced | performance
    property bool hasPerformance: true
    property int chargeLimit: 80               // applied ceiling; -1 = no such node, 100 = off
    property bool chargeLimitOn: true
    property string throttled: ""
    property bool idleAwake: false
    property var idleStages: [
        { key: "lock", name: "LOCK", on: true, min: 5 }, { key: "screen", name: "SCREEN OFF", on: true, min: 10 },
        { key: "suspend", name: "SUSPEND", on: false, min: 30 }]
    property var topProcs: [{ name: "claude", pct: 12.4 }, { name: "qs", pct: 6.1 }, { name: "Hyprland", pct: 3.2 }, { name: "wezterm-gui", pct: 1.9 }]
    function setProfile(p) { profile = p; ultra = p === "ultra"; log("power profile " + p); }
    function setChargeLimit(on) { chargeLimitOn = on; chargeLimit = on ? 80 : 100; log("charge limit " + on); }
    function setIdleAwake(on) { idleAwake = on; log("keep awake " + on); }
    function setIdleStage(key, on) {
        idleStages = idleStages.map(s => s.key === key ? Object.assign({}, s, { on: on }) : s);
        log("idle stage " + key + " " + on);
    }

    // ---- SYSTEMS / STORAGE ----
    property var filesystems: [
        { source: "/dev/nvme0n1p2", fs: "btrfs", size: "1.9T", used: "635G", avail: "1.3T", pct: 34, mounts: "/  /home  /var/log  /.snapshots  /swap" },
        { source: "/dev/nvme0n1p1", fs: "vfat", size: "1022M", used: "53M", avail: "970M", pct: 6, mounts: "/boot" }]
    property var subvols: [
        { mount: "/", sub: "@" }, { mount: "/home", sub: "@home" }, { mount: "/var/log", sub: "@log" },
        { mount: "/.snapshots", sub: "@snapshots" }, { mount: "/swap", sub: "@swap" }, { mount: "/var/lib/docker", sub: "@/var/lib/docker" }]
    property var btrfsRows: [
        { name: "DATA", used: "599G", size: "637G", pct: 94 },
        { name: "METADATA", used: "17.2G", size: "19G", pct: 90 },
        { name: "SYSTEM", used: "96K", size: "8M", pct: 1 }]
    property string btrfsFree: "1.24T"
    property bool dockerUp: true
    property var containers: [
        { name: "postgres", status: "Up 3 hours", use: "2%  \u00b7  120M" },
        { name: "redis", status: "Up 3 hours", use: "0%  \u00b7  12M" }]

    // ---- SYSTEMS / SYSTEM ----
    property string hostname: "binstar"
    property string kernel: "7.2.11-artix1-1"
    property string uptime: "2D 4H 12M"
    property int updates: 14                   // -1 = unknown
    property int dotChanges: 13
    property string dotBranch: "master"
    property var services: [
        { name: "agetty-tty1", state: "RUN" }, { name: "agetty-tty2", state: "RUN" }, { name: "bluetoothd", state: "RUN" },
        { name: "docker", state: "RUN" }, { name: "elogind", state: "DOWN" }, { name: "tailscale", state: "RUN" }]
    function openLazygit() { log("wezterm lazygit in ~/.dots"); }

    // ---- COMMS / MESSAGES ----
    property var messageList: [
        { key: "1", app: "wezterm", summary: "Claude finished", body: "Build passed, 3 files changed in the lcars folder.", ago: "2m", urgency: 1 },
        { key: "2", app: "Signal", summary: "Mum", body: "Are you coming Sunday?", ago: "14m", urgency: 1 },
        { key: "3", app: "System", summary: "Battery low", body: "Plug in the charger.", ago: "1h", urgency: 2 },
        { key: "4", app: "brave", summary: "Download complete", body: "firmware.zip", ago: "1h", urgency: 0 },
        { key: "5", app: "Calendar", summary: "Standup in 10 minutes", body: "", ago: "3h", urgency: 1 },
        { key: "6", app: "Signal", summary: "Alex", body: "pushed the fix", ago: "5h", urgency: 1 },
        { key: "7", app: "System", summary: "Updates available", body: "14 packages", ago: "1d", urgency: 0 },
        { key: "8", app: "wezterm", summary: "Agent waiting", body: "Needs your approval to continue", ago: "1d", urgency: 2 }]
    function removeMessage(key) { messageList = messageList.filter(m => m.key !== key); messages = messageList.length; log("remove message " + key); }
    function clearMessages() { messageList = []; messages = 0; log("clear all messages"); }

    // ---- COMMS / AUDIO ----
    property var audioSinks: [
        { id: 1, name: "SPEAKERS", current: true, muted: false },
        { id: 2, name: "AIRPODS PRO", current: false, muted: false },
        { id: 3, name: "HDMI / DISPLAYPORT 1", current: false, muted: true },
        { id: 4, name: "HDMI / DISPLAYPORT 2", current: false, muted: false }]
    property var audioSources: [
        { id: 11, name: "INTERNAL MIC", current: true, muted: false },
        { id: 12, name: "AIRPODS PRO MIC", current: false, muted: false }]
    property var audioLevels: ({ "1": 0.54, "2": 0.8, "3": 1.0, "4": 0.3, "11": 0.65, "12": 0.5 })
    function setDefaultNode(id) {
        audioSinks = audioSinks.map(n => Object.assign({}, n, { current: n.id === id ? true : (audioSinks.some(x => x.id === id) ? false : n.current) }));
        audioSources = audioSources.map(n => Object.assign({}, n, { current: n.id === id ? true : (audioSources.some(x => x.id === id) ? false : n.current) }));
        log("default audio node " + id);
    }
    function setNodeVolume(id, v) { const m = Object.assign({}, audioLevels); m[id] = v; audioLevels = m; }
    function toggleNodeMute(id) {
        audioSinks = audioSinks.map(n => n.id === id ? Object.assign({}, n, { muted: !n.muted }) : n);
        audioSources = audioSources.map(n => n.id === id ? Object.assign({}, n, { muted: !n.muted }) : n);
        log("toggle mute " + id);
    }

    // ---- COMMS / BLUETOOTH ----
    property bool btPresent: true
    property var btDevices: [
        { key: "AA:01", name: "AIRPODS PRO", icon: "airpods", connected: true, busy: false, battery: -1, pods: true },
        { key: "AA:02", name: "ZENBOOK DUO KEYBOARD", icon: "keyboard", connected: true, busy: false, battery: 82, pods: false },
        { key: "AA:03", name: "MX MASTER 3", icon: "mouse", connected: false, busy: false, battery: -1, pods: false },
        { key: "AA:04", name: "SONY WH-1000XM4", icon: "headphones", connected: false, busy: false, battery: -1, pods: false },
        { key: "AA:05", name: "PIXEL 8", icon: "cellphone", connected: false, busy: false, battery: -1, pods: false },
        { key: "AA:06", name: "JBL FLIP", icon: "speaker", connected: false, busy: false, battery: -1, pods: false },
        { key: "AA:07", name: "KINDLE", icon: "bluetooth", connected: false, busy: false, battery: -1, pods: false }]
    property var pods: ({ present: true, up: true, name: "AIRPODS PRO", text: "L 80  R 75+  C 60", noise: 1, adaptive: true, ca: false, supportsCa: true })
    function btToggle(key) {
        btDevices = btDevices.map(d => d.key === key ? Object.assign({}, d, { connected: !d.connected }) : d);
        log("bluetooth toggle " + key);
    }
    function podsCtl(verb) {
        if (verb.indexOf("noise:") === 0) pods = Object.assign({}, pods, { noise: { anc: 1, transparency: 2, adaptive: 3 }[verb.slice(6)] });
        log("pods " + verb);
    }

    // ---- COMMS / NETWORK ----
    property string netText: "W: HOMELAB-5G 192.168.1.42"
    property bool netUp: true
    property var wifiNets: [
        { name: "HOMELAB-5G", signal: 0.92, secured: true, known: true, connected: true, busy: false },
        { name: "HOMELAB-2G", signal: 0.7, secured: true, known: true, connected: false, busy: false },
        { name: "Neighbour_WiFi", signal: 0.55, secured: true, known: false, connected: false, busy: false },
        { name: "BT-HUB6-XK2", signal: 0.5, secured: true, known: false, connected: false, busy: false },
        { name: "CoffeeShop Guest", signal: 0.45, secured: false, known: false, connected: false, busy: false },
        { name: "VM-Hotspot", signal: 0.3, secured: true, known: true, connected: false, busy: false },
        { name: "EE-WRXY7K", signal: 0.22, secured: true, known: false, connected: false, busy: false },
        { name: "Sky_ABC123", signal: 0.15, secured: true, known: false, connected: false, busy: false }]
    function wifiToggle(name) {
        wifiNets = wifiNets.map(n => Object.assign({}, n, { connected: n.name === name ? !n.connected : false }));
        log("wifi toggle " + name);
    }
    property bool tsPresent: true
    property string tsNode: "binstar"
    property string tsIp: "100.64.0.12"
    property string tsExit: ""
    property var tsPeers: [
        { n: "homelab", ip: "100.64.0.2", on: true, ex: true }, { n: "pixel-8", ip: "100.64.0.5", on: true, ex: false },
        { n: "nas", ip: "100.64.0.7", on: true, ex: false }, { n: "work-laptop", ip: "100.64.0.9", on: false, ex: false },
        { n: "vps-fra", ip: "100.64.0.20", on: true, ex: true }]
    function setTsExit(ip) { tsExit = ip; log("tailscale exit node " + ip); }

    Timer { interval: 30000; repeat: true; running: fd.active; onTriggered: fd.now = new Date() }

    // ---- CREW ----
    property var crew: ["ff-gtmux", "ws-homelab", "ff-sagr", "sf-sportfreelancers.com", "ws-serverconfig", "ws-vulpe.rsvp", "dots", "ff-stackr", "ff-fraedi"]
        .map((n, i) => ({ name: n, windows: n === "ff-stackr" ? 3 : n === "dots" ? 1 : 2,
            agent: n === "dots" || n === "ff-stackr" ? "WORKING" : n === "ws-homelab" ? "NEEDS ORDERS" : n === "ff-sagr" ? "IDLE" : "" }))
    property bool crewOk: true
    property var projectWs: ["notes", "ws", "at", "sf", "ff", "uww"]
    function crewSoon() { log("re-poll gtmux in 1.5s"); }
    property string agentSel: "claude"
    property var agents: [
        { id: "claude", name: "Claude", tier: "MAX 5X", status: "", balance: null, limits: [
            { title: "5-hour", pct: 0.41, reset: "2h 13m" }, { title: "Weekly (7-day)", pct: 0.93, reset: "1d 4h" },
            { title: "Fable Weekly", pct: 0.6, reset: "1d 4h" }] },
        { id: "codex", name: "Codex", tier: "PLUS", status: "", balance: { remaining: 12.4, funded: 20, spent: 7.6, currency: "USD", estimated: true }, limits: [
            { title: "5-hour", pct: 0.12, reset: "4h 2m" }, { title: "Weekly", pct: 0.35, reset: "3d 9h" }] }
    ]
    function selectAgent(id) { agentSel = id; log("select agent " + id); }

    // ---- SETTINGS ----
    // Mirrors LiveData; every action runs the SAME Cmds.js builders and logs the argv it would run.
    property var overrides: [
        { key: "general.gaps_in", label: "GAPS INNER", value: "12", old: "5" },
        { key: "animations.enabled", label: "ANIMATIONS", value: "false", old: "true" }]
    property var ovrLog: [
        { t: Date.now() - 120000, key: "animations.enabled", old: "true", new: "false", what: "SET" },
        { t: Date.now() - 600000, key: "general.gaps_in", old: "8", new: "12", what: "SET" },
        { t: Date.now() - 3600000, key: "general.gaps_in", old: "5", new: "8", what: "SET" }]
    property var lookNow: ({ "general.gaps_in": "12", "general.gaps_out": "5", "general.border_size": "2", "decoration.rounding": "12",
        "decoration.blur.enabled": "true", "decoration.shadow.enabled": "true", "animations.enabled": "false",
        "input.kb_layout": "us", "input.repeat_rate": "25", "input.repeat_delay": "300" })
    readonly property int overrideCount: overrides.length
    property var _olds: ({ "general.gaps_in": "5", "animations.enabled": "true" })
    function _run(r) {
        if (!r) return;
        const now = Object.assign({}, lookNow);
        const keys = new Set(overrides.map(o => o.key).concat(Object.keys(r.ovr)));
        for (const k of keys) { const v = r.ovr[k] ?? _olds[k]; if (v !== undefined) now[k] = v; }
        lookNow = now;
        _olds = r.olds;
        overrides = Object.keys(r.ovr).map(k => ({ key: k, label: Cmds.labelOf(k), value: r.ovr[k], old: r.olds[k] ?? "" }));
        for (const l of r.argv[6].split("\n")) if (l) ovrLog = [JSON.parse(l)].concat(ovrLog);
        log("overrides " + JSON.stringify(r.argv));
    }
    function _stNow() { const o = {}; for (const x of overrides) o[x.key] = x.value; return { ovr: o, olds: _olds, now: lookNow }; }
    function setOverride(key, value) { _run(Cmds.ovrChange(_stNow(), "set", key, value, Date.now())); }
    function clearOverride(key) { _run(Cmds.ovrChange(_stNow(), "clear", key, "", Date.now())); }
    function clearAllOverrides() { _run(Cmds.ovrChange(_stNow(), "clearAll", "", "", Date.now())); }
    function undoLog(i) { if (ovrLog[i]) _run(Cmds.undoOp(_stNow(), ovrLog[i])); }
    function copyOverride(key) { const o = overrides.find(x => x.key === key); if (o) log("wl-copy " + Cmds.copyLua(key, o.value)); }
    property var lookFlags: ({ glass: true, transparency: true, bar: true })
    function setLookFlag(flag, on) { const f = Object.assign({}, lookFlags); f[flag] = on; lookFlags = f; log("~/.scripts/glass " + flag + " " + (on ? "on" : "off")); }
    property var touchMap: []
    property var inputInfo: ({ kb: "us", rate: "25", delay: "300", touch: [
        { name: "elan9008:00-04f3:4447", output: "eDP-1" }, { name: "elan9009:00-04f3:4448", output: "eDP-2" },
        { name: "elan9008:00-04f3:4447-stylus", output: "eDP-1" }, { name: "elan9009:00-04f3:4448-stylus", output: "eDP-2" }] })

    property var monitorList: [
        { name: "eDP-1", desc: "Samsung Display Corp. 0x419D", off: false, mirror: false, ext: false, x: 0, y: 0, tf: 0, scale: 1.6, hz: 120, w: 2880, h: 1800, rates: [120, 60] },
        { name: "eDP-2", desc: "Samsung Display Corp. 0x419D", off: true, mirror: false, ext: false, x: 0, y: 1125, tf: 0, scale: 1.6, hz: 120, w: 2880, h: 1800, rates: [120, 60] },
        { name: "DP-3", desc: "MSI MPG 322URX", off: false, mirror: false, ext: true, x: 1800, y: 0, tf: 0, scale: 1.5, hz: 120, w: 3840, h: 2160, rates: [120, 60] }]
    property string confirmKind: ""
    property int confirmLeft: 0
    property string confirmText: ""
    // no timer here: the mock never reverts on its own, the countdown is static
    function applyScale(name, s) {
        const m = monitorList.find(x => x.name === name);
        if (confirmKind !== "" || (m && Math.abs(m.scale - s) < 0.01)) return;
        log("scale " + JSON.stringify(Cmds.scaleApply(name, s))); confirmKind = "scale"; confirmLeft = 15; confirmText = name + " SCALE " + s;
    }
    function applyRefresh(name, hz) {
        const m = monitorList.find(x => x.name === name);
        if (confirmKind !== "" || !m || ultra || m.hz === hz) return;
        log("refresh " + JSON.stringify(Cmds.refreshApply(m, hz)));
        confirmKind = "refresh"; confirmLeft = 15; confirmText = name + " " + hz + " HZ";
    }
    function keepDisplay() { log("keep " + JSON.stringify(Cmds.keepCmd(confirmKind === "refresh"))); confirmKind = ""; }
    function revertDisplay() { log("revert " + JSON.stringify(Cmds.displayRevert())); confirmKind = ""; }
    function saveArrangement() { log("save arrangement " + JSON.stringify(Cmds.saveCmd())); }

    function log(what) { console.log("LCARS (fake) would:", what); }
    // ---- privileged actions (live: pkexec via the polkit agent) ----
    property bool authReady: false
    property string privTitle: ""
    property string privOut: ""
    property bool privBusy: false
    function priv(title, cmd) { privTitle = title; privOut = "MOCK OUTPUT\n" + cmd.join(" "); log("pkexec " + cmd.join(" ")); }
    function privClear() { privTitle = ""; privOut = ""; }
    function setWifi(on) { wifi = on; log("wifi " + on); }
    function setBt(on) { bt = on; log("bluetooth " + on); }
    function setDnd(on) { dnd = on; log("dnd " + on); }
    function setNight(on) { night = on; log("night light " + on); }
    function setTailscale(on) { tailscale = on; log("tailscale " + on); }
    function setUltra(on) { ultra = on; log("ultra save " + on); }
    function setVolume(v) { volume = v; log("volume " + v); }
    function setMute(on) { muted = on; log("mute " + on); }
    function setBrightness(v) { brightness = v; log("brightness " + v); }
    function playPause() { playing = !playing; log("play/pause"); }
    function next() { log("next track"); }
    function prev() { log("previous track"); }
    function run(cmd) { log("run " + JSON.stringify(cmd)); }
    function desk(mon) {
        return { id: 2, name: "2", layout: "dwindle", count: 3,
            titles: ["WEZTERM: GTMUX", "FIREFOX: QUICKSHELL DOCS", "ZED: LCARS"],
            res: "1800 X 1125", scale: "1.60", refresh: "120 HZ",
            others: [{ id: 1, urgent: false }, { id: 3, urgent: false }, { id: 4, urgent: true }] };
    }
    function dispatch(d) { log("hyprland " + d); }
}
