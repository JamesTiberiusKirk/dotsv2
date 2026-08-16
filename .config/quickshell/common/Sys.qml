pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// System stats not covered by a quickshell service. Reuses the same sources
// the waybar setup used: /tmp/i3status_* files (ping-latency.sh,
// update-count.sh started from hyprx) and the ~/.config/hypr/.layout file.
Singleton {
    id: root

    property string latency: ""
    property string layout: "dwindle"
    property string netText: "down"
    property bool netUp: false
    property real cpu: 0            // 0..1
    property string memText: ""
    property string swapText: ""
    property string diskFree: ""
    property real backlight: -1     // 0..1, -1 = no backlight device

    FileView {
        path: "/tmp/i3status_latency"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.latency = text().trim()
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/.layout"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.layout = text().trim() || "dwindle"
    }

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

    // backlight (poll; sysfs has no reliable inotify)
    // ponytail: device name hardcoded search via glob process once
    Process {
        id: blMax
        command: ["sh", "-c", "cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -1"]
        running: true
        stdout: SplitParser { onRead: data => root._blMax = Number(data) || 0 }
    }
    property real _blMax: 0
    Process {
        id: blNow
        command: ["sh", "-c", "cat /sys/class/backlight/*/brightness 2>/dev/null | head -1"]
        stdout: SplitParser {
            onRead: data => root.backlight = root._blMax > 0 ? Number(data) / root._blMax : -1
        }
    }
    Timer {
        interval: 2000; running: root._blMax > 0; repeat: true; triggeredOnStart: true
        onTriggered: blNow.running = true
    }
    function refreshBacklight() { blNow.running = true; }

    // service statuses, same scripts waybar used (JSON with a .text field)
    property string docker: ""
    property string tailscale: ""
    property string vm: ""
    Process {
        id: dockerProc
        command: ["sh", "-c", "~/.scripts/waybar/docker_status.sh"]
        stdout: SplitParser {
            onRead: data => { try { root.docker = JSON.parse(data).text; } catch (e) {} }
        }
    }
    Process {
        id: tsProc
        command: ["sh", "-c", "~/.scripts/waybar/tailscale.sh"]
        stdout: SplitParser {
            onRead: data => { try { root.tailscale = JSON.parse(data).text; } catch (e) {} }
        }
    }
    Process {
        id: vmProc
        command: ["sh", "-c", "~/.scripts/waybar/vm_status.sh"]
        stdout: SplitParser {
            onRead: data => { try { root.vm = JSON.parse(data).text; } catch (e) {} }
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

    // network summary, same shape as the old waybar module: "W: ssid ip" / "E: ip"
    Process {
        id: netProc
        command: ["sh", "-c",
            "r=$(ip -j route get 1.1.1.1 2>/dev/null) || { echo down; exit 0; };" +
            "dev=$(printf %s \"$r\" | jq -r '.[0].dev // empty');" +
            "src=$(printf %s \"$r\" | jq -r '.[0].prefsrc // empty');" +
            "[ -n \"$dev\" ] || { echo down; exit 0; };" +
            "if [ -d /sys/class/net/$dev/wireless ]; then " +
            "ssid=$(iw dev $dev link 2>/dev/null | sed -n 's/.*SSID: //p');" +
            "echo \"W: ${ssid:-?} $src\"; else echo \"E: $src\"; fi"]
        stdout: SplitParser {
            onRead: data => {
                root.netText = data.trim();
                root.netUp = data.trim() !== "down";
            }
        }
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
            netProc.running = true;
            dockerProc.running = true;
            tsProc.running = true;
            vmProc.running = true;
        }
    }
    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: diskProc.running = true
    }
}
