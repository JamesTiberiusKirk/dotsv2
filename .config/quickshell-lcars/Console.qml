import QtQuick
import "."

// The bottom-screen LCARS console: spine entering from the top screen (hinge
// flow), top elbow + bar, station column, bottom elbow + bar, station content.
// `ui.released` = console hidden, only the spine with an OPEN CONSOLE tab remains.
Rectangle {
    id: con
    required property var ship
    required property var ui

    // `stubOnly`: the narrow window shown while released: only the released spine is painted, nothing is loaded
    property bool stubOnly: false
    readonly property var stations: ui.stations
    readonly property var current: ui.current

    // the top bar is thick: it carries the station name at its end (no separate title row)
    readonly property int topBar: 56

    color: ui.released ? "transparent" : Lc.black
    // passive: sees every touch without taking it, keeps the pollers awake
    PointHandler {
        onActiveChanged: {
            con.ui.poke();
            // COMPUTER chat box holds the keyboard (Exclusive): a finished tap anywhere but on the box hands it back
            const b = con.ship.computer;
            if (!active && b && b.typing) { if (b.boxTap) b.boxTap = false; else b.typing = false; }
        }
    }

    // ---- released: full-height spine with the tab ----
    Item {
        visible: con.ui.released
        anchors.fill: parent
        opacity: Lc.beat
        Rectangle { x: Lc.pad; y: 0; width: Lc.topSpine; height: parent.height * 0.3; color: Lc.lilac }
        Rectangle {
            x: Lc.pad; y: parent.height * 0.3 + Lc.gap
            width: Lc.topSpine; height: parent.height * 0.32
            color: Lc.orange
            Label {
                anchors.centerIn: parent
                rotation: -90
                text: "OPEN CONSOLE"
                color: "black"; font.pixelSize: 26
            }
            MouseArea { anchors.fill: parent; onClicked: con.ui.released = false }
        }
        Rectangle {
            x: Lc.pad; y: parent.height * 0.62 + 2 * Lc.gap
            width: Lc.topSpine; height: parent.height - y
            color: Lc.lilac
            bottomLeftRadius: 30
        }
    }

    // ---- frame ----
    Item {
        anchors.fill: parent
        visible: !con.ui.released && !con.stubOnly

        // spine stub entering from the top screen
        Rectangle { id: stub; x: Lc.pad; y: 0; width: Lc.topSpine; height: 24; color: Lc.lilac; opacity: Lc.beat }

        // top elbow (mirror of the bottom one) + bar
        Rectangle {
            id: topElbow
            opacity: Lc.beat
            x: Lc.pad; y: stub.height
            width: Lc.spine + 70; height: con.topBar + 40
            color: Lc.lilac
            Rectangle {
                x: Lc.spine; y: con.topBar
                width: parent.width - x + 1; height: parent.height - con.topBar + 1
                color: Lc.black
                topLeftRadius: 30
            }
        }
        Row {
            x: topElbow.x + topElbow.width + Lc.gap
            y: topElbow.y
            opacity: Lc.beat
            height: con.topBar
            spacing: Lc.gap
            readonly property real avail: con.width - x - Lc.pad
            Rectangle { id: codeBlock; width: 120; height: parent.height; color: Lc.orange
                Label { anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 4 } text: Lc.code("top" + con.ui.station); color: "black"; font.pixelSize: 18 } }
            Rectangle { width: parent.avail - codeBlock.width - nameBlock.width - cap.width - 3 * Lc.gap; height: parent.height; color: Lc.dim }
            Rectangle {
                id: nameBlock
                width: nameLbl.implicitWidth + 60; height: parent.height; color: con.current.tint
                Label { id: nameLbl; anchors { right: parent.right; rightMargin: 24; bottom: parent.bottom; bottomMargin: 2 } text: con.ui.station; color: "black"; font.pixelSize: 46 }
            }
            Rectangle { id: cap; width: 40; height: parent.height; color: Lc.blue; topRightRadius: 13; bottomRightRadius: 13 }
        }

        // station column
        Column {
            id: column
            x: Lc.pad
            y: topElbow.y + topElbow.height + Lc.gap
            width: Lc.spine
            spacing: Lc.gap
            Repeater {
                model: con.stations
                Pill {
                    required property var modelData
                    width: Lc.spine; height: Lc.pill
                    square: true
                    text: modelData.name
                    sub: Lc.code(modelData.name)
                    tint: con.ui.station === modelData.name ? Lc.orange : modelData.tint
                    onClicked: con.ui.station = modelData.name
                }
            }
        }
        // filler between stations and the release button: coloured blocks with codes
        Column {
            x: Lc.pad; width: Lc.spine
            y: column.y + column.height + Lc.gap
            height: Math.max(0, release.y - Lc.gap - y)
            spacing: Lc.gap
            readonly property var parts: [
                { w: 3, c: Lc.dim }, { w: 1, c: Lc.tan }, { w: 2, c: Lc.lilac }, { w: 1, c: Lc.dim }
            ]
            Repeater {
                model: parent.parts
                Rectangle {
                    required property var modelData
                    required property int index
                    width: Lc.spine
                    height: (parent.height - 3 * Lc.gap) * modelData.w / 7
                    color: modelData.c
                    Label {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 4 }
                        text: Lc.code("fill" + index); color: "black"; font.pixelSize: 14
                        visible: parent.height > 24
                    }
                }
            }
        }
        Pill {
            id: release
            x: Lc.pad
            y: elbow.y - Lc.gap - height
            width: Lc.spine; height: Lc.pill
            square: true
            text: "RELEASE CONSOLE"; labelSize: 17
            sub: Lc.code("release")
            tint: Lc.rose
            onClicked: con.ui.released = true
        }

        // bottom elbow
        Rectangle {
            id: elbow
            opacity: Lc.beat
            x: Lc.pad
            y: parent.height - Lc.pad - height
            width: Lc.spine + 70; height: Lc.bar + 54
            color: Lc.sky
            bottomLeftRadius: 60
            Rectangle {
                // overlaps the outer edge by 1px so no antialiased hairline shows
                x: Lc.spine; y: -1
                width: parent.width - x + 1; height: parent.height - Lc.bar + 1
                color: Lc.black
                bottomLeftRadius: 30
            }
        }
        // bottom bar
        Row {
            x: elbow.x + elbow.width + Lc.gap
            y: elbow.y + elbow.height - Lc.bar
            opacity: Lc.beat
            height: Lc.bar
            spacing: Lc.gap
            readonly property real avail: con.width - x - Lc.pad
            Rectangle { width: 120; height: parent.height; color: Lc.orange
                Label { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: Lc.code(con.ui.station); color: "black"; font.pixelSize: 16 } }
            Rectangle { width: parent.avail - 120 - 180 - 40 - 3 * Lc.gap; height: parent.height; color: Lc.tan }
            Rectangle { width: 180; height: parent.height; color: Lc.blue
                Label { anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter } text: con.ship.live ? "LIVE" : "MOCK DATA"; color: "black"; font.pixelSize: 16 } }
            Rectangle { width: 40; height: parent.height; color: Lc.lilac; topRightRadius: 13; bottomRightRadius: 13 }
        }

        // station content: only the current station is alive (nothing hidden keeps polling)
        Item {
            id: content
            x: column.x + Lc.spine + 30
            y: topElbow.y + con.topBar + 16
            width: con.width - x - Lc.pad
            height: elbow.y + elbow.height - Lc.bar - 24 - y

            Loader {
                id: loader
                anchors.fill: parent
                active: !con.ui.released && !con.stubOnly && con.current.file !== ""
                function applyPage() { if (con.ui.wantPage >= 0 && item && "page" in item) { item.page = con.ui.wantPage; con.ui.wantPage = -1; } }
                function load() { if (con.current.file !== "") setSource(con.current.file, { ship: con.ship }); applyPage(); }
                Component.onCompleted: load()
                Connections { target: con; function onCurrentChanged() { loader.load(); } }
                Connections { target: con.ui; function onWantPageChanged() { loader.applyPage(); } }
            }
            Label {
                visible: con.current.file === ""
                anchors.centerIn: parent
                text: con.current.name + " OFFLINE: COMING IN A LATER PHASE"
                color: Lc.lilac; font.pixelSize: 30
            }
        }
    }
}
