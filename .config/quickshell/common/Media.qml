pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Which MPRIS player the media keys and the island talk to. playerctl takes
// the first D-Bus name it sees, which is registration order — a paused
// YouTube tab kept eating play/pause meant for spotify. Here: the user's
// pick while it lives, else whatever is playing, else the last player that
// changed track.
Singleton {
    id: root

    // playerctld (playerctl's proxy daemon) mirrors the active player and
    // would show as a duplicate of it
    readonly property var players: Mpris.players.values.filter(p => !p.dbusName.endsWith(".playerctld"))
    property var picked: null
    property var lastChanged: null
    // set on any track change so the island can flash that player's track
    signal trackChanged(var player)

    readonly property var player: (picked && players.includes(picked)) ? picked
        : players.find(p => p.isPlaying)
        ?? ((lastChanged && players.includes(lastChanged)) ? lastChanged : (players[0] ?? null))

    function select(p) { picked = p; }

    Instantiator {
        model: Mpris.players
        Connections {
            required property var modelData
            target: modelData
            function onTrackChanged() {
                root.lastChanged = modelData;
                root.trackChanged(modelData);
            }
        }
    }

    // spotify / firefox / … → icon name if there is one, else music-note
    function icon(p) {
        const n = ((p?.desktopEntry || p?.identity) ?? "").toLowerCase();
        for (const k of ["spotify", "firefox", "google-chrome", "chat", "video"])
            if (n.includes(k.split("-")[0])) return k;
        return "music-note";
    }
    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
}
