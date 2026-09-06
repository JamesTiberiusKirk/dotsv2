pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// One palette for the whole shell, read from ~/.theme.json — written by
// ~/.scripts/theme-apply from ~/.config/themes/<name>.json. Defaults below
// are the purple theme, so the shell paints before the file lands.
Singleton {
    id: root

    property string name: "purple"
    property string mode: "dark"
    readonly property bool dark: mode !== "light"
    property var c: ({})

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 12

    // screen bezel: band thickness + concave inner-corner radius
    readonly property int frameT: 10
    // thinner band on the three edges without the bar
    readonly property int frameTEdge: 6
    readonly property int frameFillet: 8
    // convex radius of the screen's outer corners, and what shows outside them
    readonly property int frameRadius: 10
    readonly property color bezel: "#000000"
    // bar body height (island/capsule height, below the top band)
    readonly property int barBody: 30
    // gap between the bar and anything that hangs off it — popout
    // cards and notification toasts sit on the same line
    readonly property int popoutGap: 14

    // The three translucent tokens. Ultra power-save (Sys.ultraSave) forces them
    // opaque: hyprglass is off by then, so alpha would read as bare see-through
    // rather than glass. Declared as colors first so the hex strings are already
    // converted when .r/.g/.b are read off them.
    readonly property color islandBase: c.island || "#D90C0716"
    readonly property color islandBorderBase: c.islandBorder || "#884A3870"
    readonly property color surfaceBase: c.surface || "#D9120A22"
    readonly property color island: Sys.ultraSave ? Qt.rgba(islandBase.r, islandBase.g, islandBase.b, 1) : islandBase
    readonly property color islandBorder: Sys.ultraSave ? Qt.rgba(islandBorderBase.r, islandBorderBase.g, islandBorderBase.b, 1) : islandBorderBase
    readonly property color surface: Sys.ultraSave ? Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b, 1) : surfaceBase
    readonly property color text: c.text || "#D0B8F0"
    readonly property color bright: c.bright || "#F0E8FF"
    readonly property color dim: c.dim || "#5A3A7A"
    readonly property color accent: c.accent || "#A000FF"
    readonly property color accentText: c.accentText || "#FFFFFF"
    readonly property color track: c.track || "#2A1A45"
    readonly property color ok: c.ok || "#7DD87D"
    readonly property color warn: c.warn || "#FBBF24"
    readonly property color urgent: c.urgent || "#F87171"

    FileView {
        path: Quickshell.env("HOME") + "/.theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = JSON.parse(text());
                root.c = t;
                root.name = t.name || "";
                root.mode = t.mode === "light" ? "light" : "dark";
            } catch (e) { console.warn("Theme: bad ~/.theme.json:", e); }
        }
    }
}
