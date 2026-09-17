pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// AirPods state and controls, read from the librepods daemon.
//
// bluez publishes nothing for AirPods — no battery, no ANC, nothing — because
// all of it rides Apple's own AAP protocol over a raw L2CAP channel. The daemon
// (pkgbuilds/librepods-omarchy, started from hyprland.start) speaks that and
// republishes it as one line of JSON; this reads the line and shells out to
// librepods-ctl for the writes.
//
// Everything here degrades to "daemon down" rather than erroring: no AirPods on
// this host, or the daemon not running, is the normal case on most machines.
Singleton {
    id: root

    property var st: ({})

    FileView {
        id: state
        // XDG_STATE_HOME. QStandardPaths::GenericStateLocation on the daemon
        // side resolves to the same place.
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
              + "/librepods/status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.st = JSON.parse(text());
            } catch (e) {
                root.st = {};
            }
        }
        onLoadFailed: root.st = {}
    }

    // The daemon starts after qs and creates the file; it deletes it again on
    // quit. watchChanges needs the file to exist to watch it, so a slow retry
    // covers the gap — it only runs while there is nothing to show.
    Timer {
        interval: 5000
        repeat: true
        running: !root.up
        onTriggered: state.reload()
    }

    readonly property bool up: st.schema_version !== undefined
    readonly property bool connected: up && (st.connected ?? false)
    readonly property string name: st.device_name || st.model_name || "AirPods"

    // level -1 means "not reported yet" even when available is true
    function pod(k) {
        const p = root.st[k] ?? {};
        return {
            ok: (p.available ?? false) && (p.level ?? -1) >= 0,
            level: p.level ?? -1,
            charging: p.charging ?? false,
            inEar: p.in_ear ?? false
        };
    }
    // budL/budR rather than left/right: those two are FINAL properties on Item,
    // and a component that ever stops being a Singleton would fail to load.
    readonly property var budL: pod("left")
    readonly property var budR: pod("right")
    readonly property var budCase: pod("case")
    // A Max reports one battery under headset, which left/right/case cannot express
    readonly property var budSet: pod("headset")
    readonly property bool hasBattery:
        budL.ok || budR.ok || budCase.ok || budSet.ok

    // "L 80  R 75+  C 60" — charging marked with a +, since a second icon per
    // pod is three icons in a row 24px tall.
    //
    // Plain text for anywhere that wants one colour; batteryMarkup() is the
    // version that colours each cell on its own.
    function batteryCells() {
        const cell = (tag, p, inEar) => ({
            text: (tag ? tag + " " : "") + p.level + (p.charging ? "+" : ""),
            level: p.level,
            inEar: inEar
        });
        if (root.budSet.ok) return [cell("", root.budSet, true)];
        const out = [];
        if (root.budL.ok) out.push(cell("L", root.budL, root.budL.inEar));
        if (root.budR.ok) out.push(cell("R", root.budR, root.budR.inEar));
        // The case has no ear to be in, so it is never the bright one.
        if (root.budCase.ok) out.push(cell("C", root.budCase, false));
        return out;
    }
    readonly property string batteryText: batteryCells().map(c => c.text).join("  ")

    // Which pod is actually in your ear is the thing worth reading at a glance,
    // so it is the only one drawn at full strength — a pod in the case and a pod
    // on the desk both read as background. A low cell still wins over that:
    // "nearly flat" outranks "not currently in use".
    //
    // StyledText markup rather than a Row of Texts: the callers pass this to a
    // single string property, and one Text is cheaper than a repeater per cell.
    function batteryMarkup(cText, cDim, cWarn, cUrgent) {
        // StyledText parses #rrggbb, not the #aarrggbb a QColor stringifies to
        // when a theme gives the colour an alpha. Getting that wrong drops the
        // whole row silently, so drop the alpha rather than trust the palette.
        const hex = c => { const t = String(c); return t.length === 9 ? "#" + t.slice(3) : t; };
        cText = hex(cText); cDim = hex(cDim); cWarn = hex(cWarn); cUrgent = hex(cUrgent);
        return batteryCells().map(c => {
            const col = c.level <= 20 ? cUrgent
                      : c.level <= 35 ? cWarn
                      : c.inEar ? cText
                      : cDim;
            return "<font color=\"" + col + "\">" + c.text + "</font>";
        }).join("  ");
    }

    // -1 unknown, 0 off, 1 anc, 2 transparency, 3 adaptive
    readonly property int noiseMode: st.noise_mode ?? -1
    readonly property int adaptiveLevel: st.adaptive_noise_level ?? 0
    readonly property bool ca: st.conversational_awareness ?? false
    readonly property bool oneBud: st.one_bud_anc_mode ?? false
    // 0 pause when one out, 1 pause when both out, 2 disabled
    readonly property int earMode: st.ear_detection_behavior ?? 0

    // Read by nothing: the audio panel drops the off pill unconditionally,
    // because this reads true on a Pro 2 whose firmware rejects the packet.
    // Kept as the schema's own answer, for when that stops being true.
    readonly property bool supportsNoiseOff: st.supports_noise_off ?? true
    readonly property bool supportsNoiseControl: st.supports_noise_control ?? true
    readonly property bool supportsAdaptive: st.supports_adaptive ?? false
    readonly property bool supportsCa: st.supports_conversational_awareness ?? false
    readonly property bool supportsOneBud: st.supports_one_bud_anc ?? false

    // Writes go through the ctl binary, which owns the daemon's control socket.
    // Fire and forget: the daemon rewrites status.json when it lands, and that
    // is what the UI reads back. A click that does not stick shows as the row
    // snapping back, which is the truth.
    function ctl(verb) {
        Quickshell.execDetached(["librepods-ctl", verb]);
    }
}
