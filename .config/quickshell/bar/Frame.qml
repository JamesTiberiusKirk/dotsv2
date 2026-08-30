import Quickshell
import Quickshell.Wayland
import QtQuick
import "../common"

// Space reservation for the screen bezel on the three edges the bar is not
// on. Nothing is painted here: the whole chrome is one shape in Chrome.qml.
Variants {
    model: Quickshell.screens

    delegate: Scope {
        id: scope

        required property var modelData

        // Invisible windows so the visible chrome can ignore every exclusive
        // zone and reach the screen corners.
        component Reserver: PanelWindow {
            property string edge
            screen: scope.modelData
            visible: ShellState.side !== edge
            anchors { top: edge !== "bottom"; bottom: edge !== "top"; left: edge !== "right"; right: edge !== "left" }
            implicitWidth: Theme.frameT
            implicitHeight: Theme.frameT
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: Theme.frameT
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "quickshell-frame"
        }

        Reserver { edge: "top" }
        Reserver { edge: "bottom" }
        Reserver { edge: "left" }
        Reserver { edge: "right" }
    }
}
