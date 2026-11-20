import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Console UI state, owned by the root (Lcars.qml / dev.qml / snap.qml) so the
// top-screen spine and popouts can share it.
QtObject {
    id: ui
    // One registry drives the console column, the docked panel and the top spine. Empty file = not built yet.
    readonly property var stations: [
        { name: "BRIDGE",   tint: Lc.blue,  file: "Bridge.qml" },
        { name: "CREW",     tint: Lc.lilac, file: "Crew.qml" },
        { name: "SYSTEMS",  tint: Lc.tan,   file: "Systems.qml" },
        { name: "COMMS",    tint: Lc.peach, file: "Comms.qml" },
        { name: "SETTINGS", tint: Lc.sky,   file: "Settings.qml" },
        { name: "COMPUTER", tint: Lc.rose,  file: "Computer.qml" }
    ]
    property string station: "BRIDGE"
    // Remember the station across reloads and restarts. Live shell only (its files load from .../lcars/);
    // the dev window and snapshots must not move the user's saved station.
    readonly property bool live: Qt.resolvedUrl(".").toString().indexOf("/lcars/") >= 0
    property FileView stationFile: FileView {
        path: ui.live ? Quickshell.env("HOME") + "/.local/state/lcars/station" : ""
        printErrors: false
        property bool ready: false
        onLoaded: { const n = text().trim(); if (ui.stations.some(x => x.name === n)) ui.station = n; ready = true; }
        onLoadFailed: ready = true
    }
    onStationChanged: if (live && stationFile.ready) stationFile.setText(station)
    property int wantPage: -1              // page a station should open on (ComputerIpc); the loaders apply it and reset to -1
    readonly property var current: stations.find(s => s.name === station) ?? stations[0]
    property bool released: false
    property bool screenPresent: true      // eDP-2 exists (docked keyboard turns it off)
    // docked fallback: station panel on the top screen, only meaningful while !screenPresent
    property bool panelOpen: false
    onScreenPresentChanged: if (screenPresent) panelOpen = false
    readonly property bool consoleShown: screenPresent && !released
    // touched in the last 90s; pollers pause when the console sits parked
    property bool attended: true
    // station a bar popout name belongs to (top-screen keybinds); unmapped names are ignored
    readonly property var panelStation: ({ audio: "COMMS", bluetooth: "COMMS", network: "COMMS", tailscale: "COMMS",
        power: "SYSTEMS", display: "SYSTEMS", system: "SYSTEMS", services: "SYSTEMS", "cc-sys": "SYSTEMS",
        clanker: "CREW", calendar: "BRIDGE", cc: "BRIDGE" })
    function showPanel(name) {
        const st = panelStation[String(name).split(":")[0]];
        if (!st) return;
        station = st;
        if (screenPresent) released = false; else panelOpen = true;
        poke();
    }
    // docked spine block / station tap: tapping the open station again closes the panel
    function tapStation(name) {
        if (panelOpen && station === name) panelOpen = false;
        else { station = name; panelOpen = true; }
        poke();
    }
    function poke() { attended = true; idle.restart(); }
    property Timer idleTimer: Timer { id: idle; interval: 90000; running: ui.attended; onTriggered: ui.attended = false }
}
