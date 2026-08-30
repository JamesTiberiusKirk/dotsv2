import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import "../common"

// Transient notification popups, top-right. Critical urgency sticks until
// clicked; everything else times out (Notifs singleton owns the list).
PanelWindow {
    id: root

    // Fixed size, mapped once, never reconfigured. The surface used to be
    // exactly the height of the stack and resize for every card that came or
    // went — and each resize is a configure round-trip during which the
    // compositor briefly has a surface with no matching buffer, so the whole
    // stack blinked out and back. A full-height strip never resizes: only its
    // contents move. Nor does it unmap: the strip is transparent and takes no
    // input outside the cards (see mask), so there is nothing to gain by
    // hiding it and a remap to lose.
    visible: true
    // follow the focused monitor instead of whatever screen is first
    screen: [...Quickshell.screens].find(s => s.name === Hyprland.focusedMonitor?.name)
            ?? Quickshell.screens[0]
    anchors { top: true; right: true; bottom: true }
    margins { top: Theme.barBody + Theme.popoutGap; right: 12 }
    implicitWidth: 320
    // The strip is transparent below the cards but it is still an Overlay
    // surface; without this it would eat every click in the column beneath
    // them. Sized to the live content rather than the visible cards, so a
    // card sliding out stops taking input the moment it leaves the model.
    mask: Region {
        x: 0; y: 0
        width: root.width
        height: list.contentHeight
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifs"

    // ListView rather than a Column of Repeater items: a Repeater destroys a
    // delegate the instant it leaves the model, so there is nothing left to
    // animate out. ListView holds a removed item alive for the duration of its
    // remove transition, which is the only reason the exit exists.
    ListView {
        id: list

        anchors.fill: parent
        spacing: 8
        clip: true
        // wheel and drag belong to the toasts themselves, not to the stack
        interactive: false

        model: ScriptModel {
            objectProp: "key"
            values: Notifs.popups
        }

        // No `add:` transition. A ViewTransition is skipped when the view is
        // not visible at the moment of insertion, and this window only maps
        // once the first popup exists — so the entry animation never ran once,
        // which is exactly what a probe in the transition showed: it was never
        // reached. The delegate animates itself in instead (`intro` below),
        // which does not care when the surface appeared. Removal is different:
        // the view is on screen by then, and only ListView can keep a removed
        // item alive long enough to animate at all.
        remove: Transition {
            // Pure slide, no fade. Travelling out to x = width puts the card
            // fully past the surface edge, so it is already gone by the time it
            // would need hiding — a fade on top just made it look smeared.
            NumberAnimation { property: "x"; to: list.width; duration: 200; easing.type: Easing.InCubic }
        }
        // the stack closing up after one in the middle leaves — without it the
        // survivors jump into the gap
        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: 240; easing.type: Easing.OutCubic }
        }

        delegate: Rectangle {
            id: card

            required property var modelData
            readonly property var n: modelData.n

            width: list.width
            // Off-screen start is x = width, not a negative margin: at that
            // offset the card sits just past the surface edge and is clipped,
            // so it comes in from the right without the window needing to be
            // wider than the toast to hide it beforehand.
            x: list.width
            Component.onCompleted: intro.start()
            NumberAnimation {
                id: intro
                target: card
                property: "x"
                to: 0
                duration: 280
                easing.type: Easing.OutCubic
            }
            implicitHeight: Math.max(inner.implicitHeight, nicon.visible ? 32 : 0) + 24
            radius: 12
            color: Theme.surface
            border.color: n?.urgency === 2 ? Theme.urgent : Theme.islandBorder
            border.width: 1

            MouseArea {
                anchors.fill: parent
                // hide, not dismiss — dismiss() drops it from history too
                onClicked: Notifs.hidePopup(n)
            }

            IconImage {
                id: nicon
                anchors { left: parent.left; top: parent.top; margins: 12 }
                implicitSize: 32
                // A sender can pass a temp file and delete it once the
                // notification is out (satty does), so a path that was fine on
                // arrival fails to load later. Fold the slot away rather than
                // show the error placeholder.
                visible: String(source) !== "" && status !== Image.Error
                // picture first; if that file is gone, the app icon
                readonly property string pic: Notifs.imageSource(n?.image)
                readonly property string fallback: Notifs.appIconSource(n?.appIcon, n?.appName)
                property bool picFailed: false
                onStatusChanged: if (status === Image.Error && String(source) === pic) picFailed = true
                source: (pic && !picFailed) ? pic : fallback
            }

            Column {
                id: inner
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                anchors.leftMargin: nicon.visible ? 54 : 12
                spacing: 3

                Text {
                    text: (n?.appName ?? "").toUpperCase()
                    font.family: Theme.font; font.pixelSize: 10
                    font.letterSpacing: 0.5
                    color: Theme.dim
                    visible: text !== ""
                }
                Text {
                    width: parent.width
                    text: n?.summary ?? ""
                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                    color: Theme.bright
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    text: n?.body ?? ""
                    visible: text !== ""
                    font.family: Theme.font; font.pixelSize: Theme.fontSize
                    color: Theme.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                }
                ActionRow { actions: n?.actions ?? [] }
            }
        }
    }
}
