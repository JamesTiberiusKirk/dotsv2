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

// ---- tailscale panel (click ts cell) ----
Popout {
    id: tsPanel

    panelName: "tailscale"
    implicitWidth: 300

    component TsDiv: Rectangle {
        width: tsPanel.contentWidth; height: 1
        color: Theme.islandBorder
    }
    component TsHead: Text {
        font.family: Theme.font; font.pixelSize: 11
        color: Theme.dim
    }
    // click copies `value`; the label reads "copied" for a
    // second so the click is seen to land. Popout stays open.
    component TsCopy: Text {
        id: tc
        property string value
        property string label
        // Not a tab stop of its own. Two of these sit side by side, and making
        // each one a stop meant j — which means "down a row" everywhere else —
        // was how you moved right. The row above is the stop; it lights the
        // half it is on through `selected` and calls copy() on Return.
        property bool selected: false
        property color baseColor: Theme.dim
        text: copied.running ? "copied" : label
        elide: Text.ElideRight
        font.family: Theme.font; font.pixelSize: 11
        color: tc.selected ? Theme.bright : tc.baseColor
        function copy() {
            Quickshell.execDetached(["wl-copy", "--", tc.value]);
            copied.restart();
        }
        Timer { id: copied; interval: 1000 }
        MouseArea {
            anchors.fill: parent
            onClicked: tc.copy()
        }
    }

    ToggleRow {
        label: "tailscale"
        checked: Sys.tsUp
        onToggled: value => Sys.tsSetUp(value)
    }
    // hostname and IP, one stop between them: arrows / h / l pick which,
    // Return copies it. Same shape as the calendar's month header.
    Item {
        id: idRow
        visible: Sys.tsUp
        width: tsPanel.contentWidth
        height: 16
        activeFocusOnTab: true
        property int sel: 0
        function hstep(d) { idRow.sel = Math.max(0, Math.min(1, idRow.sel + d)); }
        Keys.onLeftPressed: idRow.hstep(-1)
        Keys.onRightPressed: idRow.hstep(1)
        Keys.onReturnPressed: idRow.sel === 0 ? idName.copy() : idIp.copy()

        Rectangle {
            anchors { fill: parent; margins: -3 }
            radius: 5
            color: idRow.activeFocus ? Theme.track : "transparent"
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            TsCopy {
                id: idName
                label: Sys.tsNode; value: Sys.tsDns
                selected: idRow.activeFocus && idRow.sel === 0
            }
            TsHead { text: "\u00b7" }
            TsCopy {
                id: idIp
                label: Sys.tsIp; value: Sys.tsIp
                selected: idRow.activeFocus && idRow.sel === 1
            }
        }
    }

    // ---- exit node ----
    TsDiv { visible: Sys.tsUp && Sys.tsExitOptions.length > 0 }
    TsHead {
        visible: Sys.tsUp && Sys.tsExitOptions.length > 0
        text: "exit node"
    }
    Item {
        id: exNone
        visible: Sys.tsUp && Sys.tsExitOptions.length > 0
        width: tsPanel.contentWidth
        height: 20
        activeFocusOnTab: Sys.tsExit !== ""
        Keys.onReturnPressed: Sys.tsSetExit("")

        Rectangle {
            anchors { fill: parent; margins: -2 }
            radius: 5
            color: exNone.activeFocus ? Theme.track : "transparent"
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5

            Icon {
                name: "check"
                size: 13
                // reserved, not removed — the peer rows below
                // line their names up with this one
                opacity: Sys.tsExit === "" ? 1 : 0
                color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "none"
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font; font.pixelSize: 12
                color: Sys.tsExit === "" ? Theme.bright : Theme.text
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: Sys.tsExit !== ""
            onClicked: Sys.tsSetExit("")
        }
    }
    Repeater {
        model: Sys.tsUp ? Sys.tsExitOptions : []

        Item {
            id: exRow
            readonly property var peer: modelData
            readonly property bool current: peer.ip === Sys.tsExit

            width: tsPanel.contentWidth
            height: 20
            activeFocusOnTab: exRow.peer.on
            Keys.onReturnPressed: Sys.tsSetExit(exRow.current ? "" : exRow.peer.ip)

            Rectangle {
                anchors { fill: parent; margins: -2 }
                radius: 5
                color: exRow.activeFocus ? Theme.track : "transparent"
            }
            Row {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 5

                Icon {
                    name: "check"
                    size: 13
                    opacity: exRow.current ? 1 : 0
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    width: Math.max(0, parent.width - 18)
                    elide: Text.ElideRight
                    text: exRow.peer.n + (exRow.peer.on ? "" : "  (offline)")
                    font.family: Theme.font; font.pixelSize: 12
                    color: exRow.current ? Theme.bright
                         : exRow.peer.on ? Theme.text : Theme.dim
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: exRow.peer.on
                onClicked: Sys.tsSetExit(exRow.current ? "" : exRow.peer.ip)
            }
        }
    }

    // ---- peers ----
    TsDiv { visible: Sys.tsUp }
    Item {
        visible: Sys.tsUp
        width: tsPanel.contentWidth
        height: 16

        TsHead {
            anchors.verticalCenter: parent.verticalCenter
            text: "peers"
        }
        TsHead {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: Sys.tsPeersOnline + "/" + Sys.tsPeerCount + " up"
        }
    }
    Flickable {
        id: tsScroll
        visible: Sys.tsUp
        width: tsPanel.contentWidth
        height: Math.min(contentHeight, 200)
        contentHeight: peerCol.implicitHeight
        clip: true
        SmoothScroll { flick: tsScroll }

        // clipped list: a row reached by j/k has to be scrolled into view
        function reveal(it) {
            const y = it.mapToItem(peerCol, 0, 0).y;
            if (y < contentY) contentY = y;
            else if (y + it.height > contentY + height) contentY = y + it.height - height;
        }

        Column {
            id: peerCol
            width: parent.width

            Repeater {
                model: Sys.tsPeerList

                // One stop per peer, not two. Ten peers used to cost twenty
                // j presses, every other one of them moving sideways.
                // Arrows / h / l pick name or IP, Return copies that one.
                Item {
                    id: pRow
                    readonly property var peer: modelData

                    width: peerCol.width
                    height: 20
                    activeFocusOnTab: true
                    property int sel: 0
                    function hstep(d) { pRow.sel = Math.max(0, Math.min(1, pRow.sel + d)); }
                    Keys.onLeftPressed: pRow.hstep(-1)
                    Keys.onRightPressed: pRow.hstep(1)
                    Keys.onReturnPressed: pRow.sel === 0 ? pName.copy() : pIp.copy()
                    onActiveFocusChanged: if (activeFocus) tsScroll.reveal(pRow)

                    Rectangle {
                        anchors { fill: parent; margins: -2 }
                        radius: 5
                        color: pRow.activeFocus ? Theme.track : "transparent"
                    }

                    // name copies the full MagicDNS name, ip copies the ip
                    TsCopy {
                        id: pName
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: parent.width - 120
                        label: (pRow.peer.on ? "\u25cf  " : "\u25cb  ") + pRow.peer.n
                        value: pRow.peer.d
                        font.pixelSize: 12
                        // the peer's own on/off colour, unless this half is picked
                        baseColor: pRow.peer.on ? Theme.text : Theme.dim
                        selected: pRow.activeFocus && pRow.sel === 0
                    }
                    TsCopy {
                        id: pIp
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        label: pRow.peer.ip
                        value: pRow.peer.ip
                        selected: pRow.activeFocus && pRow.sel === 1
                    }
                }
            }
        }
    }

    // never surfaced anywhere before: a silently broken
    // MagicDNS looks exactly like a working one
    TsDiv { visible: Sys.tsHealth.length > 0 }
    Repeater {
        model: Sys.tsHealth
        Text {
            width: tsPanel.contentWidth
            wrapMode: Text.WordWrap
            text: modelData
            font.family: Theme.font; font.pixelSize: 10
            color: Theme.urgent
        }
    }
}
