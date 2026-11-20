import Quickshell
import QtQuick
import "."

// Dev copy: run as its own process with
//   qs -p ~/.config/quickshell-lcars/dev.qml
// Opens the console as a normal window (park it on a spare workspace).
// Fake data only. Never import the real common/ here: Sys.qml pulls in
// Notifs.qml, whose NotificationServer would fight the real shell for the bus.
ShellRoot {
    FloatingWindow {
        id: win
        title: "LCARS DEV"
        implicitWidth: 1440
        implicitHeight: 900
        color: "black"
        ConsoleState { id: uiState }
        FakeData { id: fake }
        ComputerIpc { ship: fake; ui: uiState }
        // TEST ONLY, exists in this dev window and nowhere else: LCARS_DEV_ANSWER=allow|deny|always answers every pending card after 1 s,
        // standing in for the tap. The live shell (Lcars.qml) has nothing like it.
        Timer {
            interval: 1000; repeat: true; running: Quickshell.env("LCARS_DEV_ANSWER") !== ""
            onTriggered: { for (const id of Object.keys(fake.computer.asks)) if (fake.computer.asks[id] === "pending") fake.computer.settle(id, Quickshell.env("LCARS_DEV_ANSWER")); }
        }
        // F2 (or tapping the corner) flips between the console and the top-screen frame preview
        property bool showTop: false
        Shortcut { sequence: "F2"; onActivated: win.showTop = !win.showTop }
        Console { anchors.fill: parent; visible: !win.showTop; ship: fake; ui: uiState }
        TopFrame { anchors.fill: parent; visible: win.showTop; ship: fake; ui: uiState }
        MouseArea { x: parent.width - 30; width: 30; height: 30; onClicked: win.showTop = !win.showTop }
    }
}
