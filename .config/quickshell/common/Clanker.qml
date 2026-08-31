pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// AI agent usage: one record per agent from ~/.scripts/agent-usage/update
// (omarchy's collectors, MIT), merged across owncloud-synced hosts by
// ~/.scripts/agent-usage/merge. Only agents that have actually recorded
// usage are listed, so the bar cell hides on a machine that never ran one.
Singleton {
    id: root

    property var agents: []          // records, sorted by id
    // selection by id, not tab position: a refresh can re-sort the list
    // under an open panel. Persisted so the bar cell shows the same agent
    // after a restart.
    property string selectedId: ""
    readonly property int current: Math.max(0, agents.findIndex(a => a.id === selectedId))
    readonly property var agent: agents[current] || null

    // which limit the bar cell shows, per agent: index into agent.limits,
    // default 0 (collectors list the 5h window first). Not persisted — a
    // restart falls back to the 5h default anyway.
    property var limitSel: ({})
    readonly property int limitIndex: agent ? Math.min(limitSel[agent.id] || 0, ((agent.limits || []).length) - 1) : -1
    readonly property var limit: limitIndex >= 0 ? agent.limits[limitIndex] : null
    // bar cell text: the pinned limit; balance-only agents fall back to headline
    readonly property real shown: limit ? Number(limit.percent) : headline(agent)
    // alarm still watches the fullest window so a maxed weekly can't hide
    readonly property real worst: headline(agent)
    readonly property bool alarming: worst >= 0.9

    function selectLimit(i) {
        if (!agent) return;
        const m = Object.assign({}, limitSel);
        m[agent.id] = i;
        limitSel = m;
    }

    // minute tick so "resets in 2h 13m" stays true while the popout is open
    property real nowMs: Date.now()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

    function headline(a) {
        let best = -1;
        for (const l of (a && a.limits) || []) if (Number(l.percent) > best) best = Number(l.percent);
        const b = a && a.balance;
        if (b && b.funded > 0) best = Math.max(best, 1 - b.remaining / b.funded);
        return best;
    }

    function select(id) { selectedId = id; }

    function refresh() { if (!collect.running) collect.running = true; }

    // ponytail: collectors re-run every 15 min like omarchy; the claude one
    // caches transcript scans by mtime so this is cheap after the first run
    Timer { interval: 15 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Process {
        id: collect
        command: ["sh", "-c", "$HOME/.scripts/agent-usage/update >/dev/null 2>&1; $HOME/.scripts/agent-usage/merge 2>/dev/null || echo []"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.agents = JSON.parse(text);
                    root.nowMs = Date.now();
                } catch (e) {}
            }
        }
    }

    FileView {
        id: selFile
        path: Quickshell.env("HOME") + "/.local/state/qs-clanker-agent"
        printErrors: false
        property bool ready: false
        onLoaded: { root.selectedId = text().trim(); ready = true; }
        onLoadFailed: ready = true
    }
    onSelectedIdChanged: if (selFile.ready) selFile.setText(selectedId)

    // "2h 13m" until an ISO timestamp, "" once passed
    function untilText(iso) {
        if (!iso) return "";
        const ms = new Date(iso) - nowMs;
        if (ms <= 0) return "";
        const m = Math.floor(ms / 60000);
        if (m < 60) return m + "m";
        const h = Math.floor(m / 60);
        if (h < 24) return h + "h " + (m % 60) + "m";
        return Math.floor(h / 24) + "d " + (h % 24) + "h";
    }

    function tokText(n) {
        n = Number(n) || 0;
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B";
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M";
        if (n >= 1e3) return Math.round(n / 1e3) + "K";
        return String(n);
    }

    // local calendar date as the records spell it
    function todayStr() {
        const d = new Date(nowMs);
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }
}
