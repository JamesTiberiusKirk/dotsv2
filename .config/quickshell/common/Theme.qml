pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// One palette for the whole shell. Mode follows ~/.theme-mode (written by
// ~/.scripts/theme-apply) — dark = purple/black over blur, light = gruvbox.
Singleton {
    id: root

    property string mode: "dark"
    readonly property bool dark: mode !== "light"

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 12

    // screen bezel: band thickness + concave inner-corner radius
    readonly property int frameT: 2
    readonly property int frameFillet: 8
    // bar body height (island/capsule height, below the top band)
    readonly property int barBody: 30

    readonly property color island:       dark ? "#D90C0716" : "#D9FBF1C7"
    readonly property color islandBorder: dark ? "#884A3870" : "#AAD5C4A1"
    readonly property color surface:      dark ? "#D9120A22" : "#E6FBF1C7"
    readonly property color text:         dark ? "#D0B8F0"   : "#504945"
    readonly property color bright:       dark ? "#F0E8FF"   : "#3C3836"
    readonly property color dim:          dark ? "#5A3A7A"   : "#BDAE93"
    readonly property color accent:       dark ? "#A000FF"   : "#B57614"
    readonly property color accentText:   dark ? "#FFFFFF"   : "#FBF1C7"
    readonly property color track:        dark ? "#2A1A45"   : "#E0D2AC"
    readonly property color ok:           dark ? "#7DD87D"   : "#79740E"
    readonly property color urgent:       dark ? "#F87171"   : "#CC241D"

    FileView {
        path: Quickshell.env("HOME") + "/.theme-mode"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const t = text().trim();
            root.mode = (t === "light") ? "light" : "dark";
        }
    }
}
