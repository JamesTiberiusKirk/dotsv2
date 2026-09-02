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
    readonly property var allPlayers: Mpris.players.values.filter(p => !p.dbusName.endsWith(".playerctld"))
    // X'd out from the island: a browser tab that stopped playing keeps its
    // title and so keeps the island alive forever. Dropped until it plays
    // again. Per player, so X'ing the dead youtube tab falls through to spotify
    property var dismissed: []
    readonly property var players: allPlayers.filter(p => !dismissed.includes(p))
    property var picked: null
    property var lastChanged: null
    // set on any track change so the island can flash that player's track
    signal trackChanged(var player)

    readonly property var player: (picked && players.includes(picked)) ? picked
        : players.find(p => p.isPlaying)
        ?? ((lastChanged && players.includes(lastChanged)) ? lastChanged : (players[0] ?? null))

    // is there anything worth showing an island for? a browser that registered
    // MPRIS without ever playing (0:00 / 0:00, no title) does not count
    readonly property bool active: !!player && (player.isPlaying || !!player.trackTitle)

    function select(p) { picked = p; }
    function dismiss(p) { if (p && !dismissed.includes(p)) dismissed = dismissed.concat([p]); }
    function revive(p) { if (dismissed.includes(p)) dismissed = dismissed.filter(x => x !== p); }

    Instantiator {
        model: Mpris.players
        Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { if (modelData.isPlaying) root.revive(modelData); }
            function onTrackChanged() {
                root.revive(modelData);
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
