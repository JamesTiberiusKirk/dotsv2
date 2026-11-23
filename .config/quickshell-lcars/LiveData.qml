import Quickshell
import Quickshell.Networking
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../common"
import "Cmds.js" as Cmds
import "."

// Real data for LCARS inside the real shell. Reads and writes go through the
// normal shell's singletons, so LCARS does exactly what the normal popouts do.
// Only loadable through the quickshell/lcars symlink ("../common" = the shell's common/).
// Scope so it can own timers/processes; `active` false pauses the clock.
Scope {
    id: root
    property bool active: true            // LCARS alive: clock and battery keep running
    property bool consoleShown: true      // eDP-2 present and not released
    property bool attended: true          // touched in the last 90s
    property bool live: true
    // "present" for the follow-up reports = any keyboard or mouse input on the machine in the last 2 minutes (ext-idle-notify), only asked while a task is watched. Not the console's own 90 s `attended`.
    IdleMonitor { id: idleMon; enabled: root.computer.watches.length > 0; timeout: 120; respectInhibitors: false }
    readonly property ComputerBrain computer: ComputerBrain { usage: root.claude; present: !idleMon.isIdle }   // COMPUTER station chat; a running claude dies with this object
    property date now: new Date()
    Timer { interval: 30000; repeat: true; running: root.active; onTriggered: root.now = new Date() }
    readonly property var dev: Sys.batteryDevice
    readonly property real battery: dev ? (dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : -1
    readonly property string batteryNote: {
        if (!dev) return "";
        const ch = dev.state === UPowerDeviceState.Charging;
        const s = ch ? dev.timeToFull : dev.timeToEmpty;
        if (!ch && Sys.chargeLimitOn && (dev.state === UPowerDeviceState.PendingCharge || dev.state === UPowerDeviceState.FullyCharged))
            return "HELD AT " + Sys.chargeLimit + "%";
        if (!s) return ch ? "CHARGING" : "";
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60);
        return h + ":" + String(m).padStart(2, "0") + (ch ? " TO FULL" : " LEFT");
    }
    // red alert: first match wins. CORE TEMP only sees temps while HARDWARE is polled (no extra poller).
    readonly property string alert: battery >= 0 && battery < 10 && batteryState === "DISCHARGING" ? "RED ALERT: WARP CORE"
        : claude >= 0.9 ? "RED ALERT: DILITHIUM"
        : temps.some(t => t.c > 95) ? "RED ALERT: CORE TEMP" : "CONDITION GREEN"
    property bool alertAcked: false      // silences the red palette; resets when the alert changes
    onAlertChanged: alertAcked = false
    function ackAlert() { alertAcked = true; }
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id).map(w => ({
        id: w.id, name: String(w.name), monitor: w.monitor?.name ?? "", active: w.active, urgent: w.urgent }))
    readonly property real cpu: Sys.cpu
    readonly property real mem: Sys.memUsed
    readonly property real claude: Number.isFinite(Clanker.shown) ? Clanker.shown : -1
    readonly property string claudeName: Clanker.agent ? String(Clanker.agent.name || Clanker.agent.id) : ""
    readonly property string claudeNote: {
        Clanker.nowMs;
        const r = Clanker.limit ? Clanker.untilText(Clanker.limit.resetsAt) : "";
        return r !== "" ? "RESETS IN " + r.toUpperCase() : "";
    }
    readonly property int messages: Notifs.history.length      // in-memory only: proves shared singletons
    readonly property bool wifi: Networking.wifiEnabled
    readonly property bool bt: Bt.enabled
    readonly property bool dnd: Notifs.dnd
    readonly property bool night: Sys.nightLight
    readonly property bool tailscale: Sys.tsUp
    readonly property bool ultra: Sys.ultraSave
    readonly property var av: Audio.sink?.audio ?? null
    readonly property real volume: av ? av.volume : 0
    readonly property bool muted: av ? av.muted : false
    // The console lives on the bottom panel: use its row when brightness is not synced.
    readonly property var briRow: {
        const rows = Sys.brightnessRows;
        if (!rows.length) return null;
        return rows.find(r => r.name === "card1-eDP-2-backlight") ?? rows[0];
    }
    readonly property real brightness: briRow ? (Sys.brightnessPct[briRow.name] ?? briRow.pct) / 100 : 0
    readonly property string brightnessLabel: briRow ? String(briRow.label) : ""
    readonly property var player: Media.player
    readonly property bool hasMedia: Media.active
    readonly property string mediaTitle: player ? (player.trackTitle || player.identity || "") : ""
    readonly property string mediaArtist: player ? (player.trackArtist || "") : ""
    readonly property string mediaPlayer: player ? (player.identity || "") : ""
    readonly property bool playing: player ? player.isPlaying : false

    // ---- which station page is on screen ----
    // Stations write `view` ("systems.hardware", "comms.network", ...). Every poller and
    // every "panel open" flag of the shared singletons below runs only for the page shown,
    // and only while the console is shown and was touched recently (parked = no polling).
    property string view: ""
    readonly property bool _watch: consoleShown && attended
    readonly property bool _wHw: _watch && view === "systems.hardware"
    readonly property bool _wPower: _watch && view === "systems.power"
    readonly property bool _wStorage: _watch && view === "systems.storage"
    readonly property bool _wSystem: _watch && view === "systems.system"
    readonly property bool _wAudio: _watch && view === "comms.audio"
    readonly property bool _wBt: _watch && view === "comms.bluetooth"
    readonly property bool _wNet: _watch && view === "comms.network"
    readonly property bool _wSet: _watch && view.indexOf("settings.") === 0
    readonly property bool _wCrew: _watch && (view === "crew.away" || view === "bridge.status")
    // Sys.panelOpen stops the 2s backlight rebuild (a rebuild mid-drag kills the slider)
    // and runs the idle probe; same flag the display popout sets.
    readonly property bool _wPanel: _wHw || _wPower
    Binding { target: Sys; property: "lcarsPanel"; value: root._wPanel; when: root._wPanel }
    Binding { target: Sys; property: "lcarsPowerPanel"; value: root._wPower; when: root._wPower }   // top-cpu list + charge limit re-read
    Binding { target: Sys; property: "lcarsNetPanel"; value: root._wNet; when: root._wNet }         // wifi scan + ip probe
    Binding { target: Audio; property: "lcarsPanel"; value: root._wAudio; when: root._wAudio }      // pactl availability probe
    // docker stats counter: change it only on a real edge, so destroy cannot double-decrement
    property bool _statsHeld: false
    function _syncStats(want) {
        if (want === _statsHeld) return;
        _statsHeld = want;
        Sys.statsWanted += want ? 1 : -1;
    }
    on_WStorageChanged: _syncStats(_wStorage)
    // a pending keep-or-revert needs nothing here: its dead-man is a detached process (Cmds.js)
    Component.onDestruction: {
        _syncStats(false);
        // a Binding on a singleton does not restore on destroy
        Sys.lcarsPanel = false; Sys.lcarsPowerPanel = false; Sys.lcarsNetPanel = false; Audio.lcarsPanel = false;
    }

    // ---- SYSTEMS / HARDWARE ----
    readonly property string batteryState: !dev ? "" : dev.state === UPowerDeviceState.Charging ? "CHARGING"
        : dev.state === UPowerDeviceState.FullyCharged ? "FULL"
        : dev.state === UPowerDeviceState.PendingCharge ? "HELD" : "DISCHARGING"
    readonly property real batteryWatts: dev ? dev.changeRate : 0
    readonly property real batteryHealth: dev && dev.healthSupported ? dev.healthPercentage : -1
    readonly property string memText: Sys.memText
    readonly property string swapText: Sys.swapText
    property var temps: []
    property var fans: []
    readonly property var brightRows: Sys.brightnessRows.map(r => ({
        name: r.name, label: String(r.label).toUpperCase(), off: r.off,
        pct: Sys.brightnessPct[r.name] ?? r.pct }))
    function setBrightnessDev(name, v) { Sys.setBrightness(name, Math.max(1, Math.round(v * 100))); }

    // sensors -j, every 4s while HARDWARE is shown
    Process {
        id: sensProc
        command: ["sh", "-c", "sensors -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let j;
                try { j = JSON.parse(text); } catch (e) { return; }
                const t = [], f = [];
                for (const chip in j) {
                    const base = chip.split("-")[0];
                    if (/^(ucsi|BAT)/.test(base)) continue;
                    for (const lab in j[chip]) {
                        const o = j[chip][lab];
                        if (typeof o !== "object") continue;
                        let temp = null, max = 100, rpm = null;
                        for (const k in o) {
                            if (/^temp\d+_input$/.test(k)) temp = o[k];
                            else if (/^temp\d+_max$/.test(k) && o[k] > 0 && o[k] < 200) max = o[k];
                            else if (/^fan\d+_input$/.test(k)) rpm = o[k];
                        }
                        if (rpm !== null) { f.push({ name: lab.replace(/_/g, " ").toUpperCase(), rpm: Math.round(rpm) }); continue; }
                        if (temp === null) continue;
                        if (base === "coretemp" && lab !== "Package id 0") continue;
                        if (base === "nvme" && lab !== "Composite") continue;
                        const name = base === "coretemp" ? "CPU PACKAGE" : base === "nvme" ? "SSD"
                            : base === "iwlwifi_1" || base.indexOf("iwlwifi") === 0 ? "WIFI"
                            : (base + " " + lab).toUpperCase().replace(/_/g, " ");
                        t.push({ name: name, c: temp, max: max });
                    }
                }
                root.temps = t;
                root.fans = f;
            }
        }
    }
    // peripheral batteries: UPower devices that are not the laptop battery or mains
    readonly property var peripherals: (UPower.devices?.values ?? [])
        .filter(d => d.isPresent && !d.isLaptopBattery && d.type !== UPowerDeviceType.LinePower)
        .map(d => ({
            name: String(d.model).toUpperCase(),
            pct: Math.round(d.percentage > 1 ? d.percentage : d.percentage * 100),
            status: d.state === UPowerDeviceState.Charging ? "CHARGING" : d.state === UPowerDeviceState.Discharging ? "DISCHARGING"
                : d.state === UPowerDeviceState.FullyCharged ? "FULL" : "" }))
    Timer {
        interval: 4000; repeat: true; triggeredOnStart: true; running: root._wHw
        onTriggered: sensProc.running = true
    }

    // ---- SYSTEMS / POWER ----
    readonly property string profile: Sys.ultraSave ? "ultra"
        : PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver"
        : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property int chargeLimit: Sys.chargeLimit
    readonly property bool chargeLimitOn: Sys.chargeLimitOn
    readonly property string throttled: PowerProfiles.degradationReason === PerformanceDegradationReason.None ? ""
        : PowerProfiles.degradationReason === PerformanceDegradationReason.LapDetected ? "LAP DETECTED" : "HIGH TEMPERATURE"
    readonly property bool idleAwake: Sys.idleAwake
    readonly property var idleStages: [
        { key: "lock", name: "LOCK", on: Sys.idleLockOn, min: Sys.idleLock },
        { key: "screen", name: "SCREEN OFF", on: Sys.idleScreenOn, min: Sys.idleScreen },
        { key: "suspend", name: "SUSPEND", on: Sys.idleSuspendOn, min: Sys.idleSuspend }]
    readonly property var topProcs: Sys.topProcs
    // same mapping as bar/popouts/PowerPopout.qml
    function setProfile(p) {
        if (p === "ultra") { Sys.setUltraSave(true); return; }
        if (Sys.ultraSave) { Sys.setUltraSave(false, p); return; }
        PowerProfiles.profile = p === "power-saver" ? PowerProfile.PowerSaver
            : p === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
    }
    function setChargeLimit(on) { Sys.setChargeLimit(on); }
    function setIdleAwake(on) { Sys.setIdleAwake(on); }
    function setIdleStage(key, on) { Sys.setIdleStage(key, on); }

    // ---- SYSTEMS / STORAGE ----
    property var filesystems: []
    property var subvols: []
    property var btrfsRows: []
    property string btrfsFree: ""
    readonly property bool dockerUp: Sys.dockerUp
    readonly property var containers: Sys.dockerList.map(c => ({
        name: c.name, status: c.status, use: Sys.usageText(Sys.dockerStats[c.name]) }))
    Process {
        id: storeProc
        // btrfs usage runs rootless with a warning (chunk detail needs root, Overall + profile lines do not)
        command: ["sh", "-c",
            "df -h --output=source,fstype,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x efivarfs -x squashfs 2>/dev/null | tail -n +2;" +
            "echo ---; findmnt -rno TARGET,SOURCE -t btrfs 2>/dev/null; echo ---; btrfs filesystem usage / 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [a, b, c] = text.split(/^---$/m);
                const fs = {}, order = [];
                for (const l of (a || "").split("\n")) {
                    const f = l.trim().split(/\s+/);
                    if (f.length < 7) continue;
                    if (!fs[f[0]]) { fs[f[0]] = { source: f[0], fs: f[1], size: f[2], used: f[3], avail: f[4], pct: parseInt(f[5]) || 0, mounts: [] }; order.push(f[0]); }
                    fs[f[0]].mounts.push(f[6]);
                }
                root.filesystems = order.map(k => Object.assign({}, fs[k], { mounts: fs[k].mounts.join("  ") }));
                const sv = [];
                for (const l of (b || "").split("\n")) {
                    const m = l.trim().match(/^(\S+)\s+\S*\[\/?(.*)\]$/);
                    if (m) sv.push({ mount: m[1], sub: m[2] });
                }
                root.subvols = sv;
                const rows = [];
                for (const l of (c || "").split("\n")) {
                    const m = l.match(/^(Data|Metadata|System),\w+: Size:(\S+), Used:(\S+) \(([\d.]+)%\)/);
                    if (m) rows.push({ name: m[1].toUpperCase(), size: m[2].replace(/i?B$/, ""), used: m[3].replace(/i?B$/, ""), pct: Math.round(Number(m[4])) });
                    const fr = l.match(/^\s*Free \(estimated\):\s+(\S+)/);
                    if (fr) root.btrfsFree = fr[1].replace(/i?B$/, "");
                }
                root.btrfsRows = rows;
            }
        }
    }
    Timer { interval: 30000; repeat: true; triggeredOnStart: true; running: root._wStorage; onTriggered: storeProc.running = true }

    // ---- SYSTEMS / SYSTEM ----
    readonly property string hostname: Sys.hostname
    property string kernel: ""
    property string uptime: ""
    property int updates: -1
    property int dotChanges: 0
    property string dotBranch: ""
    property var services: []
    // updates: the count ~/.scripts/update-count.sh keeps in /tmp/i3status_updates (hourly, "n/a" without yay).
    // git: --no-optional-locks so a status read never touches the index. sv status needs root, so
    // services come from one ps: a `runsv <name>` with a child process is RUN, without one DOWN.
    Process {
        id: sysProc
        command: ["sh", "-c",
            "echo \"kernel $(uname -r)\"; echo \"uptime $(cut -d' ' -f1 /proc/uptime)\";" +
            "echo \"updates $(cat /tmp/i3status_updates 2>/dev/null || echo n/a)\";" +
            "echo \"dot $(git --no-optional-locks -C ~/.dots status --porcelain 2>/dev/null | wc -l)\";" +
            "echo \"branch $(git -C ~/.dots rev-parse --abbrev-ref HEAD 2>/dev/null)\";" +
            "echo ---; ls -1 /etc/runit/runsvdir/current 2>/dev/null; echo ---; ps -eo pid,ppid,args 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [head, names, procs] = text.split(/^---$/m);
                for (const l of (head || "").split("\n")) {
                    const i = l.indexOf(" "), k = l.slice(0, i), v = l.slice(i + 1).trim();
                    if (k === "kernel") root.kernel = v;
                    else if (k === "uptime") {
                        const s = Math.floor(Number(v)), d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                        root.uptime = (d > 0 ? d + "D " : "") + h + "H " + m + "M";
                    }
                    else if (k === "updates") root.updates = /^\d+$/.test(v) ? Number(v) : -1;
                    else if (k === "dot") root.dotChanges = Number(v) || 0;
                    else if (k === "branch") root.dotBranch = v;
                }
                const runsv = {}, kids = {};
                for (const l of (procs || "").split("\n")) {
                    const m = l.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/);
                    if (!m) continue;
                    kids[m[2]] = (kids[m[2]] || 0) + 1;
                    const r = m[3].match(/^runsv (\S+)$/);
                    if (r) runsv[r[1]] = m[1];
                }
                const sv = (names || "").split("\n").map(n => n.trim()).filter(n => n)
                    .map(n => ({ name: n, state: runsv[n] && kids[runsv[n]] ? "RUN" : "DOWN" }));
                root.services = sv;
            }
        }
    }
    Timer { interval: 30000; repeat: true; triggeredOnStart: true; running: root._wSystem; onTriggered: sysProc.running = true }
    // ---- SYSTEMS / JOBS (cron housekeeping, status files from /usr/local/bin/job) ----
    // One sh reads everything: per job `J name sched alive` plus its
    // status lines (`S k=v`) and last log lines (`L text`). Status dir is $JOBS_DIR (default /var/lib/jobs).
    // state: OK / FAILED (also a run that died) / RUNNING / NEVER. Next run: hourly = next HH:01,
    // weekly = own last start + 7 days ("~": anacron fires it when the laptop is awake), "~SOON" if never run.
    // alive = status says not ended AND /proc/<pid>/cmdline is the job wrapper (pids get reused after a reboot).
    // The status lines are read after that check, so a job that just finished shows as ended, not died.
    property var jobs: []
    function _jobAgo(s) {
        s = Math.max(0, s);
        return s < 60 ? "NOW" : s < 3600 ? Math.floor(s / 60) + "M AGO" : s < 86400 ? Math.floor(s / 3600) + "H AGO" : Math.floor(s / 86400) + "D AGO";
    }
    function _jobParse(text) {
        const nowD = new Date(), nowS = nowD.getTime() / 1000, out = [];
        let cur = null;
        for (const l of text.split("\n")) {
            if (l.indexOf("J ") === 0) {
                const [, name, sched, alive] = l.split(" ");
                cur = { name: name, sched: sched, alive: alive === "1", desc: "", kv: {}, log: [] };
                out.push(cur);
            }
            else if (cur && l.indexOf("D ") === 0) cur.desc = l.slice(2).trim();
            else if (cur && l.indexOf("S ") === 0) { const i = l.indexOf("="); if (i > 2) cur.kv[l.slice(2, i)] = l.slice(i + 1).trim(); }
            else if (cur && l.indexOf("L ") === 0) cur.log.push(l.slice(2));
        }
        const wd = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], mo = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        const nextH = new Date(nowD.getFullYear(), nowD.getMonth(), nowD.getDate(), nowD.getHours(), 1);
        if (nextH <= nowD) nextH.setHours(nextH.getHours() + 1);
        return out.map(j => {
            const k = j.kv, started = Number(k.started) || 0, ended = Number(k.ended) || 0;
            const state = !started ? "NEVER" : !k.ended ? (j.alive ? "RUNNING" : "FAILED") : k.exit === "0" ? "OK" : "FAILED";
            const last = !started ? "NEVER" : state === "RUNNING" ? "RUNNING" : ended ? _jobAgo(nowS - ended) : "DIED";
            const wk = new Date(started * 1000 + 7 * 86400000);
            const next = j.sched === "hourly" ? String(nextH.getHours()).padStart(2, "0") + ":01"
                : !started ? "~SOON" : "~" + wd[wk.getDay()] + " " + wk.getDate() + " " + mo[wk.getMonth()];
            return { name: j.name, sched: j.sched.toUpperCase(), sc: j.sched, state: state, last: last, next: next, desc: j.desc.toUpperCase(), log: j.log.join("\n") };
        });
    }
    Process {
        id: jobsProc
        command: ["sh", "-c",
            "D=\"${JOBS_DIR:-/var/lib/jobs}\";" +
            "for f in /etc/cron.hourly/job-* /etc/cron.weekly/job-*; do [ -e \"$f\" ] || continue;" +
            "n=${f##*/job-}; s=${f#/etc/cron.}; s=${s%%/*};" +
            "p=$(sed -n 's/^pid=//p' \"$D/$n.status\" 2>/dev/null); a=0; [ -n \"$p\" ] && grep -qa /usr/local/bin/job \"/proc/$p/cmdline\" 2>/dev/null && a=1;" +
            "echo \"J $n $s $a\"; printf 'D %s\\n' \"$(sed -n 's/^# desc: //p' \"$f\" | head -n 1)\"; sed 's/^/S /' \"$D/$n.status\" 2>/dev/null; tail -n 8 \"$D/$n.log\" 2>/dev/null | sed 's/^/L /'; done; true"]
        stdout: StdioCollector { onStreamFinished: root.jobs = root._jobParse(text) }
    }
    // 2 s while a job runs, else 30 s
    Timer {
        interval: root.jobs.some(j => j.state === "RUNNING") ? 2000 : 30000
        repeat: true; triggeredOnStart: true; running: root._wSystem
        onTriggered: if (!jobsProc.running) jobsProc.running = true
    }
    function openLazygit() { Quickshell.execDetached(["wezterm", "start", "--cwd", Quickshell.env("HOME") + "/.dots", "--", "lazygit"]); }

    // ---- COMMS / MESSAGES ----
    // Notifs.history is the real list (in memory + notifs.json); records are mapped to plain rows.
    // ago() is local: Notifs.ago only refreshes while the normal notification center is open.
    function _ago(ms) {
        const s = Math.max(0, Math.floor((now.getTime() - ms) / 1000));
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d";
    }
    // urgency: 0 low, 1 normal, 2 critical (NotificationUrgency values)
    readonly property var messageList: Notifs.history.slice().reverse().map(r => ({
        key: r.key, app: r.appName, summary: r.summary, body: r.body, ago: _ago(r.time), urgency: Number(r.urgency) }))
    function removeMessage(key) {
        const r = Notifs.history.find(x => x.key === key);
        if (r) Notifs.remove(r);
    }
    function clearMessages() { Notifs.dismissAll(); }

    // ---- COMMS / AUDIO ----
    function _row(n, cur) { return { id: n.id, name: Audio.devName(n).toUpperCase(), current: n === cur, muted: n.audio?.muted ?? false }; }
    readonly property var audioSinks: Audio.sinks.map(n => _row(n, Audio.sink))
    readonly property var audioSources: Audio.sources.map(n => _row(n, Audio.source))
    // volumes live in their own map so a slider drag does not rebuild the row lists
    readonly property var audioLevels: {
        const m = {};
        for (const n of Audio.sinks.concat(Audio.sources)) m[n.id] = n.audio?.volume ?? 0;
        return m;
    }
    function _node(id) { return Audio.sinks.concat(Audio.sources).find(n => n.id === id) ?? null; }
    function setDefaultNode(id) { Audio.setDefault(_node(id)); }
    function setNodeVolume(id, v) { const n = _node(id); if (n?.audio) n.audio.volume = v; }
    function toggleNodeMute(id) { const n = _node(id); if (n?.audio) n.audio.muted = !n.audio.muted; }

    // ---- COMMS / BLUETOOTH ----
    readonly property bool btPresent: Bt.present
    readonly property var btDevices: Bt.devices.map(d => ({
        key: d.address, name: String(d.name).toUpperCase(), icon: Bt.devIcon(d), connected: d.connected,
        busy: d.state === BluetoothDeviceState.Connecting || Bt.connecting === d || d.state === BluetoothDeviceState.Disconnecting,
        battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1, pods: Bt.isPods(d) }))
    readonly property var pods: ({
        present: Pods.up, up: Pods.connected, name: String(Pods.name).toUpperCase(), text: Pods.batteryText,
        noise: Pods.noiseMode, adaptive: Pods.supportsAdaptive, ca: Pods.ca, supportsCa: Pods.supportsCa })
    function btToggle(key) { Bt.toggle(Bt.devices.find(d => d.address === key)); }
    function podsCtl(verb) { Pods.ctl(verb); }

    // ---- COMMS / NETWORK ----
    readonly property string netText: Sys.netText
    readonly property bool netUp: Sys.netUp
    readonly property var wifiNets: Sys.wifiList.map(n => ({
        name: n.name, signal: n.signalStrength, secured: n.security !== WifiSecurityType.Open,
        known: n.known, connected: n.connected, busy: n.stateChanging }))
    // known or open networks only; a new secured one needs a key typed (normal shell popout)
    function wifiToggle(name) {
        const n = Sys.wifiList.find(x => x.name === name);
        if (!n) return;
        if (n.connected) n.disconnect();
        else if (n.known || n.security === WifiSecurityType.Open) n.connect();
    }
    readonly property bool tsPresent: Sys.tsPresent
    readonly property string tsNode: Sys.tsNode
    readonly property string tsIp: Sys.tsIp
    readonly property string tsExit: Sys.tsExit
    readonly property var tsPeers: Sys.tsPeerList
    function setTsExit(ip) { Sys.tsSetExit(ip); }

    // ---- privileged actions (pkexec through the LCARS polkit agent; authReady = agent registered) ----
    property bool authReady: false
    property string privTitle: ""
    property string privOut: ""
    readonly property bool privBusy: privProc.running
    Process {
        id: privProc
        stdout: StdioCollector { onStreamFinished: { root.privOut = text.trim().slice(-4000) || "(NO OUTPUT)"; if (!jobsProc.running) jobsProc.running = true; } }
    }
    // cmd: argv run as root, e.g. ["snapper", "list"]; stderr is merged into the output
    function priv(title, cmd) {
        if (privProc.running) return;
        privTitle = title; privOut = "";
        privProc.command = ["sh", "-c", "pkexec \"$@\" 2>&1", "sh"].concat(cmd);
        privProc.running = true;
    }
    function privClear() { privTitle = ""; privOut = ""; }
    function setWifi(on) { Networking.wifiEnabled = on; }
    function setBt(on) { Bt.setEnabled(on); }
    // ---- CREW ----
    // away teams: `gtmux ls` lines "name: N windows", every 10s while CREW/AWAY TEAMS or BRIDGE/STATUS shows.
    // Agent state per session: lcars-hook.sh (Claude Code hooks) writes $XDG_RUNTIME_DIR/lcars-agents/<session>.json
    // while LCARS is on; polled every 3s while the crew list shows. Older than 10 min = IDLE.
    property var _crewRaw: []
    property var _agentStates: ({})
    readonly property var crew: _crewRaw.map(c => ({ name: c.name, windows: c.windows, agent: _agentStates[c.name] ?? "" }))
    Process {
        id: agentProc
        command: ["sh", "-c", "cd \"$XDG_RUNTIME_DIR/lcars-agents\" 2>/dev/null || exit 0; for f in *.json; do [ -f \"$f\" ] && printf '%s\\t' \"${f%.json}\" && cat \"$f\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {}, now = Date.now() / 1000;
                for (const l of text.split("\n")) {
                    const i = l.indexOf("\t");
                    if (i < 0) continue;
                    let j;
                    try { j = JSON.parse(l.slice(i + 1)); } catch (e) { continue; }
                    out[l.slice(0, i)] = now - Number(j.t) > 600 ? "IDLE"
                        : j.state === "working" ? "WORKING" : j.state === "orders" ? "NEEDS ORDERS" : "IDLE";
                }
                root._agentStates = out;
            }
        }
    }
    Timer { interval: 3000; repeat: true; triggeredOnStart: true; running: root._wCrew; onTriggered: if (!agentProc.running) agentProc.running = true }
    Process {
        id: crewProc
        command: ["timeout", "3", "gtmux", "ls"]       // no sh -c: a hung server cannot wedge polling
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of text.split("\n")) {
                    const m = l.match(/^(.+): (\d+) windows?\b/);
                    if (m) out.push({ name: m[1], windows: Number(m[2]) });
                }
                out.sort((a, b) => a.name < b.name ? -1 : 1);
                root._crewRaw = out;
            }
        }
        onExited: code => root.crewOk = code === 0
    }
    property bool crewOk: true
    // project workspace names for NEW MISSION: top-level keys under `workspaces:` in the workspacer yaml (read once)
    property var projectWs: []
    Process {
        running: true
        command: ["awk", "/^workspaces:/{f=1;next} /^[^ #]/{f=0} f && /^    [A-Za-z0-9_.-]+:/{sub(/^ +/,\"\");sub(/:.*/,\"\");print}", Quickshell.env("HOME") + "/.config/workspacer/workspaces.yaml"]
        stdout: StdioCollector { onStreamFinished: root.projectWs = text.split("\n").filter(l => l !== "") }
    }
    // a launched terminal changes the session list: re-poll once, shortly after
    Timer { id: crewSoonT; interval: 1500; onTriggered: if (!crewProc.running) crewProc.running = true }
    function crewSoon() { crewSoonT.restart(); }
    Timer { interval: 10000; repeat: true; triggeredOnStart: true; running: root._wCrew; onTriggered: if (!crewProc.running) crewProc.running = true }
    // agents: the shell's Clanker records, trimmed; reset text recomputes on Clanker's minute tick
    readonly property string agentSel: Clanker.agent ? Clanker.agent.id : ""
    readonly property var agents: {
        Clanker.nowMs;
        return Clanker.agents.map(a => ({
            id: a.id, name: String(a.name || a.id), tier: String(a.tierLabel || ""), status: String(a.usageStatusText || ""),
            balance: a.balance ? { remaining: Number(a.balance.remaining) || 0, funded: Number(a.balance.funded) || 0, spent: Number(a.balance.spent) || 0,
                currency: String(a.balance.currency || ""), estimated: !!a.balance.estimated } : null,
            limits: (a.limits || []).map(l => ({ title: String(l.title || l.label || "LIMIT"), pct: Number(l.percent), reset: Clanker.untilText(l.resetsAt) })) }));
    }
    function selectAgent(id) { Clanker.select(id); }
    // ---- SETTINGS ----
    // Overrides: ~/.local/state/lcars/{overrides,olds,log.jsonl}; hypr/lcars.lua applies them (see Cmds.js).
    property var overrides: []             // [{ key, label, value, old }]  old = YOUR config value
    property var ovrLog: []                // newest first: { t, key, old, new, what }
    property var lookNow: ({})             // live getoption values, "general.gaps_in" -> "5"
    readonly property int overrideCount: overrides.length
    property var _st: ({ ovr: {}, olds: {} })
    // generation: bumped by every local write; a poll that started before it holds stale data and is dropped
    property int _gen: 0
    property int _stateGen: 0
    property int _optGen: 0
    Process {
        id: stateProc
        command: Cmds.stateRead()
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._stateGen !== root._gen) { reloadT.restart(); return; }
                const s = Cmds.parseState(text);
                root._st = { ovr: s.ovr, olds: s.olds };
                root.overrides = Object.keys(s.ovr).map(k => ({ key: k, label: Cmds.labelOf(k), value: s.ovr[k], old: s.olds[k] ?? "" }));
                root.ovrLog = s.log;
            }
        }
    }
    Process {
        id: optProc
        command: Cmds.optsRead()
        stdout: StdioCollector { onStreamFinished: { if (root._optGen !== root._gen) reloadT.restart(); else root.lookNow = Cmds.parseOpts(text); } }
    }
    property var touchMap: []
    Process {
        id: touchProc
        command: ["sh", "-c", "grep -h 'output *=' ~/.config/hypr/base.lua 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of text.split("\n")) {
                    const m = l.match(/name\s*=\s*"([^"]+)"\s*,\s*output\s*=\s*"([^"]+)"/);
                    if (m) out.push({ name: m[1], output: m[2] });
                }
                root.touchMap = out;
            }
        }
    }
    function _reload() {
        if (!stateProc.running) { _stateGen = _gen; stateProc.running = true; }
        if (!optProc.running) { _optGen = _gen; optProc.running = true; }
    }
    Timer { id: reloadT; interval: 1200; onTriggered: root._reload() }
    Timer { interval: 4000; repeat: true; triggeredOnStart: true; running: root._wSet; onTriggered: { root._reload(); if (!touchProc.running && !root.touchMap.length) touchProc.running = true; } }
    Component.onCompleted: { stateProc.running = true; pendProc.running = true }   // Bridge OVERRIDES count; banner survives an LCARS reload
    function _run(r) {
        if (!r) return;
        _gen++;
        const keys = new Set(Object.keys(_st.ovr).concat(Object.keys(r.ovr)));
        const now = Object.assign({}, lookNow);
        for (const k of keys) { const v = r.ovr[k] ?? _st.olds[k]; if (v !== undefined) now[k] = v; }
        lookNow = now;
        _st = { ovr: r.ovr, olds: r.olds };
        overrides = Object.keys(r.ovr).map(k => ({ key: k, label: Cmds.labelOf(k), value: r.ovr[k], old: r.olds[k] ?? "" }));
        Quickshell.execDetached(r.argv);
        reloadT.restart();
    }
    function _stNow() { return { ovr: _st.ovr, olds: _st.olds, now: lookNow }; }
    function setOverride(key, value) { _run(Cmds.ovrChange(_stNow(), "set", key, value, Date.now())); }
    function clearOverride(key) { _run(Cmds.ovrChange(_stNow(), "clear", key, "", Date.now())); }
    function clearAllOverrides() { _run(Cmds.ovrChange(_stNow(), "clearAll", "", "", Date.now())); }
    function undoLog(i) { if (ovrLog[i]) _run(Cmds.undoOp(_stNow(), ovrLog[i])); }
    function copyOverride(key) { const o = overrides.find(x => x.key === key); if (o) Quickshell.execDetached(["wl-copy", Cmds.copyLua(key, o.value)]); }
    readonly property var lookFlags: ({ glass: Sys.glassOn, transparency: Sys.transparencyOn, bar: Sys.barOn })
    function setLookFlag(flag, on) { Sys.setLook(flag, on); }
    readonly property var inputInfo: ({ kb: lookNow["input.kb_layout"] ?? "", rate: lookNow["input.repeat_rate"] ?? "", delay: lookNow["input.repeat_delay"] ?? "", touch: touchMap })

    // display: scale/refresh changes start a 15s keep-or-revert. The revert itself is a detached
    // dead-man process (Cmds.js, $D/pending), so it fires even if the shell or LCARS dies. This
    // timer only draws the countdown, derived from pending's timestamp, so a reloaded LCARS shows
    // the banner again while pending exists.
    property var monitorList: []
    property string confirmKind: ""        // "" | "scale" | "refresh"
    property int confirmLeft: 0
    property string confirmText: ""
    property double _pendStamp: 0
    Process {
        id: pendProc
        command: Cmds.pendingRead()
        stdout: StdioCollector {
            onStreamFinished: {
                const p = Cmds.parsePending(text);
                if (!p) { root.confirmKind = ""; return; }
                root.confirmKind = p.kind; root.confirmText = p.text; root._pendStamp = p.stamp; root._tick();
            }
        }
    }
    function _tick() {
        confirmLeft = Math.max(0, 15 - Math.floor((Date.now() - _pendStamp) / 1000));
        if (confirmLeft === 0) pendT.restart();           // dead-man fires about now: re-read to learn the outcome
    }
    Timer { id: pendT; interval: 2500; onTriggered: pendProc.running = true }
    Process {
        id: monProc
        command: Cmds.monRead()
        stdout: StdioCollector {
            onStreamFinished: {
                let l;
                try { l = JSON.parse(text.trim()); } catch (e) { return; }
                root.monitorList = l.map(m => Object.assign(m, { ext: m.name.indexOf("eDP") !== 0, rates: Cmds.rates(m) }));
            }
        }
    }
    Timer { interval: 4000; repeat: true; triggeredOnStart: true; running: root._wSet && root.view === "settings.display"; onTriggered: monProc.running = true }
    Timer { id: monT; interval: 1500; onTriggered: { monProc.running = true; pendProc.running = true; } }
    Timer { interval: 1000; repeat: true; running: root.confirmKind !== "" && root.confirmLeft > 0; onTriggered: root._tick() }
    function _begin(kind, text) { confirmKind = kind; confirmText = text; _pendStamp = Date.now(); confirmLeft = 15; monT.restart(); }
    function applyScale(name, s) {
        const m = monitorList.find(x => x.name === name);
        if (confirmKind !== "" || (m && Math.abs(m.scale - s) < 0.01)) return;
        Quickshell.execDetached(Cmds.scaleApply(name, s));
        _begin("scale", name + " SCALE " + s);
    }
    function applyRefresh(name, hz) {
        const m = monitorList.find(x => x.name === name);
        if (confirmKind !== "" || !m || m.mirror || m.off || ultra || m.hz === hz) return;
        Quickshell.execDetached(Cmds.refreshApply(m, hz));
        _begin("refresh", name + " " + hz + " HZ");
    }
    function keepDisplay() {
        Quickshell.execDetached(Cmds.keepCmd(confirmKind === "refresh"));
        confirmKind = ""; monT.restart();
    }
    function revertDisplay() {
        Quickshell.execDetached(Cmds.displayRevert());
        confirmKind = ""; monT.restart();
    }
    function saveArrangement() { Quickshell.execDetached(Cmds.saveCmd()); }

    function setDnd(on) { Notifs.dnd = on; }
    function setNight(on) { Sys.setNightLight(on); }
    function setTailscale(on) { Sys.tsSetUp(on); }
    function setUltra(on) {
        if (on) { Sys.setUltraSave(true); return; }
        // same mapping as bar/popouts/PowerPopout.qml: restore the current profile
        Sys.setUltraSave(false, PowerProfiles.profile === PowerProfile.PowerSaver ? "power-saver"
            : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced");
    }
    function setVolume(v) { if (av) av.volume = v; }
    function setMute(on) { if (av) av.muted = on; }
    function setBrightness(v) { if (briRow) Sys.setBrightness(briRow.name, Math.max(1, Math.round(v * 100))); }
    function playPause() { player?.togglePlaying(); }
    function next() { player?.next(); }
    function prev() { player?.previous(); }
    function run(cmd) { Quickshell.execDetached(cmd); }
    // per-workspace layout picks, same file the normal bar reads
    FileView {
        id: layoutFile
        path: `${Quickshell.env("HOME")}/.config/hypr/.layout`
        watchChanges: true
        onFileChanged: reload()
    }
    // Desk readout for one monitor; reactive because it only reads Hyprland models and layoutFile.
    function desk(mon) {
        const m = Hyprland.monitors.values.find(x => x.name === mon);
        const id = m?.activeWorkspace?.id ?? 0;
        let def = "dwindle", cur = "";
        for (const line of layoutFile.text().split("\n")) {
            const [k, v] = line.split("=");
            if (k === "*") def = v; else if (k == id) cur = v;
        }
        const o = m?.lastIpcObject ?? {};
        const sc = m?.scale ?? 1;
        return { id: id, name: String(m?.activeWorkspace?.name ?? ""),
            layout: (cur || def || "").replace("lua:", ""),
            count: Hyprland.toplevels.values.filter(t => t.workspace?.id === id).length,
            titles: Hyprland.toplevels.values.filter(t => t.workspace?.id === id).map(t => t.title),
            res: m ? Math.round(m.width / sc) + " X " + Math.round(m.height / sc) : "",
            scale: sc.toFixed(2),
            refresh: o.refreshRate ? Math.round(o.refreshRate) + " HZ" : "",
            others: workspaces.filter(w => w.monitor === mon && w.id !== id).map(w => ({ id: w.id, urgent: w.urgent })) };
    }
    function dispatch(d) { Hyprland.dispatch(d); }
}
