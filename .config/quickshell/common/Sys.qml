pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Networking
import QtQuick

// System stats not covered by a quickshell service.
Singleton {
    id: root

    property real cpu: 0            // 0..1
    property string memText: ""
    property string swapText: ""
    property string diskFree: ""

    // cpu: /proc/stat delta over the poll interval
    property var prevStat: null
    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + f[4];
            const total = f.reduce((a, b) => a + b, 0);
            if (root.prevStat) {
                const dt = total - root.prevStat.total;
                if (dt > 0)
                    root.cpu = 1 - (idle - root.prevStat.idle) / dt;
            }
            root.prevStat = { idle: idle, total: total };
        }
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            const m = {};
            for (const line of text().split("\n")) {
                const p = line.split(/[:\s]+/);
                m[p[0]] = Number(p[1]);
            }
            const gb = kb => (kb / 1048576).toFixed(kb / 1048576 >= 10 ? 0 : 1) + "G";
            root.memText = gb(m.MemTotal - m.MemAvailable) + "/" + gb(m.MemTotal);
            root.swapText = m.SwapTotal > 0
                ? gb(m.SwapTotal - m.SwapFree) + "/" + gb(m.SwapTotal) : "";
        }
    }
    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { statFile.reload(); memFile.reload(); }
    }

    // Primary-panel brightness as 0..1 (-1 = no backlight at all). Derived from
    // the enumeration below rather than polled separately — the bar Cell and the
    // OSD have always read this one number and still do.
    readonly property real backlight: backlights.length > 0 ? backlights[0].pct / 100 : -1
    function refreshBacklight() { refreshDisplays(); }

    // ---- displays ----
    // Host identity. /etc/hostname, not `hostnamectl` — that ships with
    // systemd and these are runit boxes. Read once: it cannot change.
    property string hostname: ""
    FileView {
        path: "/etc/hostname"
        onLoaded: root.hostname = text().trim()
    }
    // binstar is the Zenbook Duo: two panels, a sub-screen to toggle and an
    // accelerometer. Everywhere else those controls have nothing to drive.
    readonly property bool isDuo: hostname === "binstar"

    // Backlights, as [{ name, label, pct }]. Filtered to nodes backed by a DRM
    // connector: the bare glob also picks up asus_screenpad, which is stuck at
    // 0/255 forever and is not the Duo's second panel. Falls back to every
    // backlight if the filter finds none, so a host whose panel sits outside
    // /drm still gets a slider.
    property var backlights: []
    Process {
        id: blProbe
        command: ["sh", "-c",
            "list() { for d in /sys/class/backlight/*; do [ -r \"$d/brightness\" ] || continue;" +
            "[ -n \"$1\" ] && { readlink -f \"$d\" | grep -q '/drm/card' || continue; };" +
            "echo \"$(basename $d) $(cat $d/brightness) $(cat $d/max_brightness)\"; done; };" +
            "out=$(list drm); [ -n \"$out\" ] || out=$(list); echo \"$out\";" +
            "echo \"sync $(cat ${XDG_STATE_HOME:-$HOME/.local/state}/duo/brightness-sync 2>/dev/null || echo on)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const devs = [];
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f.length < 2) continue;
                    if (f[0] === "sync") { root.brightnessSync = f[1] !== "off"; continue; }
                    if (f.length < 3) continue;
                    const maxB = Number(f[2]);
                    if (!(maxB > 0)) continue;
                    devs.push({ name: f[0], pct: Math.round(Number(f[1]) * 100 / maxB) });
                }
                // primary panel first: the glob is alphabetical, which on the
                // Duo puts card1-eDP-2 ahead of intel_backlight, and backlight
                // (above) reads element 0 as "the" screen brightness
                devs.sort((a, b) => root.blRank(a.name) - root.blRank(b.name));
                for (let i = 0; i < devs.length; i++)
                    devs[i].label = root.blLabel(devs[i].name, i);
                root.backlights = devs;
            }
        }
    }
    function blRank(name) {
        return name === "intel_backlight" || name === "amdgpu_bl0" || name === "acpi_video0" ? 0 : 1;
    }
    // The Duo's panels are physically stacked and duo(1) already addresses them
    // as top/bottom, so the connector name would be a second vocabulary for the
    // same two things. Elsewhere: the connector name, or a positional fallback.
    function blLabel(name, i) {
        if (root.isDuo) return i === 0 ? "top" : "bottom";
        const m = name.match(/^card\d+-(.+)-backlight$/);
        if (m) return m[1];
        if (name === "intel_backlight" || name === "amdgpu_bl0") return "eDP-1";
        return i === 0 ? "screen" : "screen " + (i + 1);
    }
    // panels locked together (duo owns the flag; the brightness keys honour it)
    property bool brightnessSync: true
    // What the panel renders. Locked, the panels hold one value between them, so
    // two sliders would be two views of the same number — drag either and the
    // other reads stale until the next poll. Show one.
    // off: the panel exists and its backlight is still writable, but the output
    // is disabled — turning it up would light nothing, so the row greys out.
    readonly property var brightnessRows: (brightnessSync && backlights.length > 1)
        ? [{ name: backlights[0].name, label: "brightness", pct: backlights[0].pct, off: false }]
        : backlights.map(d => ({
            name: d.name, label: d.label, pct: d.pct,
            off: root.isDuo && !root.subScreen && d.name === "card1-eDP-2-backlight"
        }))
    function refreshDisplays() { blProbe.running = true; }

    // Writes go through duo on the Duo so the sync flag and the OSD stay
    // coherent with the hardware keys; elsewhere brightnessctl (common.txt)
    // is already installed and does the one thing needed.
    function setBrightness(dev, pct) {
        if (isDuo)
            Quickshell.execDetached(["sh", "-c", "~/go/bin/duo brightness set " + pct
                + " " + (dev === "card1-eDP-2-backlight" ? "bottom" : "top")]);
        else
            Quickshell.execDetached(["brightnessctl", "-d", dev, "set", pct + "%"]);
    }
    function setBrightnessSync(on) {
        brightnessSync = on;
        Quickshell.execDetached(["sh", "-c", "~/go/bin/duo brightness sync " + (on ? "on" : "off")]);
    }

    // sub-screen (eDP-2) and accelerometer follow — Duo only, duo(1) owns both.
    // "monitors all": a mirrored output is absent from the plain monitors list
    // even though it is enabled, which reported the sub screen as off.
    property bool subScreen: true
    property bool autoRotate: false
    Process {
        id: duoStateProbe
        running: false
        command: ["sh", "-c",
            "hyprctl -j monitors all 2>/dev/null | jq -e '.[]|select(.name==\"eDP-2\" and .disabled==false)' >/dev/null && echo 'screen on' || echo 'screen off';" +
            "echo \"rotate $(~/go/bin/duo autorotate status 2>/dev/null || echo off)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f[0] === "screen") root.subScreen = f[1] === "on";
                    else if (f[0] === "rotate") root.autoRotate = f[1] === "on";
                }
            }
        }
    }
    function setSubScreen(on) {
        subScreen = on;
        Quickshell.execDetached(["sh", "-c", "~/go/bin/duo screen " + (on ? "on" : "off")]);
    }
    function setAutoRotate(on) {
        autoRotate = on;
        Quickshell.execDetached(["sh", "-c", "~/go/bin/duo autorotate " + (on ? "on" : "off")]);
    }

    // Polling stops while the panel is open. backlights is a plain array
    // reassigned wholesale, which resets the Repeater and destroys every slider
    // delegate — mid-drag that deletes the MouseArea out from under the gesture.
    // Nothing is lost by holding still: while the panel is open the user is the
    // one writing brightness, and the duo state probe forks hyprctl+jq that
    // nothing reads when it is closed.
    property bool panelOpen: false
    onPanelOpenChanged: if (panelOpen) poll();

    // Asks the bar to toggle a popout by name (calendar, system, display,
    // power, network, audio, bluetooth, tailscale). The bar is one panel per
    // screen, so this cannot reach a popout directly — every panel hears it
    // and only the one on the focused monitor answers. The menu uses it.
    signal togglePanel(string name)
    // Close every popout and the drawer, on every screen. Bound to Esc via the
    // `popout` submap below; the bar panels listen.
    signal closeAll()

    // How many bar panels currently have a popout up (one per screen), plus
    // the drawer. While anything is open Hyprland sits in the `popout` submap,
    // whose only binding is Esc → closeAll — the popouts take no keyboard
    // focus themselves (that broke pointer focus on the bell), so Esc has to
    // be caught at the compositor. Everything else passes through a submap.
    property int barPopoutsOpen: 0
    readonly property bool anythingOpen: barPopoutsOpen > 0 || Notifs.centerOpen
    onAnythingOpenChanged: Hyprland.dispatch(anythingOpen ? 'hl.dsp.submap("popout")' : 'hl.dsp.submap("reset")')
    function poll() {
        blProbe.running = true;
        if (root.isDuo) duoStateProbe.running = true;
    }
    Timer {
        interval: 2000; running: !root.panelOpen; repeat: true; triggeredOnStart: true
        onTriggered: blProbe.running = true
    }
    // The duo state is the other way round: it only feeds the panel's toggles,
    // so it is pure waste (a hyprctl + jq fork every 2s) while closed, and has
    // to stay live while open or the sub-screen switch keeps showing whatever it
    // read when the panel was opened.
    Timer {
        interval: 2000; running: root.isDuo && root.panelOpen; repeat: true
        onTriggered: duoStateProbe.running = true
    }

    // Zenbook Duo keyboard backlight. The firmware exposes no readable node, so
    // the level is whatever duo(1) last set (it pushes via the osd ipc handler);
    // duoKbd just tracks whether the keyboard is docked at all.
    property int kbdBacklight: 0
    property bool duoKbd: false
    // "<docked> <level> <bottom-screen>" — level comes from duo's runtime file so
    // a quickshell restart picks the real value back up instead of guessing 0.
    // The screen state rides along here rather than in duoStateProbe: the bar
    // shows it all the time, and this fork already happens every 5s, so it is
    // free. duoStateProbe stays lazy for the things only the panel reads.
    Process {
        id: duoKbdProbe
        command: ["sh", "-c",
            "grep -lx 1bf2 /sys/bus/usb/devices/*/idProduct >/dev/null 2>&1 && p=1 || p=0;" +
            "echo \"$p $(cat ${XDG_RUNTIME_DIR:-/tmp}/duo-kbd-backlight 2>/dev/null || echo 0)" +
            " $(~/go/bin/duo screen status 2>/dev/null || echo -)\""]
        stdout: SplitParser {
            onRead: data => {
                const f = data.trim().split(/\s+/);
                root.duoKbd = f[0] === "1";
                root.kbdBacklight = Number(f[1]) || 0;
                // "-" on a host with no duo binary: leave subScreen alone rather
                // than reporting a panel that does not exist as switched off
                if (f[2] === "on" || f[2] === "off") root.subScreen = f[2] === "on";
            }
        }
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: duoKbdProbe.running = true
    }

    // ---- power panel ----
    // Profiles themselves need nothing here: Quickshell.Services.UPower exposes
    // PowerProfiles.profile as a writable property, so the panel binds straight
    // to the daemon. The rest of the panel is what has no binding.
    //
    // Its own flag, not panelOpen: that one also gates the Duo state probe, so
    // sharing it would fork hyprctl+jq every 2s for a panel that shows neither.
    property bool powerPanelOpen: false

    // Charging ceiling, as a percentage. -1 when the machine has no such node
    // (desktops, and laptops whose firmware does not expose one), 100 when
    // nothing is capping. This is the applied value, not the configured one:
    // UPower holds 80 ready whether or not the limit is switched on, and only
    // sysfs says which is true right now.
    property int chargeLimit: -1
    readonly property bool chargeLimitOn: chargeLimit > 0 && chargeLimit < 100
    // The internal battery's kernel name ("BAT0", "BAT1", "CMB0"...). Not
    // displayDevice.nativePath — that is UPower's synthetic aggregate and
    // reports "". isLaptopBattery drops the mouse and keyboard cells, which
    // are also batteries as far as UPower is concerned.
    // The real battery object, not UPower.displayDevice. displayDevice is a
    // synthetic aggregate: it carries percentage and time-to-empty fine, but
    // reports Capacity 0 and NativePath "" — so battery health and the kernel
    // name both have to come from the device itself.
    readonly property var batteryDevice: {
        const devs = UPower.devices?.values ?? [];
        for (const d of devs)
            if (d.isLaptopBattery && d.nativePath) return d;
        return null;
    }
    readonly property string batteryName: batteryDevice?.nativePath ?? ""
    FileView {
        id: chargeLimitFile
        path: root.batteryName
            ? "/sys/class/power_supply/" + root.batteryName + "/charge_control_end_threshold"
            : ""
        onLoaded: root.chargeLimit = Number(text().trim())
        onLoadFailed: root.chargeLimit = -1
    }
    // UPower 1.91 owns the write (it runs as root, and re-applies across
    // reboots and resume), so this needs no udev rule and no sudo — the
    // enable-charging-limit polkit action is allow_active. The 80% ceiling is
    // compiled into upowerd: ChargeEndThreshold is not a writable property, so
    // this is on/off and not a slider.
    function setChargeLimit(on) {
        if (!batteryName) return;
        Quickshell.execDetached(["busctl", "call", "org.freedesktop.UPower",
            "/org/freedesktop/UPower/devices/battery_" + batteryName,
            "org.freedesktop.UPower.Device", "EnableChargeThreshold",
            "b", on ? "true" : "false"]);
        chargeLimitSettle.restart();
    }
    // sysfs lands a beat after the call returns, and it is a kernel attribute
    // that never fires an inotify event — so re-read on a delay rather than
    // watching the file.
    Timer { id: chargeLimitSettle; interval: 400; onTriggered: chargeLimitFile.reload() }

    // Top CPU consumers, [{ name, pct }]. CPU time, not watts — nothing on Linux
    // attributes power per process without a powertop calibration run, and even
    // that is an estimate. Useful as "what is keeping the CPU awake".
    property var topProcs: []
    Process {
        id: procProbe
        // Two samples, not one: %CPU in a single top pass (and ps pcpu) is an
        // average over the process lifetime, which reports a long-idle process
        // as busy forever. Only the second block measures the 0.5s interval, so
        // awk keeps resetting and prints whatever the last header left behind.
        // -w200 stops top truncating COMMAND to the terminal width.
        command: ["sh", "-c",
            "top -bn2 -d 0.5 -w200 -o %CPU 2>/dev/null | " +
            "awk '/^ *PID/{n=0;delete a;next} " +
            "$1~/^[0-9]+$/&&n<2&&$9+0>0.5{a[n++]=$12\" \"$9} " +
            "END{for(i=0;i<n;i++)print a[i]}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f.length < 2) continue;
                    out.push({ name: f[0], pct: Number(f[1]) });
                }
                root.topProcs = out;
            }
        }
    }
    Timer {
        interval: 3000; running: root.powerPanelOpen; repeat: true; triggeredOnStart: true
        onTriggered: { procProbe.running = true; chargeLimitFile.reload(); }
    }

    // ---- night light (hyprsunset) ----
    // "on|off <kelvin>". The script is the single source of truth for both the
    // stored temperature and what counts as "on" — see its header for why that
    // is process lifetime rather than hyprsunset's identity mode.
    property bool nightLight: false
    property int nightTemp: 3500
    Process {
        id: nightProbe
        command: ["sh", "-c", "~/.config/hypr/scripts/nightlight status 2>/dev/null"]
        stdout: SplitParser {
            onRead: data => {
                const f = data.trim().split(/\s+/);
                if (f[0] !== "on" && f[0] !== "off") return;
                root.nightLight = f[0] === "on";
                const t = Number(f[1]);
                if (t > 0) root.nightTemp = t;
            }
        }
    }
    function setNightLight(on) {
        nightLight = on;
        Quickshell.execDetached(["sh", "-c",
            "~/.config/hypr/scripts/nightlight " + (on ? "on" : "off")]);
    }
    // Setting a temperature switches it on, matching the script: a value that
    // nothing is applying is not worth showing as a change.
    function setNightTemp(k) {
        nightTemp = k;
        nightLight = true;
        Quickshell.execDetached(["sh", "-c",
            "~/.config/hypr/scripts/nightlight set " + k]);
    }

    // Service statuses. These used to shell out to ~/.scripts/waybar/*.sh for a
    // JSON blob with a .text field; that whole directory is gone, so the three
    // probes had been forking every five seconds to produce empty strings. The
    // docker and vm summaries are now derived from the per-item lists below —
    // the same data, no extra process — and tailscale answers for itself.
    // Always rendered, count and all: hiding at zero made a dead daemon and an
    // idle one look identical, which is the one thing the cell exists to tell
    // apart. dockerUp is what separates them — the bar greys the cell when it
    // is false. The old waybar script had three states (OFF / 0 / N) and the
    // first port collapsed the first two into nothing.
    // Values only. The icon used to be prepended into these strings as a glyph;
    // it belongs to the cell that draws them, not to the data.
    readonly property bool dockerUp: dockerRunning
    readonly property string docker: "" + dockerList.length
    readonly property string vm: "" + vmList.length

    // tailscale: one `status --json` (18ms) feeds the bar cell and the panel,
    // so it is parsed once into fields rather than re-shelled per consumer.
    // Control needs no privilege since `tailscale set --operator=$USER`.
    property bool tsPresent: false
    property bool tsUp: false
    property string tsNode: ""
    property string tsIp: ""
    property string tsExit: ""          // exit node in use, by tailnet IP
    property var tsHealth: []
    property var tsPeerList: []         // [{n, ip, on, ex}]

    readonly property int tsPeerCount: tsPeerList.length
    readonly property int tsPeersOnline: tsPeerList.filter(p => p.on).length
    readonly property var tsExitOptions: tsPeerList.filter(p => p.ex)
    readonly property string tsExitName: {
        const m = tsPeerList.find(p => p.ip === root.tsExit);
        return m ? m.n : "";
    }

    Process {
        id: tsProc
        command: ["sh", "-c",
            "tailscale status --json 2>/dev/null | jq -c '{" +
            "s:.BackendState, n:(.Self.DNSName|split(\".\")[0]), ip:(.Self.TailscaleIPs[0]//\"\")," +
            "ex:((.ExitNodeStatus.TailscaleIPs[0]//\"\")|sub(\"/.*\";\"\"))," +
            "h:(.Health//[])," +
            "p:[.Peer[]?|{n:(.DNSName|split(\".\")[0]), ip:(.TailscaleIPs[0]//\"\")," +
            "on:.Online, ex:(.ExitNodeOption//false)}]}' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (!t) {
                    root.tsPresent = false; root.tsUp = false;
                    root.tsHealth = []; root.tsPeerList = [];
                    return;
                }
                try {
                    const j = JSON.parse(t);
                    root.tsPresent = true;
                    root.tsUp = j.s === "Running";
                    root.tsNode = j.n ?? "";
                    root.tsIp = j.ip ?? "";
                    root.tsExit = j.ex ?? "";
                    root.tsHealth = j.h ?? [];
                    root.tsPeerList = j.p ?? [];
                } catch (e) {
                    root.tsPresent = false;
                }
            }
        }
    }
    // `up`/`down` and `set` all return before the daemon has settled, so the
    // panel would show the old state until the next 5s tick without this
    Timer { id: tsSettle; interval: 700; onTriggered: tsProc.running = true }

    function tsSetUp(on) {
        Quickshell.execDetached(["tailscale", on ? "up" : "down"]);
        tsSettle.restart();
    }
    // empty ip clears it — `--exit-node=` with no value is how tailscale spells that
    function tsSetExit(ip) {
        Quickshell.execDetached(["tailscale", "set", "--exit-node=" + ip]);
        tsSettle.restart();
    }

    // per-item lists for the popout: [{name, status}]
    property var dockerList: []
    property var vmList: []
    property bool dockerRunning: false
    Process {
        id: dockerListProc
        // `docker ps` exits non-zero when the daemon is unreachable (and when
        // docker is not installed at all), so the daemon check rides along on
        // the call that was already being made rather than costing a second
        // fork every five seconds.
        command: ["sh", "-c", "docker ps --format '{{.Names}}|{{.Status}}' 2>/dev/null || echo __down__"]
        stdout: StdioCollector {
            onStreamFinished: {
                const down = text.indexOf("__down__") !== -1;
                root.dockerRunning = !down;
                root.dockerList = down ? [] : text.split("\n").filter(l => l).map(l => {
                    const i = l.indexOf("|");
                    return { name: l.slice(0, i), status: l.slice(i + 1) };
                });
            }
        }
    }
    Process {
        id: vmListProc
        // qemu VM names from -name (libvirt sets guest=X); nameless qemu shows "qemu"
        command: ["sh", "-c",
            "for p in $(pgrep -f '[q]emu-system-'); do " + // bracket dodges self-match
            "tr '\\0' '\\n' < /proc/$p/cmdline 2>/dev/null | " +
            "awk '$0==\"-name\"{getline;sub(/^guest=/,\"\");sub(/,.*/,\"\");print;f=1;exit} END{if(!f)print \"qemu\"}'; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: root.vmList = text.split("\n").filter(l => l)
                .map(n => ({ name: n, status: "running" }))
        }
    }

    // corne keyboard layer (cornd/cornectl, present on some hosts only)
    property string corne: ""
    Process {
        id: corneProc
        command: ["sh", "-c",
            "command -v cornectl >/dev/null 2>&1 && cornectl get layer 2>/dev/null || true"]
        stdout: SplitParser {
            onRead: data => {
                let t = data.trim();
                try { t = JSON.parse(t).text ?? t; } catch (e) {}
                root.corne = t;
            }
        }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: corneProc.running = true
    }

    // ---- network ----
    // Quickshell.Networking (NetworkManager backend, present on every host via
    // common.txt) replaces a 5s `ip route` + `jq` + `iw` fork. It carries SSID,
    // signal, security and connect/disconnect, but NOT an address:
    // NetworkDevice.address is the MAC. So the IP still needs a probe, and since
    // it only ever renders inside a popout it runs on device change, not on a timer.
    property bool netPanelOpen: false

    readonly property var netDevice: {
        const devs = Networking.devices?.values ?? [];
        let wifi = null;
        for (const d of devs) {
            if (!d.connected) continue;
            if (d.type === DeviceType.Wired) return d;   // wired owns the route when both are up
            if (!wifi) wifi = d;
        }
        return wifi;
    }
    readonly property var wifiDevice: {
        const devs = Networking.devices?.values ?? [];
        for (const d of devs) if (d.type === DeviceType.Wifi) return d;
        return null;
    }
    readonly property var wifiNetwork: {
        const nets = wifiDevice?.networks?.values ?? [];
        for (const n of nets) if (n.connected) return n;
        return null;
    }
    // connected first, then saved, then by strength
    readonly property var wifiList: {
        const nets = (wifiDevice?.networks?.values ?? []).slice();
        nets.sort((a, b) => (b.connected - a.connected)
                         || (b.known - a.known)
                         || (b.signalStrength - a.signalStrength));
        return nets;
    }

    readonly property bool netUp: Networking.connectivity === NetworkConnectivity.Full
    property string netIp: ""
    readonly property string netText: {
        if (!netDevice) return "down";
        if (netDevice.type === DeviceType.Wifi)
            return "W: " + (wifiNetwork?.name ?? "?") + " " + netIp;
        return "E: " + netIp;
    }
    readonly property string netLabel: {
        if (!netDevice) return "off";
        return netDevice.type === DeviceType.Wifi ? (wifiNetwork?.name ?? "wifi") : "eth";
    }
    // Icon names, not glyphs — see common/Icon.qml.
    readonly property string netIcon: {
        if (!netDevice) return "wifi-strength-off-outline";
        if (netDevice.type === DeviceType.Wired) return "ethernet";
        const s = wifiNetwork?.signalStrength ?? 0;
        if (s >= 0.75) return "wifi-strength-4";
        if (s >= 0.5) return "wifi-strength-3";
        if (s >= 0.25) return "wifi-strength-2";
        if (s > 0) return "wifi-strength-1";
        return "wifi-strength-outline";
    }

    onNetDeviceChanged: ipProc.running = true
    Process {
        id: ipProc
        command: ["sh", "-c", "ip -4 -o addr show " + (root.netDevice?.name ?? "lo")
            + " 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1"]
        stdout: StdioCollector { onStreamFinished: root.netIp = text.trim() }
    }

    // Scanning is only worth its power draw while somebody is looking at the list.
    // scannerEnabled is a request, not a mode: the backend clears it once the
    // scan finishes and NetworkManager then prunes its AP list down to the one
    // it is associated with, so it has to be re-asserted while the list is on
    // screen. Off the rest of the time — continuous scanning is real battery draw.
    onNetPanelOpenChanged: {
        if (wifiDevice) wifiDevice.scannerEnabled = netPanelOpen;
        if (netPanelOpen) ipProc.running = true;
    }
    Timer {
        interval: 8000
        running: root.netPanelOpen && root.wifiDevice !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: root.wifiDevice.scannerEnabled = true
    }

    // Saved PSK plus a QR of it. nmcli reads the secret with no prompt (polkit
    // allows it for the active session). qrencode is optional; the QR hides
    // without it rather than erroring.
    property string secretSsid: ""
    property string secretPsk: ""
    property string qrPath: ""
    property string qrPending: ""
    property bool hasQrencode: false

    Process {
        running: true
        command: ["sh", "-c", "command -v qrencode >/dev/null 2>&1"]
        onExited: code => root.hasQrencode = code === 0
    }
    Process {
        id: secretProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.secretPsk = text.trim();
                root.makeQr();
            }
        }
    }
    Process { id: qrProc; onExited: code => { if (code === 0) root.qrPath = root.qrPending; } }

    function loadSecret(ssid) {
        secretPsk = "";
        qrPath = "";
        secretSsid = ssid;
        if (!ssid) return;
        secretProc.running = false;
        secretProc.command = ["nmcli", "-s", "-g", "802-11-wireless-security.psk",
            "connection", "show", ssid];
        secretProc.running = true;
    }
    function makeQr() {
        if (!secretSsid) return;
        // the WIFI: URI is delimited by ; and :, so those have to be escaped in
        // the SSID and the key or a network named "a;b" produces a broken code
        const esc = s => s.replace(/([\\;,:"])/g, "\\$1");
        const uri = "WIFI:T:" + (secretPsk ? "WPA" : "nopass") + ";S:" + esc(secretSsid)
            + ";P:" + esc(secretPsk) + ";;";
        qrPending = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-wifi-qr.png";
        qrProc.running = false;
        qrProc.command = ["qrencode", "-o", qrPending, "-s", "6", "-m", "2", "--", uri];
        qrProc.running = true;
    }

    // disk free on /
    Process {
        id: diskProc
        command: ["sh", "-c", "df -h --output=avail / | tail -1 | tr -d ' '"]
        stdout: SplitParser { onRead: data => root.diskFree = data.trim() }
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            tsProc.running = true;
            dockerListProc.running = true;
            vmListProc.running = true;
            nightProbe.running = true;
        }
    }
    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: diskProc.running = true
    }
}
