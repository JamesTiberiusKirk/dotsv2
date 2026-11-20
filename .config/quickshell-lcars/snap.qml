import Quickshell
import Quickshell.Wayland
import QtQuick
import "."

// Dev tool: renders the console with fake data on the BACKGROUND layer (behind
// all windows), saves a PNG to $LCARS_SNAP, then quits. For checking the look
// without putting anything in front of the user.
//   LCARS_SNAP=/path/out.png LCARS_STATION=BRIDGE LCARS_PAGE=0 qs -p ~/.config/quickshell-lcars/snap.qml
ShellRoot {
    // LCARS_VIEW=console (default) | top | both (top above console, 30px hinge gap) | docked (top + fallback panel)
    // LCARS_ALERT=1 red alert palette, LCARS_AUTH=1 privileged pills live (mock)
    readonly property string view: Quickshell.env("LCARS_VIEW") || "console"
    Component.onCompleted: {
        if (!Quickshell.env("LCARS_SNAP")) {
            console.log("usage: LCARS_SNAP=/path/out.png [LCARS_STATION=BRIDGE LCARS_PAGE=0 LCARS_RELEASED=1 LCARS_VIEW=console|top|both|docked LCARS_ALERT=1 LCARS_AUTH=1] qs -p snap.qml");
            Qt.quit();
        } else if (["console", "top", "both", "docked", "desk"].indexOf(view) < 0) {
            console.log("unknown LCARS_VIEW", view);
            Qt.quit();
        }
    }
    ConsoleState {
        id: uiState
        station: Quickshell.env("LCARS_STATION") || "BRIDGE"
        released: Quickshell.env("LCARS_RELEASED") === "1"
        screenPresent: view !== "docked"
        panelOpen: view === "docked"
    }
    readonly property bool wantTop: view !== "console"
    readonly property bool wantCon: view !== "top" && view !== "docked" && view !== "desk"
    Binding { target: Lc; property: "alert"; value: Quickshell.env("LCARS_ALERT") === "1"; when: Quickshell.env("LCARS_ALERT") === "1" }
    FakeData {
        id: fake
        Component.onCompleted: {
            if (Quickshell.env("LCARS_BANNER") === "1") { confirmKind = "scale"; confirmLeft = 11; confirmText = "EDP-1 SCALE 2"; }
            if (Quickshell.env("LCARS_ALERT") === "1") alert = "RED ALERT: WARP CORE";
            if (Quickshell.env("LCARS_AUTH") === "1") authReady = true;
        }
    }
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true }
        implicitWidth: 1800
        implicitHeight: (wantTop && wantCon ? 2 * 1125 + 30 : 1125)
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "lcars-snap"

        Item {
            id: all
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "black" }
            TopFrame {
                visible: wantTop
                x: 0; y: 0; width: 1800; height: 1125
                ship: fake; ui: uiState
            }
            StationPanel {
                visible: view === "docked"
                x: 76; y: 72; width: Math.min(1100, 1800 - 92); height: 1125 - 72 - 20
                ship: fake; ui: uiState
            }
            DeskInfo {
                visible: view === "desk"
                x: 0; y: 0; width: 1800; height: 1125
                ship: fake; topInset: Lc.pad + Lc.topBar
            }
            Console {
                id: c
                visible: wantCon
                x: 0; y: wantTop ? 1155 : 0; width: 1800; height: 1125
                ship: fake
                ui: uiState
                Component.onCompleted: pageTimer.start()
            }
        }
        Timer {
            id: pageTimer
            interval: 400
            onTriggered: {
                const p = Number(Quickshell.env("LCARS_PAGE") || 0);
                const st = findStation(all);
                if (st) { st.page = p; if (st.sub !== undefined) st.sub = Number(Quickshell.env("LCARS_SUB") || 0); }
                snapTimer.start();
            }
            function findStation(it) {
                if (it.page !== undefined && it.ship !== undefined) return it;
                for (const ch of it.children) { const r = findStation(ch); if (r) return r; }
                return null;
            }
        }
        Timer {
            id: snapTimer
            interval: 600
            onTriggered: { all.grabToImage(r => { r.saveToFile(Quickshell.env("LCARS_SNAP")); Qt.quit(); }); giveUp.start(); }
        }
        // a grab that never calls back used to hang the tool for good: say so and leave
        Timer { id: giveUp; interval: 8000; onTriggered: { console.log("snap: grabToImage never called back"); Qt.quit(); } }
    }
}
