pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick

// Notification daemon state. Owning org.freedesktop.Notifications means dunst
// must not be running when the shell is (HYPR_SHELL=quickshell handles that).
Singleton {
    id: root

    property bool centerOpen: false
    property var popups: []   // [{ n: Notification, until: ms-epoch }]
    // Silences toasts. History still records everything — the point is to stop
    // things appearing over a screen share, not to stop hearing about them.
    property bool dnd: false
    // Per-app silence. Same rule as dnd, scoped to one sender: no toast, still
    // recorded. Keyed on appName because that is all the protocol gives us —
    // desktop-entry is optional and most senders leave it blank.
    property var mutedApps: []
    // Every sender history has seen — the settings page lists these, so there
    // is no registry of apps to maintain and nothing to add when a new one
    // starts sending.
    readonly property var apps: [...new Set(history.map(r => r.appName).filter(a => a))].sort()

    // Image source for a notification's picture. A sender's file image comes
    // through as image://icon//abs/path, and quickshell's icon provider
    // answers a missing file with a placeholder rather than an error — so a
    // temp file the sender already deleted (satty) drew as a checkerboard.
    // Loading the file directly makes a missing file a real load error, which
    // the delegates fold away.
    function imageSource(img) {
        img = String(img || "");
        return img.startsWith("image://icon//") ? "file://" + img.slice("image://icon/".length) : img;
    }

    // The app icon, or the app *name* looked up as one when the sender sets
    // none: satty ships satty.svg and never mentions it. Empty when neither
    // resolves, so the icon slot folds away instead of showing a placeholder.
    function appIconSource(appIcon, appName) {
        appIcon = String(appIcon || "");
        if (appIcon.startsWith("/")) return "file://" + appIcon;
        if (appIcon) return Quickshell.iconPath(appIcon, true);
        const byName = Quickshell.iconPath(String(appName || "").toLowerCase(), true);
        return byName || "";
    }

    function isMuted(app) { return mutedApps.indexOf(app) !== -1; }
    function setMuted(app, on) {
        const without = mutedApps.filter(a => a !== app);
        mutedApps = on ? without.concat([app]) : without;
    }

    // set at open time (bell click or IPC fallback) — never read before then
    property real centerAnchorX: 0
    property real centerAnchorWidth: 0
    property var centerScreen: null
    readonly property real centerScreenWidth: centerScreen ? centerScreen.width : 0

    function setCenterAnchor(x, w, screen) {
        centerAnchorX = x;
        centerAnchorWidth = w;
        centerScreen = screen;
    }

    // Open the drawer with nothing to hang it from (IPC, menu row): on the
    // focused monitor. The bell passes its own screen through setCenterAnchor.
    function toggle() {
        if (!centerOpen) {
            const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
            centerScreen = [...Quickshell.screens].find(sc => sc.name === name) || Quickshell.screens[0];
        }
        centerOpen = !centerOpen;
    }

    // ---- history -----------------------------------------------------------
    // The center used to render server.trackedNotifications directly, which
    // made the daemon's live set double as the history — so anything that
    // untracked a notification deleted the record too, and the whole lot
    // evaporated on a shell restart. History is its own list now: plain
    // serialisable records, with `n` holding the live Notification while we
    // still have one (null once restored from disk, which is what makes a
    // restored entry's action buttons disappear rather than misfire).
    property var history: []   // oldest first
    readonly property int historyCap: 100

    // Bumped on a timer while the center is open so the relative timestamps
    // re-evaluate; ago() reads it to take the dependency.
    property int tick: 0
    Timer {
        interval: 30000; repeat: true
        running: root.centerOpen
        onTriggered: root.tick++
    }

    function ago(ms) {
        root.tick;
        const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    // FileView will not create the directory, and on a fresh host nothing else
    // puts a quickshell dir under ~/.local/state.
    Process {
        running: true
        command: ["mkdir", "-p", Quickshell.statePath("")]
    }

    property bool storeReady: false
    FileView {
        id: store
        path: Quickshell.statePath("notifs.json")
        // The file is ours alone; a reload would only ever fight the writer.
        watchChanges: false
        printErrors: false
    }
    // Read synchronously, here, rather than from FileView's `loaded` signal.
    // With a blocking read the load completes inside the FileView's own
    // construction — before any onLoaded handler is connected — so a handler
    // there never ran and history silently started empty on every rebuild.
    // Synchronous on purpose: the server re-emits carried-over notifications
    // immediately on reload, and they have to be matched against a history
    // that has already loaded or they get filed as new. It is a few KB.
    Component.onCompleted: {
        store.blockLoading = true;
        let rows = [];
        try {
            const d = JSON.parse(store.text());
            // earlier revisions wrote a bare array; still read those rather
            // than throwing away someone's history on an upgrade
            const raw = Array.isArray(d) ? d : (d.history || []);
            root.dnd = Array.isArray(d) ? false : !!d.dnd;
            root.mutedApps = Array.isArray(d) ? [] : (d.mutedApps || []);
            rows = raw.map(r => Object.assign({}, r, { n: null }));
        } catch (e) {
            // no file yet, or unreadable — first run on this host
            rows = [];
        }
        // Prepended rather than assigned: a notification can already have
        // landed by now, and overwriting would drop it.
        root.history = rows.concat(root.history).slice(-root.historyCap);
        root.storeReady = true;
    }

    // Debounced: a burst of notifications would otherwise rewrite the file once
    // per arrival.
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: store.setText(JSON.stringify({
            dnd: root.dnd,
            mutedApps: root.mutedApps,
            history: root.history.map(r => ({
                key: r.key, id: r.id, appName: r.appName, summary: r.summary, body: r.body,
                appIcon: r.appIcon, image: r.image, urgency: r.urgency, time: r.time
            }))
        }))
    }
    onHistoryChanged: if (storeReady) saveTimer.restart()
    // Persisted too: muting before a meeting and being un-muted by the next
    // shell restart is the one way this setting can actively bite.
    onDndChanged: if (storeReady) saveTimer.restart()
    onMutedAppsChanged: if (storeReady) saveTimer.restart()

    readonly property NotificationServer server: NotificationServer {
        actionsSupported: true
        bodySupported: true
        imageSupported: true
        onNotification: n => {
            n.tracked = true;

            // A config reload does not restart the daemon: every notification
            // the previous generation still tracked is re-emitted here. Those
            // are already in history, and appending them again is how one
            // notification became six copies over an afternoon of edits.
            // Relink the live object onto the existing record instead, so its
            // action buttons survive the reload.
            if (n.lastGeneration) {
                const i = root.history.findIndex(r => !r.n && r.id === n.id);
                if (i !== -1) {
                    const merged = root.history.slice();
                    merged[i] = Object.assign({}, merged[i], { n: n });
                    root.history = merged;
                    return;
                }
            }

            const rec = {
                // the daemon reuses ids once a notification closes, so the id
                // alone is not stable enough to key a list row on
                key: n.id + ":" + Date.now(),
                id: n.id,
                appName: n.appName,
                summary: n.summary,
                body: n.body,
                appIcon: n.appIcon,
                // Only a path survives on the record. The daemon's own image
                // handles (image://qsimage/…) are read from the live object at
                // paint time: they change on every reload, and a stored one
                // is a dead reference the moment that happens.
                image: String(n.image || "").startsWith("image://qsimage/") ? "" : String(n.image || ""),
                urgency: n.urgency,
                time: Date.now(),
                n: n
            };
            // Trimming has to untrack what falls off the end. `tracked` is what
            // keeps a Notification alive, so a plain slice() would drop our last
            // reference to the record while the daemon still held the object.
            const next = root.history.concat([rec]);
            while (next.length > root.historyCap) {
                const dropped = next.shift();
                if (dropped.n)
                    dropped.n.dismiss();
            }
            root.history = next;

            if (!root.dnd && !root.isMuted(n.appName)) {
                const critical = n.urgency === NotificationUrgency.Critical;
                // honor the sender's timeout when it sets one (ms), like dunst did
                const ttl = n.expireTimeout > 0 ? n.expireTimeout : 6000;
                root.popups = root.popups.concat([{
                    // shared with the history record so the toast list can key
                    // its rows on something stable — without it the view
                    // rebuilds every delegate on each arrival and the slide-in
                    // transitions fire on toasts that were already there
                    key: rec.key,
                    n: n,
                    until: critical ? Number.MAX_VALUE : Date.now() + ttl
                }]);
            }
            // The daemon destroys the object once it is closed — by the sender,
            // by expiry, by us. The record stays; its live link goes, or the
            // next remove() would call dismiss() on a dead reference.
            n.closed.connect(() => {
                root.popups = root.popups.filter(p => p.n !== n);
                root.history = root.history.map(r => r.n === n ? Object.assign({}, r, { n: null }) : r);
            });
        }
    }

    Timer {
        interval: 500; repeat: true
        running: root.popups.length > 0
        onTriggered: {
            const now = Date.now();
            const keep = root.popups.filter(p => p.until > now);
            if (keep.length !== root.popups.length)
                root.popups = keep;
        }
    }

    // Hide a toast without touching the record behind it — clicking a toast
    // away is getting it off the screen, not throwing it out.
    function hidePopup(n) {
        root.popups = root.popups.filter(p => p.n !== n);
    }

    // Real deletion: the center's X and clear-all, and nothing else.
    function remove(rec) {
        root.history = root.history.filter(r => r !== rec);
        root.popups = root.popups.filter(p => p.n !== rec.n);
        if (rec.n)
            rec.n.dismiss();
    }

    function dismissAll() {
        root.popups = [];
        for (const r of root.history)
            if (r.n)
                r.n.dismiss();
        root.history = [];
    }

    function dismissLatest() {
        // A visible toast is a screen problem, so clear that first and leave
        // the record; only once nothing is on screen does this delete.
        if (popups.length > 0) {
            root.popups = root.popups.slice(0, -1);
            return;
        }
        if (history.length > 0)
            remove(history[history.length - 1]);
    }
}
