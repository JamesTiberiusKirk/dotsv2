import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../common"

// Wallpaper caption — bottom-left of every monitor, on the Bottom layer so it
// sits above awww and below every window: only visible where the desktop is.
// Text comes from ~/Pictures/wallpapers/info.tsv (file, title, artist, blurb);
// a file without a row falls back to its name. Refreshed by wallpaper.sh via
// `qs ipc call wallinfo refresh` after each apply.
Scope {
    id: scope

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/wallpapers"
    property var info: ({})

    FileView {
        path: scope.dir + "/info.tsv"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const m = {};
            for (const line of text().split("\n")) {
                if (!line || line.startsWith("#")) continue;
                const f = line.split("\t");
                m[f[0]] = { title: f[1] || "", artist: f[2] || "", blurb: f[3] || "" };
            }
            scope.info = m;
        }
    }

    IpcHandler {
        target: "wallinfo"
        function refresh(): void { scope.tick++; }
    }
    property int tick: 0

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { bottom: true; left: true }
            // clear the bar when it sits on this corner's edges
            margins {
                bottom: 18 + (ShellState.side === "bottom" ? ShellState.barBody + Theme.frameT : 0)
                left: 18 + (ShellState.side === "left" ? ShellState.barBody + Theme.frameT : 0)
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell-wallinfo"
            color: "transparent"
            implicitWidth: col.implicitWidth + 2 * pad
            implicitHeight: col.implicitHeight + 2 * pad
            readonly property int pad: 10
            visible: file !== ""

            property string file: ""
            property string dims: ""
            readonly property string base: file.slice(file.lastIndexOf("/") + 1)
            readonly property var row: scope.info[base] || {}

            // awww prints one line per output; pull this screen's and its size
            Process {
                id: query
                command: ["sh", "-c",
                    "p=$(awww query 2>/dev/null | sed -n 's/^: " + win.screen.name + ": .*currently displaying: image: //p'); " +
                    "[ -n \"$p\" ] && printf '%s\\n%s' \"$p\" \"$(identify -format '%wx%h' \"$p\" 2>/dev/null)\""]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const l = text.split("\n");
                        win.file = l[0] || "";
                        win.dims = l[1] || "";
                    }
                }
            }
            Connections {
                target: scope
                function onTickChanged() { query.running = true; }
            }
            Component.onCompleted: query.running = true

            // thin glass pane: low alpha so the wallpaper reads through, hyprglass
            // (layers enabled globally in hypr/plugins.lua) does the refraction
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Qt.rgba(Theme.island.r, Theme.island.g, Theme.island.b, 0.35)
                border.width: 1
                border.color: Qt.rgba(Theme.islandBorder.r, Theme.islandBorder.g, Theme.islandBorder.b, 0.4)
            }

            Column {
                id: col
                x: win.pad; y: win.pad
                spacing: 2
                Text {
                    text: win.row.title || win.base
                    font { family: Theme.font; pixelSize: Theme.fontSize + 2; bold: true }
                    color: Theme.bright
                }
                Text {
                    visible: !!win.row.artist
                    text: win.row.artist
                    font { family: Theme.font; pixelSize: Theme.fontSize }
                    color: Theme.text
                }
                Text {
                    visible: !!win.row.blurb
                    text: win.row.blurb
                    font { family: Theme.font; pixelSize: Theme.fontSize }
                    color: Theme.text
                }
                Text {
                    text: (win.row.title ? win.base + "  " : "") + win.dims
                    font { family: Theme.font; pixelSize: Theme.fontSize - 2 }
                    color: Theme.text
                    opacity: 0.7
                }
            }
        }
    }
}
