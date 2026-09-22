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

// ---- network panel (click net cell) ----
Popout {
    id: networkPopout

    panelName: "network"
    iconName: "wifi-strength-4"
    implicitWidth: 320
    // which SSID has its detail row unfolded; "" = none
    property string expanded: ""
    onOpenChanged: {
        Sys.netPanelOpen = open;
        if (!open) expanded = "";
    }

    // Keyboard only while a passphrase field is actually showing.
    // Asking for it whenever the panel was open made this the one
    // popout that did not close on a second click of its cell:
    // Hyprland focuses a layer that wants keys the moment it maps,
    // and with the pointer parked on the cell that focus stayed on
    // the panel — the second click never reached the bar. OnDemand,
    // not Exclusive, so the compositor's own bindings keep working
    // while the field is up.
    // Hyprland only hands an OnDemand layer focus on map or on a click
    // into it; flipping the mode after the row click is ignored, so the
    // grab is what actually moves the keyboard here.
    // Menu-opened counts as wanting keys too, same reasoning.
    // pskFocus is the old flag, set by the passphrase field below.
    property bool pskFocus: false
    // five-step strength glyph, same ladder as the bar cell
    function bars(v) {
        if (v >= 0.75) return "wifi-strength-4";
        if (v >= 0.5) return "wifi-strength-3";
        if (v >= 0.25) return "wifi-strength-2";
        if (v > 0) return "wifi-strength-1";
        return "wifi-strength-outline";
    }
    wantsKeys: networkPopout.pskFocus

    Text {
        text: Sys.netLabel
        font.family: Theme.font; font.pixelSize: 15
        color: Theme.bright
    }
    Text {
        text: Sys.netUp
            ? [Sys.netIp,
               Sys.wifiNetwork ? WifiSecurityType.toString(Sys.wifiNetwork.security) : "wired",
               Sys.wifiNetwork ? Math.round(Sys.wifiNetwork.signalStrength * 100) + "%" : ""
              ].filter(x => x).join("  ·  ")
            : "no connection"
        font.family: Theme.font; font.pixelSize: 11
        color: Theme.dim
    }

    // a wired-only box has nothing below the header worth drawing
    Rectangle {
        visible: Sys.wifiDevice !== null
        width: networkPopout.contentWidth; height: 1; color: Theme.islandBorder
    }

    ToggleRow {
        visible: Sys.wifiDevice !== null
        label: "wifi"
        checked: Networking.wifiEnabled
        onToggled: value => Networking.wifiEnabled = value
    }

    Rectangle {
        visible: Sys.wifiDevice !== null && Networking.wifiEnabled
        width: networkPopout.contentWidth; height: 1; color: Theme.islandBorder
    }

    Text {
        visible: Networking.wifiEnabled && Sys.wifiList.length === 0
        text: "scanning…"
        font.family: Theme.font; font.pixelSize: 11
        color: Theme.dim
    }

    // capped height with a scroll rather than a truncated list:
    // a crowded band can turn up 30 APs and the weak one at the
    // bottom is often exactly the one being looked for
    Flickable {
        id: netScroll
        width: networkPopout.contentWidth
        height: Math.min(contentHeight, 260)
        contentHeight: netList.implicitHeight
        clip: true
        SmoothScroll { flick: netScroll }

        // the list is clipped, so a row reached by j/k has
        // to be brought into view or the ring lands off-panel
        function reveal(it) {
            const y = it.mapToItem(netList, 0, 0).y;
            if (y < contentY) contentY = y;
            else if (y + it.height > contentY + height) contentY = y + it.height - height;
        }

        Column {
            id: netList
            width: parent.width
            spacing: 4

            Repeater {
                model: Sys.wifiList

                Column {
                    id: netRow

                    readonly property var net: modelData
                    readonly property bool secured: net.security !== WifiSecurityType.Open
                    readonly property bool unfolded: networkPopout.expanded === net.name
                    readonly property bool secretShown: Sys.secretSsid === net.name
                    property string pskText: ""
                    property bool qrShown: false
                    property bool reveal: false
                    property string failMsg: ""

                    // NM rejects a bad key asynchronously; without this the row
                    // just flickers back to disconnected and says nothing
                    Connections {
                        target: netRow.net
                        function onConnectionFailed(reason) {
                            netRow.failMsg = ConnectionFailReason.toString(reason);
                        }
                        function onConnectedChanged() {
                            if (netRow.net.connected) netRow.failMsg = "";
                        }
                    }

                    width: netList.width
                    spacing: 6

                    function join(psk) {
                        if (!psk) return;
                        netRow.failMsg = "";
                        netRow.net.connectWithPsk(psk);
                    }

                    Item {
                        id: netHead
                        width: parent.width
                        height: 24
                        activeFocusOnTab: true
                        Keys.onReturnPressed: netHead.fold()
                        onActiveFocusChanged: if (activeFocus) netScroll.reveal(netHead)
                        function fold() {
                            const name = netRow.net.name;
                            networkPopout.expanded = networkPopout.expanded === name ? "" : name;
                            netRow.reveal = false;
                            netRow.qrShown = false;
                            netRow.failMsg = "";
                            Sys.loadSecret("");
                        }

                        Rectangle {
                            anchors { fill: parent; margins: -2 }
                            radius: 5
                            color: netHead.activeFocus ? Theme.track : "transparent"
                        }
                        Row {
                            anchors { left: parent.left; right: marks.left; verticalCenter: parent.verticalCenter; rightMargin: 6 }
                            spacing: 8

                            Icon {
                                name: networkPopout.bars(netRow.net.signalStrength)
                                size: 15
                                color: netRow.net.connected ? Theme.accent : Theme.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: Math.max(0, parent.width - 26)
                                text: netRow.net.name
                                elide: Text.ElideRight
                                font.family: Theme.font; font.pixelSize: 12
                                color: netRow.net.connected ? Theme.bright : Theme.text
                            }
                        }
                        Row {
                            id: marks
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 6

                            Text {
                                visible: netRow.net.stateChanging
                                text: "…"
                                font.family: Theme.font; font.pixelSize: 12
                                color: Theme.warn
                            }
                            Icon {
                                visible: netRow.secured
                                name: "lock"
                                size: 13
                                color: netRow.net.known ? Theme.text : Theme.dim
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Icon {
                                name: netRow.unfolded ? "chevron-up" : "chevron-down"
                                size: 13
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.dim
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: netHead.fold()
                        }
                    }

                    // ---- detail ----
                    FoldCard {
                        visible: netRow.unfolded
                        width: parent.width - 22
                        x: 22

                        // passphrase — only when there is no saved key to reuse
                        Row {
                            visible: netRow.secured && !netRow.net.known
                            spacing: 6

                            Rectangle {
                                width: 140; height: 24; radius: 4
                                color: Theme.track

                                TextInput {
                                    anchors { fill: parent; margins: 6 }
                                    font.family: Theme.font; font.pixelSize: 11
                                    color: Theme.bright
                                    echoMode: netRow.reveal ? TextInput.Normal : TextInput.Password
                                    clip: true
                                    // the surface takes focus on click, but nothing
                                    // hands it to the field inside the delegate
                                    onVisibleChanged: {
                                        networkPopout.pskFocus = visible;
                                        if (visible) forceActiveFocus();
                                    }
                                    onTextChanged: netRow.pskText = text
                                    Keys.onReturnPressed: netRow.join(netRow.pskText)
                                    Keys.onEscapePressed: bar.closeIslandPopouts()
                                }
                            }
                            PillBtn {
                                text: netRow.reveal ? "hide" : "show"
                                onPressed: netRow.reveal = !netRow.reveal
                            }
                            PillBtn {
                                text: "join"
                                active: netRow.pskText !== ""
                                onPressed: netRow.join(netRow.pskText)
                            }
                        }

                        // saved key, revealed on request
                        Row {
                            visible: netRow.net.known && netRow.secured
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: netRow.secretShown && netRow.reveal
                                    ? (Sys.secretPsk || "no saved key")
                                    : "••••••••"
                                font.family: Theme.font; font.pixelSize: 11
                                color: Theme.text
                            }
                            PillBtn {
                                text: netRow.secretShown && netRow.reveal ? "hide" : "password"
                                onPressed: {
                                    if (netRow.secretShown && netRow.reveal) {
                                        netRow.reveal = false;
                                    } else {
                                        netRow.reveal = true;
                                        Sys.loadSecret(netRow.net.name);
                                    }
                                }
                            }
                            PillBtn {
                                visible: Sys.hasQrencode
                                text: "qr"
                                active: netRow.qrShown
                                onPressed: {
                                    netRow.qrShown = !netRow.qrShown;
                                    if (netRow.qrShown) Sys.loadSecret(netRow.net.name);
                                }
                            }
                        }

                        Image {
                            visible: netRow.qrShown && netRow.secretShown && Sys.qrPath !== ""
                            source: Sys.qrPath ? "file://" + Sys.qrPath : ""
                            // the path is stable across regenerations, so the
                            // cache would keep serving the previous network's code
                            cache: false
                            fillMode: Image.PreserveAspectFit
                            width: 150; height: 150
                            smooth: false
                        }

                        Text {
                            visible: netRow.failMsg !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: netRow.failMsg
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.urgent
                        }

                        Row {
                            spacing: 6

                            PillBtn {
                                text: netRow.net.connected ? "disconnect" : "connect"
                                active: netRow.net.connected
                                visible: netRow.net.known || !netRow.secured
                                onPressed: netRow.net.connected ? netRow.net.disconnect() : netRow.net.connect()
                            }
                            PillBtn {
                                visible: netRow.net.known
                                text: "forget"
                                onPressed: {
                                    netRow.net.forget();
                                    networkPopout.expanded = "";
                                    Sys.loadSecret("");
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
