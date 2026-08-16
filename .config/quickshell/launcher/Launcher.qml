import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import "../common"

// App launcher (wofi drun replacement) + dmenu mode for scripts.
// Toggle apps:  qs ipc call launcher toggle
// Dmenu:        ~/.scripts/qsmenu --prompt "..."  (feeds stdin, blocks on a
//               fifo until a selection — or "" on cancel — is written back)
PanelWindow {
    id: root

    visible: false
    implicitWidth: 430
    implicitHeight: 320
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property bool dmenu: false
    property string dmenuPrompt: ""
    property string dmenuOut: ""
    property var dmenuItems: []

    onVisibleChanged: {
        if (visible) {
            query.text = "";
            list.currentIndex = 0;
            query.forceActiveFocus();
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (root.visible)
                root.finish(null);
            else
                root.visible = true;
        }
    }
    IpcHandler {
        target: "dmenu"
        function open(prompt: string, inFile: string, outFile: string): void {
            if (root.visible)
                root.finish(null);
            root.dmenuPrompt = prompt;
            root.dmenuOut = outFile;
            reader.command = ["cat", inFile];
            reader.running = true;
        }
    }
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                root.dmenuItems = text.split("\n").filter(l => l.trim() !== "");
                root.dmenu = true;
                root.visible = true;
            }
        }
    }

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property var matches: {
        const q = query.text.toLowerCase();
        if (dmenu) {
            return q === "" ? dmenuItems
                            : dmenuItems.filter(l => l.toLowerCase().includes(q));
        }
        if (q === "")
            return apps;
        const starts = [], contains = [];
        for (const a of apps) {
            const n = a.name.toLowerCase();
            if (n.startsWith(q)) starts.push(a);
            else if (n.includes(q)) contains.push(a);
        }
        return starts.concat(contains);
    }

    // Close the window; sel is a dmenu line, or null for cancel / app mode.
    function finish(sel) {
        if (dmenu && dmenuOut !== "") {
            // unblock the qsmenu client waiting on the fifo
            Quickshell.execDetached(["sh", "-c", 'printf %s "$0" > "$1"', sel ?? "", dmenuOut]);
        }
        dmenu = false;
        dmenuOut = "";
        dmenuItems = [];
        visible = false;
    }

    function activate() {
        const m = matches[list.currentIndex];
        if (m === undefined)
            return;
        if (dmenu) {
            finish(m);
        } else {
            m.execute();
            finish(null);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.surface
        border.color: Theme.islandBorder
        border.width: 1

        TextInput {
            id: query

            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            height: 24
            font.family: Theme.font
            font.pixelSize: 13
            color: Theme.bright
            clip: true
            onTextChanged: list.currentIndex = 0

            Keys.onEscapePressed: root.finish(null)
            Keys.onReturnPressed: root.activate()
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onUpPressed: list.decrementCurrentIndex()

            Text {
                visible: query.text === ""
                text: root.dmenu ? root.dmenuPrompt : "search apps…"
                font: query.font
                color: Theme.dim
            }
        }
        Rectangle {
            id: divider
            anchors { top: query.bottom; left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14; topMargin: 4 }
            height: 1
            color: Theme.track
        }

        ListView {
            id: list

            anchors { top: divider.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
            clip: true
            model: root.matches
            highlightMoveDuration: 60

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: 30
                radius: 8
                color: list.currentIndex === index ? Qt.alpha(Theme.accent, 0.13) : "transparent"

                IconImage {
                    id: aicon
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    implicitSize: 18
                    visible: !root.dmenu && String(source) !== ""
                    source: root.dmenu ? "" : Quickshell.iconPath(modelData.icon, true)
                }
                Text {
                    anchors { left: parent.left; leftMargin: root.dmenu ? 8 : 34; right: side.left; verticalCenter: parent.verticalCenter }
                    text: root.dmenu ? modelData : modelData.name
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    color: list.currentIndex === index ? Theme.bright : Theme.text
                }
                Text {
                    id: side
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: root.dmenu ? "" : (modelData.genericName || "")
                    font.family: Theme.font
                    font.pixelSize: 10
                    color: Theme.dim
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { list.currentIndex = index; root.activate(); }
                }
            }
        }
    }
}
