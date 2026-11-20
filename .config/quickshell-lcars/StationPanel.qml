import QtQuick
import "."

// Docked fallback: while the lower screen is off (keyboard docked) the current station opens here,
// as a panel on the top screen. Window and visibility live in Lcars.qml; the station Loader works like
// Console's (only the current station is alive, and only while the panel is open).
Rectangle {
    id: sp
    required property var ship
    required property var ui
    color: Lc.black
    border.width: 3; border.color: ui.current.tint
    PointHandler {
        onActiveChanged: {
            sp.ui.poke();
            const b = sp.ship.computer;
            if (!active && b && b.typing) { if (b.boxTap) b.boxTap = false; else b.typing = false; }
        }
    }

    Rectangle {
        id: head
        x: 3; y: 3; width: parent.width - 6; height: 52
        color: Lc.dim
        Rectangle { id: code; width: 110; height: parent.height; color: Lc.orange
            Label { anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 3 } text: Lc.code("panel" + sp.ui.station); color: "black"; font.pixelSize: 18 } }
        Rectangle {
            anchors.left: code.right; anchors.leftMargin: Lc.gap
            width: nm.implicitWidth + 60; height: parent.height; color: sp.ui.current.tint
            Label { id: nm; anchors { right: parent.right; rightMargin: 24; bottom: parent.bottom; bottomMargin: 2 } text: sp.ui.station; color: "black"; font.pixelSize: 42 }
        }
        Pill {
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            height: 40; implicitWidth: 120; labelSize: 20
            text: "CLOSE"; tint: Lc.rose
            onClicked: sp.ui.panelOpen = false
        }
    }

    Item {
        x: 24; y: head.height + 22
        width: parent.width - 48; height: parent.height - y - 18
        Loader {
            id: loader
            anchors.fill: parent
            active: sp.ui.panelOpen && sp.ui.current.file !== ""
            function applyPage() { if (sp.ui.wantPage >= 0 && item && "page" in item) { item.page = sp.ui.wantPage; sp.ui.wantPage = -1; } }
            function load() { if (sp.ui.current.file !== "") setSource(sp.ui.current.file, { ship: sp.ship }); applyPage(); }
            Component.onCompleted: load()
            Connections { target: sp.ui; function onCurrentChanged() { loader.load(); } }
            Connections { target: sp.ui; function onWantPageChanged() { loader.applyPage(); } }
        }
    }
}
