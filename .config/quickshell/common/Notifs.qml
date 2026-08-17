pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// Notification daemon state. Owning org.freedesktop.Notifications means dunst
// must not be running when the shell is (HYPR_SHELL=quickshell handles that).
Singleton {
    id: root

    property bool centerOpen: false
    property var popups: []   // [{ n: Notification, until: ms-epoch }]
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

    readonly property NotificationServer server: NotificationServer {
        actionsSupported: true
        bodySupported: true
        imageSupported: true
        onNotification: n => {
            n.tracked = true;
            const critical = n.urgency === NotificationUrgency.Critical;
            // honor the sender's timeout when it sets one (ms), like dunst did
            const ttl = n.expireTimeout > 0 ? n.expireTimeout : 6000;
            root.popups = root.popups.concat([{
                n: n,
                until: critical ? Number.MAX_VALUE : Date.now() + ttl
            }]);
            n.closed.connect(() => {
                root.popups = root.popups.filter(p => p.n !== n);
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

    function dismissAll() {
        const all = [...server.trackedNotifications.values];
        root.popups = [];
        for (const n of all)
            n.dismiss();
    }

    function dismissLatest() {
        if (popups.length > 0) {
            const latest = popups[popups.length - 1].n;
            root.popups = root.popups.filter(p => p.n !== latest);
            latest.dismiss();
            return;
        }
        const all = [...server.trackedNotifications.values];
        if (all.length > 0)
            all[all.length - 1].dismiss();
    }
}
