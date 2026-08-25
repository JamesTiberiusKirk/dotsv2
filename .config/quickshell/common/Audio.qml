pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// Everything the audio panel needs. Deliberately not in Sys.qml — that one is
// already six unrelated domains deep, and this is self-contained.
Singleton {
    id: root

    // Nothing on a node — its properties, its audio object, its type — is
    // readable until the node is bound. The list is a dozen objects, so track
    // the lot rather than juggling per-row trackers.
    PwObjectTracker { objects: Pipewire.nodes.values }

    // Peak monitors open a real pipewire stream per node, so they only run
    // while somebody is looking at the panel.
    property bool panelOpen: false

    // A node's type is Untracked until it binds, a beat after it appears, and
    // the filters below capture nodes.values — not each node's type — so they
    // would keep a new stream at its stale type forever. Bumping rev on the
    // add/remove signals (and once more after the bind settles) forces them.
    property int rev: 0
    readonly property int nodeCount: Pipewire.nodes.values.length
    onNodeCountChanged: settle.restart()
    Connections {
        target: Pipewire
        function onReadyChanged() { settle.restart(); }
    }
    Timer {
        id: settle
        interval: 400
        onTriggered: { root.rev++; availProbe.running = true; }
    }

    // PipeWire lists every sink the card profile can expose, plugged in or not
    // — three HDMI outputs here with nothing on the other end. Whether a port
    // is live lives on the device route, not on the node, and quickshell does
    // not surface devices, so this is the one thing pactl still has to answer.
    // Empty means "have not been told", and everything shows: a missing pactl
    // must not make the whole device list vanish.
    property var availableNames: []
    Process {
        id: availProbe
        command: ["sh", "-c", "{ pactl list sinks; pactl list sources; } | awk '/^(Sink|Source) #/ { if (name && ok) print name; name=\"\"; ok=1 } /^\\tName: / { name=$2 } /^\\t\\t\\[(Out|In)\\]/ { ok = ($0 ~ /not available/) ? 0 : 1 } END { if (name && ok) print name }'"]
        stdout: StdioCollector {
            onStreamFinished: root.availableNames = text.split("\n").filter(x => x)
        }
    }
    Timer {
        interval: 3000
        running: root.panelOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: availProbe.running = true
    }
    function available(node) {
        return root.availableNames.length === 0
            || root.availableNames.indexOf(node.name) >= 0;
    }

    function ofType(t) {
        root.rev; root.availableNames;   // dependencies, see above
        return Pipewire.nodes.values.filter(n => n.type === t);
    }

    readonly property var sinks: ofType(PwNodeType.AudioSink).filter(available)
    readonly property var sources: ofType(PwNodeType.AudioSource).filter(available)
    // A peak monitor is itself a capture stream, named "Quickshell Peak
    // Detect". Without this the panel's own meters show up as apps holding the
    // mic, each row drawing a meter of its own — an unbounded loop that makes
    // the whole popout grow and flicker.
    function ownMonitor(node) {
        return (node.properties ?? {})["application.name"] === "Quickshell Peak Detect";
    }

    readonly property var playing: ofType(PwNodeType.AudioOutStream).filter(n => !ownMonitor(n))
    readonly property var capturing: ofType(PwNodeType.AudioInStream).filter(n => !ownMonitor(n))
    readonly property bool recording: capturing.length > 0

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // Pipewire.preferredDefaultAudioSink accepts the write and reads back, but
    // the default never actually moves — verified against both an unplugged
    // HDMI sink and a live monitor. wpctl is what switches it.
    function setDefault(node) {
        if (node) Quickshell.execDetached(["wpctl", "set-default", String(node.id)]);
    }

    // Back to 100%, unmuted, for every app holding an output stream. Muted-at-
    // 100% is still a silent app, so mute is part of "reset" — otherwise the
    // button looks like it did nothing.
    function resetAppLevels() {
        for (const n of root.playing) {
            if (!n.audio) continue;
            n.audio.volume = 1;
            n.audio.muted = false;
        }
    }

    // five-step speaker icon, matching the bar's other level indicators
    function volIcon(vol, muted) {
        if (muted) return "volume-off";
        if (vol > 0.66) return "volume-high";
        if (vol > 0.33) return "volume-medium";
        if (vol > 0) return "volume-low";
        return "volume-off";
    }

    // "Telegram" beats "Playback Stream"; media.name carries the track and is
    // worth a second line only when it says something the name does not.
    function appName(node) {
        const p = node.properties ?? {};
        return node.nickname || p["application.name"] || node.name || "audio";
    }
    function appDetail(node) {
        const p = node.properties ?? {};
        const m = p["media.name"] ?? "";
        return m === root.appName(node) ? "" : m;
    }
    function devName(node) {
        if (!node) return "";
        return node.nickname || node.description || node.name;
    }
}
