import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import QtQuick
import "."

// Password prompt for pkexec, inside LCARS only. Only instantiated by Lcars.qml (never dev/snap),
// so the polkit agent exists exactly while LCARS is on. One window on the monitor that was focused
// when the request started; Enter submits, Esc cancels, 60s of nothing cancels.
Scope {
    id: ap
    required property var agent                 // PolkitAgent
    readonly property var flow: agent.flow
    property string target: ""

    Connections {
        target: ap.agent
        function onAuthenticationRequestStarted() { ap.target = Hyprland.focusedMonitor?.name ?? ""; }
    }
    readonly property string shownOn: Quickshell.screens.some(s => s.name === target) ? target : (Quickshell.screens[0]?.name ?? "")

    function cancel() { if (agent.isActive && flow) flow.cancelAuthenticationRequest(); }
    Component.onDestruction: cancel()
    // focus the input whenever a response is wanted (a retry after a wrong password re-asks without re-showing the window)
    Connections {
        target: ap.flow
        function onIsResponseRequiredChanged() { if (ap.flow?.isResponseRequired) ap.focusInput(); }
    }
    signal focusInput()
    Timer { interval: 60000; running: ap.agent.isActive; onTriggered: ap.cancel() }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "#d0000000"
            visible: ap.agent.isActive && modelData.name === ap.shownOn
            WlrLayershell.namespace: "lcars-auth"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            onVisibleChanged: if (visible) { input.text = ""; input.forceActiveFocus(); }
            Connections { target: ap; function onFocusInput() { input.forceActiveFocus(); } }
            Item { anchors.fill: parent; focus: true; Keys.onEscapePressed: ap.cancel() }   // Esc cancels even when the input lacks focus

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(760, parent.width - 80); height: col.implicitHeight + 150
                color: Lc.black
                Rectangle { id: topBar; width: parent.width; height: 56; color: Lc.orange; topLeftRadius: 28
                    Label { anchors { right: parent.right; rightMargin: 24; bottom: parent.bottom; bottomMargin: 2 } text: "AUTHORISATION REQUIRED"; color: "black"; font.pixelSize: 38 }
                    Label { anchors { left: parent.left; leftMargin: 40; bottom: parent.bottom; bottomMargin: 4 } text: Lc.code("auth"); color: "black"; font.pixelSize: 18 }
                }
                Rectangle { y: topBar.height + 6; width: 28; height: parent.height - y; color: Lc.lilac; bottomLeftRadius: 28 }
                Column {
                    id: col
                    x: 52; y: topBar.height + 24
                    width: parent.width - 52 - 28
                    spacing: 14
                    Label { width: parent.width; wrapMode: Text.WordWrap; text: String(ap.flow?.message ?? "").toUpperCase(); color: Lc.peach; font.pixelSize: 28 }
                    Label { width: parent.width; wrapMode: Text.WordWrap; visible: text !== ""; text: String(ap.flow?.actionId ?? "").toUpperCase(); color: Lc.tan; font.pixelSize: 16 }
                    Label {
                        width: parent.width; wrapMode: Text.WordWrap
                        visible: text !== ""
                        text: String(ap.flow?.supplementaryMessage ?? "").toUpperCase()
                        color: ap.flow?.supplementaryIsError ? Lc.red : Lc.sky; font.pixelSize: 22
                    }
                    Label { visible: input.visible; text: String(ap.flow?.inputPrompt ?? "PASSWORD").toUpperCase(); color: Lc.lilac; font.pixelSize: 20 }
                    Rectangle {
                        visible: ap.flow?.isResponseRequired ?? false
                        width: parent.width; height: 56; radius: 28; color: Lc.track
                        border.width: 3; border.color: Lc.orange
                        TextInput {
                            id: input
                            anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: ap.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                            color: Lc.peach; font.family: Lc.font; font.pixelSize: 28
                            passwordCharacter: "*"
                            clip: true
                            onAccepted: win.submit()
                            Keys.onEscapePressed: ap.cancel()
                        }
                    }
                    Row {
                        spacing: 12
                        Pill { text: "AUTHORISE"; tint: Lc.green; height: 56; labelSize: 22; onClicked: win.submit() }
                        Pill { text: "DENY"; tint: Lc.rose; height: 56; labelSize: 22; onClicked: ap.cancel() }
                    }
                }
            }
            function submit() {
                if (!ap.flow || !(ap.flow.isResponseRequired)) return;
                ap.flow.submit(input.text);
                input.text = "";
            }
        }
    }
}
