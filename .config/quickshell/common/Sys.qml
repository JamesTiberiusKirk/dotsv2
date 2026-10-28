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
    property real memUsed: 0        // 0..1, for the control center's meter
    property string swapText: ""
    property string diskFree: ""
    property real diskUsed: 0       // 0..1 of /, same

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
            root.memUsed = m.MemTotal > 0 ? (m.MemTotal - m.MemAvailable) / m.MemTotal : 0;
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
    // External DDC monitors as [{ name: connector, pct }], kept OUT of
    // `backlights` on purpose: `backlight` (the bar % and OSD) reads
    // backlights[0], and the lock-collapse below counts internal panels — an
    // external in that array would hijack both. Enumerated by `duo brightness
    // ext`, which is a ddcutil detect (seconds), so only on panel open, never
    // on a heartbeat and never after a write (that would rebuild the slider
    // Repeater mid-drag — the trap monitors/backlights both warn about).
    // On the Duo the daemon reads them instead (duoState below); this probe is
    // the fallback for a host without `duo watch`.
    property var externals: []
    property string extRaw: ""
    Process {
        id: extProbe
        running: false
        command: ["sh", "-c", "~/go/bin/duo brightness ext 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text === root.extRaw) return; // identical: don't rebuild
                root.extRaw = text;
                const ext = [];
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/);
                    if (f.length < 2) continue;
                    const pct = Number(f[1]);
                    if (!(pct >= 0)) continue; // -1 = read failed, skip it
                    ext.push({ name: f[0], pct: Math.round(pct) });
                }
                root.externals = ext;
            }
        }
    }
    function isExternal(name) {
        for (let i = 0; i < externals.length; i++)
            if (externals[i].name === name) return true;
        return false;
    }

    // Locked, every monitor tracks one value, so one "brightness" row writes
    // them all (target "all" → duo pushes both panels + every external).
    // Unlocked, one row per internal panel then one per external.
    readonly property var brightnessRows: (brightnessSync && (backlights.length + externals.length) > 1)
        ? [{ name: root.isDuo ? "all" : backlights[0].name, label: "brightness", pct: backlights[0].pct, off: false }]
        : backlights.map(d => ({
            name: d.name, label: d.label, pct: d.pct,
            off: root.isDuo && !root.subScreen && d.name === "card1-eDP-2-backlight"
        })).concat(externals.map(e => ({
            name: e.name, label: e.name, pct: e.pct, off: false
        })))
    // name -> live pct for every monitor, reassigned on EVERY state update
    // (the Repeater rows are not: sliders read this so values follow the
    // hardware without a rebuild). "all" is the locked row: the top panel.
    property var brightnessPct: ({})
    function refreshDisplays() { blProbe.running = true; }

    // Writes go through duo on the Duo so the sync flag and the OSD stay
    // coherent with the hardware keys; elsewhere brightnessctl (common.txt)
    // is already installed and does the one thing needed.
    function setBrightness(dev, pct) {
        // "all" (locked) and a connector name (an external) both go straight to
        // duo, which owns the panels' sysfs and the externals' coalescing.
        if (dev === "all" || isExternal(dev)) {
            Quickshell.execDetached(["sh", "-c", "~/go/bin/duo brightness set " + pct + " " + dev]);
            return;
        }
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
    function setSubScreen(on) {
        subScreen = on;
        Quickshell.execDetached(["sh", "-c", "~/go/bin/duo screen " + (on ? "on" : "off")]);
    }
    function setAutoRotate(on) {
        autoRotate = on;
        Quickshell.execDetached(["sh", "-c", "~/go/bin/duo autorotate " + (on ? "on" : "off")]);
    }

    // ---- monitor scale ----
    // Output names for the display panel's scale rows, plus { name: scale }
    // beside it. Split like brightnessRows/brightnessPct: reassigning
    // `monitors` resets the Repeater and destroys every delegate, which
    // mid-click deletes the pill's own hit area and drops the keyboard
    // focus off the row. So it changes only on hotplug; a new scale lands in
    // `monScales` alone. Read on panel open and after a write, never on a
    // heartbeat.
    property var monitors: []
    property var monScales: ({})
    Process {
        id: monProbe
        running: false
        command: ["sh", "-c", "hyprctl -j monitors 2>/dev/null | jq -c '[.[]|{name, scale}]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list;
                try { list = JSON.parse(text.trim()); } catch (e) { return; }
                const s = {};
                for (const m of list) s[m.name] = m.scale;
                root.monScales = s;
                const names = list.map(m => m.name);
                if (names.join() !== root.monitors.join()) root.monitors = names;
            }
        }
    }
    // Hyprland refuses a scale that gives a non-integer logical size and picks
    // the nearest one that does — 1.5 on a 2560-wide panel comes back as 1.6 —
    // so the displayed value has to come from the compositor, not from us.
    // Deliberately does NOT touch `monitors`: the row echoes the click
    // locally (ScaleRow.shown) so this array changes only when the probe
    // brings back something genuinely new. Rewriting it here would rebuild
    // the Repeater on every click and delete the pill's own MouseArea, or
    // the row holding keyboard focus, mid-gesture.
    function setScale(name, s) {
        Quickshell.execDetached(["sh", "-c",
            "~/.config/hypr/scripts/monitor-layout.sh scale " + name + " " + s]);
        monReadback.restart();
    }
    // The script waits out the modeset before re-saving; read after that.
    Timer { id: monReadback; interval: 1200; onTriggered: monProbe.running = true }

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

    // Fired when the machine comes back from suspend. Qt timers run on the
    // monotonic clock, which stops during sleep, so anything scheduled "in
    // 40 seconds" before the lid closed still has 40 seconds to wait after
    // it opens — the bar clock showed the pre-sleep minute until then.
    // elogind announces resume on the system bus (PrepareForSleep false);
    // there is no D-Bus API in QML, so a filtered dbus-monitor sits on that
    // one signal. Idle on a socket read between events.
    // Waking up, for the bar clock (SystemClock does not resync across sleep).
    // Only listens: screens around sleep are hypridle's (scripts/idle: off
    // before, on + layout after) — this used to blank them as well, a second
    // owner of the same job. No D-Bus API in QML, so a filtered dbus-monitor
    // sits on the one signal.
    signal resumed()
    Process {
        id: sleepWatch
        running: true
        command: ["dbus-monitor", "--system",
                  "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        stdout: SplitParser {
            onRead: line => { if (line.indexOf("boolean false") !== -1) root.resumed(); }
        }
        // the bus daemon restarting would take the monitor with it
        onExited: restartWatch.restart()
    }
    Timer { id: restartWatch; interval: 5000; onTriggered: sleepWatch.running = true }
    // Close every popout and the drawer, on every screen. Bound to Esc via the
    // `popout` submap below; the bar panels listen.
    signal closeAll()

    // How many bar panels currently have a popout up (one per screen), plus
    // the drawer. While anything is open Hyprland sits in the `popout` submap,
    // whose only binding is Esc → closeAll — a mouse-opened popout takes no
    // keyboard focus (that broke pointer focus on the bell), so Esc has to be
    // caught at the compositor. Everything else passes through a submap.
    property int barPopoutsOpen: 0
    readonly property bool anythingOpen: barPopoutsOpen > 0 || Notifs.centerOpen
    onAnythingOpenChanged: if (!anythingOpen) kbdNav = false
    // How many bar panels have a popout holding the keyboard — opened from
    // the menu, or showing an InputField. The `popout` submap's catchall
    // closes everything on any key, so while one of these is up it must be
    // off, or the first keystroke typed into it closes it. The popout
    // handles Esc itself then (AttachedPanel, InputField).
    property int barPopoutsGrabbing: 0
    // Set by the launcher while it is open (its own submap, see binds.lua).
    property bool launcherOpen: false

    // The one place Hyprland's submap is decided. Two writers used to each
    // dispatch on their own events, and whichever ran last won.
    readonly property string submap: launcherOpen ? "launcher"
        : anythingOpen && barPopoutsGrabbing === 0 ? "popout" : "reset"
    // Deferred: one popout closing moves both counters, one after the other,
    // and dispatching each step would send a "popout" between two "reset"s —
    // dispatches are not guaranteed to land in order. callLater coalesces
    // them into one dispatch of the settled value.
    onSubmapChanged: Qt.callLater(root.applySubmap)
    function applySubmap() { Hyprland.dispatch('hl.dsp.submap("' + submap + '")'); }
    // Set by openPanel before the popout maps: Hyprland only hands an OnDemand
    // layer focus on map, so this has to be true by the time it appears.
    property bool kbdNav: false
    function openPanel(name) {
        kbdNav = true;
        togglePanel(name);
        // togglePanel runs its handlers inline, so this sees the result: no
        // panel answered (no focused monitor matched), or the row toggled an
        // open popout shut. Either way nothing must stay flagged.
        if (!anythingOpen) kbdNav = false;
    }
    function poll() {
        monProbe.running = true;
        if (root.isDuo) {
            // the daemon owns the i2c bus: it re-detects and re-reads the
            // externals (seconds), then rewrites the state file once more
            Quickshell.execDetached(["sh", "-c", "~/go/bin/duo brightness refresh"]);
            root.applyDuoState(true);
        } else {
            blProbe.running = true;
        }
    }
    Timer {
        interval: 2000; running: !root.panelOpen && !root.isDuo; repeat: true; triggeredOnStart: true
        onTriggered: blProbe.running = true
    }

    // ---- Duo: the daemon's state file ----
    // `duo watch` looks at the hardware (dock, keyboard level, bottom panel,
    // autorotate, every backlight and external) and rewrites
    // $XDG_RUNTIME_DIR/duo/state only when something differs; see duo/publish.go.
    // This replaces four timers that each forked a shell every 2-5s.
    //
    // Slider rows are only rebuilt while the panel is closed (or when the set
    // of monitors changes): reassigning backlights/externals destroys the
    // Repeater's delegates, so doing it on every write would delete the slider
    // out from under a drag. The one exception is the re-read poll() asks for
    // on open: duo bumps "refreshed N" when it lands (seconds later), and only
    // that number moving — never our own slider writes — rebuilds open rows.
    property int duoRefreshed: -1
    FileView {
        id: duoState
        path: root.isDuo ? Quickshell.env("XDG_RUNTIME_DIR") + "/duo/state" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyDuoState(false)
        // qs and duo both start at login; until duo's first write there is no
        // file to watch, so keep knocking
        onLoadFailed: duoStateRetry.restart()
    }
    Timer { id: duoStateRetry; interval: 2000; onTriggered: duoState.reload() }
    function applyDuoState(force) {
        const text = duoState.text();
        if (!text) return; // mid-write: the next change event brings the rest
        const devs = [], ext = [];
        let refreshed = root.duoRefreshed;
        for (const line of text.split("\n")) {
            const f = line.trim().split(/\s+/);
            switch (f[0]) {
            case "docked": root.duoKbd = f[1] === "on"; break;
            case "kbdlevel": root.kbdBacklight = Number(f[1]) || 0; break;
            case "bottom": root.subScreen = f[1] === "on"; break;
            case "autorotate": root.autoRotate = f[1] === "on"; break;
            case "sync": root.brightnessSync = f[1] !== "off"; break;
            case "bl": devs.push({ name: f[1], pct: Number(f[2]) }); break;
            case "ext": ext.push({ name: f[1], pct: Number(f[2]) }); break;
            case "refreshed": refreshed = Number(f[1]); break;
            }
        }
        devs.sort((a, b) => root.blRank(a.name) - root.blRank(b.name));
        for (let i = 0; i < devs.length; i++)
            devs[i].label = root.blLabel(devs[i].name, i);
        const live = {};
        for (const d of devs.concat(ext)) live[d.name] = d.pct;
        if (devs.length) live.all = devs[0].pct;
        root.brightnessPct = live;
        const names = a => a.map(d => d.name).join(",");
        if (force || !root.panelOpen || names(devs) !== names(root.backlights))
            root.backlights = devs;
        const fresh = refreshed !== root.duoRefreshed;
        root.duoRefreshed = refreshed;
        if (force || !root.panelOpen || fresh || names(ext) !== names(root.externals))
            root.externals = ext;
    }

    // Zenbook Duo keyboard backlight. The firmware exposes no readable node, so
    // the level is whatever duo(1) last set (it pushes via the osd ipc handler);
    // duoKbd just tracks whether the keyboard is docked at all.
    property int kbdBacklight: 0
    property bool duoKbd: false
    // "<docked> <level> <bottom-screen>" — level comes from duo's runtime file so
    // a quickshell restart picks the real value back up instead of guessing 0.
    // Only on a host without `duo watch`; on the Duo the state file
    // (applyDuoState) carries all three.
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
        interval: 5000; running: !root.isDuo; repeat: true; triggeredOnStart: true
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

    // Ultra power-save (~/.scripts/powersave): the state file holds 1 or 0 and
    // always exists, so watchChanges tracks it — a toggle from the shell
    // repaints straight away, not on the next panel open. Theme reads this to
    // drop every translucent surface to opaque.
    property bool ultraSave: false
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/ultrasave"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.ultraSave = text().trim() === "1"
        onLoadFailed: root.ultraSave = false
    }
    // Look flags (~/.scripts/glass): persisted 1/0 files, missing = on. The
    // script writes both files on every toggle so the watches have a file.
    readonly property string lookDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glass"
    property bool glassOn: true
    property bool transparencyOn: true
    // Theme reads this to drop every translucent surface to opaque.
    readonly property bool opaque: ultraSave || !transparencyOn
    FileView {
        path: root.lookDir + "/glass"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.glassOn = text().trim() !== "0"
        onLoadFailed: root.glassOn = true
    }
    FileView {
        path: root.lookDir + "/transparency"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.transparencyOn = text().trim() !== "0"
        onLoadFailed: root.transparencyOn = true
    }
    function setLook(flag, on) {
        if (flag === "glass") glassOn = on; else transparencyOn = on;
        Quickshell.execDetached([Quickshell.env("HOME") + "/.scripts/glass", flag, on ? "on" : "off"]);
    }

    // off takes the daemon profile to land on, so the script's own
    // `powerprofilesctl set` cannot race a segment click that follows it.
    function setUltraSave(on, profile) {
        ultraSave = on;
        Quickshell.execDetached([Quickshell.env("HOME") + "/.scripts/powersave"]
            .concat(on ? ["on"] : ["off", profile ?? "balanced"]));
    }

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

    // ---- idle ladder (hypridle via scripts/idle) ----
    // key=value lines from `idle status`; the script owns the settings file
    // and the generated hypridle.conf. "keep awake" (idleAwake) drops the
    // timeout listeners but keeps hypridle alive so suspend still locks first.
    property bool idleRunning: true
    property bool idleAwake: false
    property int idleLock: 5
    property bool idleLockOn: true
    property int idleScreen: 10
    property bool idleScreenOn: true
    property int idleSuspend: 30
    property bool idleSuspendOn: false
    Process {
        id: idleProbe
        command: ["sh", "-c", "~/.config/hypr/scripts/idle status 2>/dev/null"]
        stdout: SplitParser {
            onRead: data => {
                const [k, v] = data.trim().split("=");
                switch (k) {
                case "running": root.idleRunning = v === "1"; break;
                case "awake": root.idleAwake = v === "1"; break;
                case "lock": root.idleLock = Number(v); break;
                case "lock_on": root.idleLockOn = v === "1"; break;
                case "screen": root.idleScreen = Number(v); break;
                case "screen_on": root.idleScreenOn = v === "1"; break;
                case "suspend": root.idleSuspend = Number(v); break;
                case "suspend_on": root.idleSuspendOn = v === "1"; break;
                }
            }
        }
    }
    // Optimistic local set + fire the script, like the night light setters;
    // the panel-open probe below re-syncs from the file afterwards.
    function setIdleAwake(on) {
        idleAwake = on;
        Quickshell.execDetached(["sh", "-c",
            "~/.config/hypr/scripts/idle awake " + (on ? "on" : "off")]);
    }
    function setIdleStage(stage, on) {
        if (stage === "lock") idleLockOn = on;
        else if (stage === "screen") idleScreenOn = on;
        else idleSuspendOn = on;
        Quickshell.execDetached(["sh", "-c",
            "~/.config/hypr/scripts/idle " + (on ? "on " : "off ") + stage]);
    }
    // Dragging a stage's timeout also enables it, matching the script (and
    // the temperature slider): a minute count nothing applies means nothing.
    function setIdleMinutes(stage, min) {
        if (stage === "lock") { idleLock = min; idleLockOn = true; }
        else if (stage === "screen") { idleScreen = min; idleScreenOn = true; }
        else { idleSuspend = min; idleSuspendOn = true; }
        Quickshell.execDetached(["sh", "-c",
            "~/.config/hypr/scripts/idle set " + stage + " " + min]);
    }
    // Only polled while the display panel is open — nothing in the bar itself
    // shows idle state, so the always-on 5s tick stays out of it.
    Timer {
        interval: 3000; running: root.panelOpen; repeat: true; triggeredOnStart: true
        onTriggered: idleProbe.running = true
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
    property string tsDns: ""           // full MagicDNS name, host.tailnet.ts.net
    property string tsExit: ""          // exit node in use, by tailnet IP
    property var tsHealth: []
    property var tsPeerList: []         // [{n, d, ip, on, ex}]

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
            "s:.BackendState, n:(.Self.DNSName|split(\".\")[0]), d:(.Self.DNSName|rtrimstr(\".\")), ip:(.Self.TailscaleIPs[0]//\"\")," +
            "ex:((.ExitNodeStatus.TailscaleIPs[0]//\"\")|sub(\"/.*\";\"\"))," +
            "h:(.Health//[])," +
            "p:[.Peer[]?|{n:(.DNSName|split(\".\")[0]), d:(.DNSName|rtrimstr(\".\")), ip:(.TailscaleIPs[0]//\"\")," +
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
                    root.tsDns = j.d ?? "";
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
    // Stop one container from the docker popout. The name goes in as an argv
    // entry, never into a shell string. `docker stop` waits out the container's
    // grace period (up to 10s), so the row spins until it returns, then the
    // list refreshes. One Process per stop: two rows can be stopping at once.
    property var dockerStopping: []
    Component {
        id: dockerStopComp
        Process {
            property string name
            running: true
            onExited: {
                root.dockerStopping = root.dockerStopping.filter(n => n !== name);
                dockerListProc.running = true;
                destroy();
            }
        }
    }
    function dockerStop(name) {
        if (root.dockerStopping.indexOf(name) >= 0) return;
        root.dockerStopping = root.dockerStopping.concat([name]);
        dockerStopComp.createObject(root, { name: name, command: ["docker", "stop", "--", name] });
    }
    // ---- docker / vm resource use ----
    // Polled only while something shows it (the sys control center or the
    // docker/vms popout): `docker stats` takes ~2s and real CPU per run.
    // Pages count themselves in and out, so two screens cannot undo each other.
    property int statsWanted: 0
    // name -> { cpu: percent of one core, mem: bytes }
    property var dockerStats: ({})
    property var vmStats: ({})
    // first numbers in yet? Until then the tiles spin instead of showing nothing.
    // Kept after that: reopening shows the last numbers while the next poll runs.
    property bool dockerStatsReady: false
    property bool vmStatsReady: false
    readonly property var dockerTotal: sumStats(dockerStats)
    readonly property var vmTotal: sumStats(vmStats)
    function sumStats(m) {
        const t = { cpu: 0, mem: 0, n: 0 };
        for (const k in m) { t.cpu += m[k].cpu; t.mem += m[k].mem; t.n++; }
        return t;
    }
    // "8% · 350M"; "" before the first poll
    function usageText(s) {
        if (!s || s.n === 0) return "";
        const b = s.mem, g = b / 1073741824;
        const mem = g >= 1 ? g.toFixed(1) + "G" : Math.round(b / 1048576) + "M";
        return Math.round(s.cpu) + "%  ·  " + mem;
    }
    Process {
        id: dockerStatsProc
        command: ["sh", "-c", "docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                // MemUsage is "21.4MiB / 30.71GiB": the used half, units to bytes
                const unit = { B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824, kB: 1e3, MB: 1e6, GB: 1e9 };
                const m = {};
                for (const l of text.split("\n").filter(l => l)) {
                    const [name, cpu, mem] = l.split("|");
                    const u = (mem || "").split("/")[0].trim().match(/^([\d.]+)\s*(\w+)$/);
                    m[name] = { cpu: parseFloat(cpu) || 0, mem: u ? parseFloat(u[1]) * (unit[u[2]] || 1) : 0, n: 1 };
                }
                root.dockerStats = m;
                root.dockerStatsReady = true;
            }
        }
    }
    // qemu has no stats command of its own: cpu ticks and RSS straight from /proc,
    // cpu as the tick delta between two polls (ps %cpu is a lifetime average)
    property var vmTicks: ({})
    Process {
        id: vmStatsProc
        command: ["sh", "-c",
            "for p in $(pgrep 'qemu-system-'); do " +
            "n=$(tr '\\0' '\\n' < /proc/$p/cmdline 2>/dev/null | " +
            "awk '$0==\"-name\"{getline;sub(/^guest=/,\"\");sub(/,.*/,\"\");print;f=1;exit} END{if(!f)print \"qemu\"}'); " +
            "t=$(awk '{print $14+$15}' /proc/$p/stat); r=$(awk '/^VmRSS/{print $2}' /proc/$p/status); " +
            "echo \"$n|$t|$r\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now(), m = {}, ticks = {}, prevTicks = root.vmTicks;
                for (const l of text.split("\n").filter(l => l)) {
                    const [name, t, rss] = l.split("|");
                    ticks[name] = { t: Number(t), at: now };
                    const prev = root.vmTicks[name];
                    // 100 ticks a second (USER_HZ); the first poll has no delta yet
                    const cpu = prev ? (Number(t) - prev.t) / ((now - prev.at) / 1000) : 0;
                    m[name] = { cpu: Math.max(0, cpu), mem: Number(rss) * 1024, n: 1 };
                }
                root.vmTicks = ticks;
                root.vmStats = m;
                // the first poll has no cpu delta yet, so it does not count as numbers in
                if (Object.keys(prevTicks).length > 0 || text.trim() === "") root.vmStatsReady = true;
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; triggeredOnStart: true
        running: root.statsWanted > 0
        onTriggered: {
            if (root.dockerRunning) dockerStatsProc.running = true;
            vmStatsProc.running = true;
        }
    }

    Process {
        id: vmListProc
        // qemu VM names from -name (libvirt sets guest=X); nameless qemu shows "qemu"
        command: ["sh", "-c",
            "for p in $(pgrep 'qemu-system-'); do " + // comm match, not -f: cmdline text (libvirt caps probes, greps) is not a VM
            "tr '\\0' '\\n' < /proc/$p/cmdline 2>/dev/null | " +
            "awk '$0==\"-name\"{getline;sub(/^guest=/,\"\");sub(/,.*/,\"\");print;f=1;exit} END{if(!f)print \"qemu\"}'; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: root.vmList = text.split("\n").filter(l => l)
                .map(n => ({ name: n, status: "running" }))
        }
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
        // one df for both: "214G  81%"
        command: ["sh", "-c", "df -h --output=avail,pcent / | tail -1"]
        stdout: SplitParser {
            onRead: data => {
                const [avail, pcent] = data.trim().split(/\s+/);
                root.diskFree = avail || "";
                root.diskUsed = (parseInt(pcent) || 0) / 100;
            }
        }
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
