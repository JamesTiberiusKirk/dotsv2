import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts
import "../../common"

// ---- docker / vms popout (click either cell) ----
// One popout, a tab per kind; each cell opens it on its own tab. Same list
// shape for both: name, status under it, a line of dim text when there is
// nothing to list. Docker rows also carry a stop button.
Popout {
    id: sp
    tabs: ["docker", "vms"]
    implicitWidth: 380
    rowSpacing: 6

    // cpu/mem per row are only polled while something shows them (Sys.statsWanted)
    onOpenChanged: Sys.statsWanted += open ? 1 : -1
    Component.onDestruction: if (open) Sys.statsWanted -= 1

    ListBody {
        visible: sp.currentTab === "docker"
        rows: Sys.dockerList
        stats: Sys.dockerStats
        empty: Sys.dockerUp ? "no containers running" : "daemon is down"
        stoppable: true
        busy: Sys.dockerStopping
        onStop: name => Sys.dockerStop(name)
    }
    ListBody {
        visible: sp.currentTab === "vms"
        rows: Sys.vmList
        stats: Sys.vmStats
        empty: "no vms running"
    }

    component ListBody: Column {
        id: lp
        property var rows: []      // [{ name, status }]
        property var stats: ({})   // name -> { cpu, mem }, appended to the status line
        property string empty: "nothing running"
        // A stop button per row (docker). The caller does the stopping; this
        // only says which row was asked. `busy` names the rows mid-stop: they
        // spin instead of offering the button again.
        property bool stoppable: false
        property var busy: []
        signal stop(string name)
        readonly property real contentWidth: sp.contentWidth
        width: contentWidth
        spacing: 6

        // The Repeater runs on names only, rebuilt when the set of names changes.
        // `rows` is reassigned on every 5s poll and its status text ("Up 5
        // minutes") changes every minute; a model built on it destroyed every row
        // each time, and with them the keyboard focus sitting on one.
        property var names: []
        property var statusOf: ({})
        onRowsChanged: {
            const n = rows.map(r => r.name);
            if (n.join("\n") !== names.join("\n")) names = n;
            const st = {};
            for (const r of rows) st[r.name] = r.status;
            statusOf = st;
        }

        Text {
            visible: lp.names.length === 0
            text: lp.empty
            font.family: Theme.font; font.pixelSize: 13
            color: Theme.dim
        }
        Repeater {
            model: lp.names
            // Two lines: the name is what you opened this for
            // and container names run long, so it gets the
            // whole width; the status sits under it.
            Item {
                id: row
                required property string modelData
                readonly property bool stopping: lp.busy.indexOf(row.modelData) >= 0
                width: lp.contentWidth
                height: texts.height
                // j/k walk onto a row (AttachedPanel), Return stops it — the
                // same opt-in every other popout row uses
                activeFocusOnTab: lp.stoppable
                Keys.onReturnPressed: if (lp.stoppable && !row.stopping) lp.stop(row.modelData)

                Rectangle {
                    anchors { fill: parent; margins: -3 }
                    radius: 5
                    color: row.activeFocus ? Theme.track : "transparent"
                }
                Column {
                    id: texts
                    anchors { left: parent.left; right: stopBtn.visible ? stopBtn.left : parent.right; rightMargin: 8 }
                    spacing: 2
                    Text {
                        width: parent.width
                        text: row.modelData
                        font.family: Theme.font; font.pixelSize: 13
                        color: Theme.text
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: row.stopping ? "stopping…"
                            : [lp.statusOf[row.modelData] ?? "", Sys.usageText(lp.stats[row.modelData])]
                                .filter(s => s).join("  ·  ")
                        font.family: Theme.font; font.pixelSize: 12
                        color: Theme.dim
                        elide: Text.ElideRight
                    }
                }
                Item {
                    id: stopBtn
                    visible: lp.stoppable
                    width: 20; height: 20
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    Icon {
                        anchors.centerIn: parent
                        name: row.stopping ? "refresh" : "stop"
                        size: 16
                        color: row.stopping ? Theme.dim
                             : (stopMouse.containsMouse || row.activeFocus) ? Theme.urgent : Theme.dim
                        RotationAnimator on rotation {
                            running: row.stopping
                            from: 0; to: 360; duration: 900
                            loops: Animation.Infinite
                        }
                        // a stopped spin leaves the icon at whatever angle it froze on
                        onVisibleChanged: if (!row.stopping) rotation = 0
                    }
                    MouseArea {
                        id: stopMouse
                        anchors { fill: parent; margins: -4 }
                        hoverEnabled: true
                        enabled: !row.stopping
                        onClicked: lp.stop(row.modelData)
                    }
                }
            }
        }
    }
}
