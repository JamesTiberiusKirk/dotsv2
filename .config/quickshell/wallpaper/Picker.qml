import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import "../common"

// Wallpaper picker — a horizontal strip, the centre slot is the pick.
// Toggle: qs ipc call wallpaper toggle (SUPER+W, and the `wallpaper` menu row).
// Applying goes back out through ~/.scripts/menu/common/wallpaper.sh so the
// transition config, the awww daemon spawn and the cycler's index all stay in
// one place — this window only decides *which* file.
PanelWindow {
    id: root

    visible: false
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/wallpapers"
    readonly property string script: Quickshell.env("HOME") + "/.scripts/menu/common/wallpaper.sh"

    readonly property int slotW: 440
    readonly property int slotH: 275

    // ground truth for where to open the strip — the index state file only
    // tracks the cycler, and awww is what is actually on screen
    property string current: ""
    Process {
        id: currentProc
        command: ["sh", "-c", "awww query 2>/dev/null | sed -n 's/.*currently displaying: image: //p' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.current = text.trim();
                root.centreOnCurrent();
            }
        }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.visible = !root.visible; }
    }

    onVisibleChanged: {
        if (!visible) return;
        currentProc.running = true;
        view.forceActiveFocus();
    }

    // FolderListModel fills asynchronously, so this runs from both the query
    // returning and the model settling — whichever lands last wins
    function centreOnCurrent() {
        for (let i = 0; i < folder.count; i++) {
            if (folder.get(i, "filePath") === root.current) {
                view.currentIndex = i;
                view.positionViewAtIndex(i, ListView.Center);
                return;
            }
        }
    }

    function apply(path) {
        Quickshell.execDetached([root.script, path]);
        root.current = path;
        root.visible = false;
    }

    FolderListModel {
        id: folder
        showDirs: false
        sortField: FolderListModel.Name
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        // set once and left alone — it watches the directory itself, and
        // reassigning it would throw away every decoded thumbnail
        folder: "file://" + root.dir
        onCountChanged: root.centreOnCurrent()
    }

    // Click-off. Nothing painted: the scrim's dim never reached the screen —
    // hyprglass discards sub-threshold pixels rather than just leaving them
    // un-glassed, so the 0.4 black was culled and only this survived.
    MouseArea {
        anchors.fill: parent
        onClicked: root.visible = false
    }

    Item {
        anchors.fill: parent
        opacity: root.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        // The glass band. Its alpha is the whole trick: Theme.surface is 0.85,
        // which leaves so little of hyprglass's blurred backdrop showing that
        // the glass reads as a flat slab. Set here rather than on the theme —
        // the OSD and every island share that colour and want it opaque.
        // Clips so the strip runs out to the radius instead of off the display.
        ClippingRectangle {
            id: band

            anchors {
                left: parent.left; right: parent.right
                leftMargin: 32; rightMargin: 32
                verticalCenter: parent.verticalCenter
            }
            height: col.implicitHeight + 36
            radius: 22
            color: Qt.alpha(Theme.surface, 0.65)
            border.width: 1
            border.color: Theme.islandBorder

            Column {
                id: col

                anchors.centerIn: parent
                width: parent.width
                spacing: 14

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 7

                    Icon {
                        name: "image-multiple"
                        color: Theme.dim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "wallpaper   \u2190 \u2192   enter to apply"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize
                        color: Theme.dim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    id: view

                    width: parent.width
                    // just enough slack for the centred slot's 2px border —
                    // delegates top-align, so anything more is dead space that
                    // pushes the filename away from the strip
                    height: root.slotH + 12
                    orientation: ListView.Horizontal
                    model: folder
                    focus: true
                    spacing: 24

                    // snap the centre slot: the selection *is* whatever sits in the middle
                    preferredHighlightBegin: width / 2 - root.slotW / 2
                    preferredHighlightEnd: width / 2 + root.slotW / 2
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    snapMode: ListView.SnapOneItem
                    // decode a few slots either side up front, so arrowing along the
                    // strip doesn't wait on a 3600px jpeg each step
                    cacheBuffer: root.slotW * 8
                    highlightMoveDuration: 220
                    // the strip is the whole band width, so leaving flicking on lets a
                    // stray drag anywhere fling it; wheel and keys drive it instead
                    interactive: false

                    Keys.onEscapePressed: root.visible = false
                    // Every step goes through step() so it wraps. The arrows would
                    // otherwise be handled by the ListView itself, which stops dead
                    // at both ends — hence intercepting them here rather than
                    // letting them fall through.
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_J || event.key === Qt.Key_Right) { view.step(1); event.accepted = true; }
                        else if (event.key === Qt.Key_K || event.key === Qt.Key_Left) { view.step(-1); event.accepted = true; }
                    }

                    // Wrapping past either end jumps rather than scrolling: with
                    // StrictlyEnforceRange, walking from the last slot to the first
                    // animates the whole strip past you, which reads as a glitch
                    // rather than as a wrap.
                    function step(d) {
                        if (count === 0)
                            return;
                        const next = (currentIndex + d + count) % count;
                        if (Math.abs(next - currentIndex) > 1)
                            positionViewAtIndex(next, ListView.Center);
                        currentIndex = next;
                    }
                    Keys.onReturnPressed: root.applyCurrent()
                    Keys.onEnterPressed: root.applyCurrent()

                    WheelHandler {
                        onWheel: event => {
                            view.step(event.angleDelta.y < 0 || event.angleDelta.x > 0 ? 1 : -1);
                        }
                    }

                    delegate: Item {
                        id: cell

                        required property int index
                        required property string filePath
                        required property string fileName

                        width: root.slotW
                        height: root.slotH

                        // 0 at dead centre, 1 at the edge of the band — drives the
                        // slice: neighbours shrink toward the edges so the middle reads as the pick
                        readonly property real t: Math.min(1, Math.abs(
                            x + width / 2 - (view.contentX + view.width / 2)) / (view.width / 2))
                        readonly property bool centred: cell.index === view.currentIndex

                        // size alone does the slicing — fading the neighbours made them
                        // read as disabled rather than just off-centre
                        scale: 1 - 0.34 * t
                        z: -t

                        ClippingRectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Theme.track
                            border.width: cell.centred ? 2 : 0
                            border.color: cell.filePath === root.current ? Theme.accent : Theme.bright

                            Image {
                                anchors.fill: parent
                                anchors.margins: parent.border.width
                                source: "file://" + cell.filePath
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 700   // slot is 440 logical px; decoding
                                                        // the full 3600px original is the
                                                        // second you were waiting on
                                // an 18MB png takes a beat to decode; fade rather than pop
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }
                        }

                        TapHandler {
                            // off-centre click centres it, a second click applies —
                            // so you never apply something you can't see properly
                            onTapped: cell.centred ? root.apply(cell.filePath)
                                                   : view.currentIndex = cell.index
                        }
                    }
                }

                // name of whatever is currently centred
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: view.currentItem ? view.currentItem.fileName : ""
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 2
                    color: Theme.bright
                }
            }
        }
    }

    function applyCurrent() {
        if (view.currentItem)
            root.apply(view.currentItem.filePath);
    }
}
