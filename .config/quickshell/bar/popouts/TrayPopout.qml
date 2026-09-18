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

// ---- tray popout (click the dots cell) ----
Popout {
    id: trayPanel

    // Only the tray rows open this, so it lives with them
    QsMenuAnchor {
        id: trayMenu
        anchor.window: trayPanel
    }

    panelName: "tray"
    iconName: "dots-horizontal"
    implicitWidth: 240
    rowSpacing: 2

    Repeater {
        model: SystemTray.items.values
        Item {
            id: trayRow
            required property var modelData
            width: trayPanel.contentWidth
            height: 28
            activeFocusOnTab: true
            Keys.onReturnPressed: {
                trayRow.modelData.activate();
                bar.closeIslandPopouts();
            }

            Rectangle {
                anchors.fill: parent
                radius: 7
                color: trayHover.hovered || trayRow.activeFocus ? Theme.track : "transparent"
            }
            IconImage {
                id: trayRowIcon
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                implicitSize: 16
                source: trayRow.modelData.icon
            }
            Text {
                anchors { left: trayRowIcon.right; leftMargin: 10; right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                // title is what the app registers; the id is a bus name, last resort
                text: trayRow.modelData.title || trayRow.modelData.tooltipTitle || trayRow.modelData.id
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.text
                elide: Text.ElideRight
            }
            HoverHandler { id: trayHover }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: e => {
                    if (e.button === Qt.LeftButton) {
                        trayRow.modelData.activate();
                        bar.closeIslandPopouts();
                    } else if (trayRow.modelData.hasMenu) {
                        // the item's own menu, hung off this row rather
                        // than off the bar; the popout stays for it
                        trayMenu.menu = trayRow.modelData.menu;
                        trayMenu.anchor.rect.x = trayRow.mapToItem(null, 0, 0).x + trayRow.width;
                        trayMenu.anchor.rect.y = trayRow.mapToItem(null, 0, 0).y;
                        trayMenu.open();
                    } else {
                        trayRow.modelData.secondaryActivate();
                    }
                }
            }
        }
    }
}
