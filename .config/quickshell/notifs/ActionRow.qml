import QtQuick
import "../common"

// A notification's action buttons. Lives here rather than inline in the toast
// because the center needs the same thing: if you miss a toast, its actions
// used to go with it — the center rendered summary and body and nothing else.
//
// A record restored from disk has no live Notification behind it, so `actions`
// is empty and the whole row folds away. That is the honest outcome: the
// invoke() would have gone to a process that is no longer listening.
Row {
    id: root

    property var actions: []

    spacing: 8
    topPadding: 6
    visible: (actions?.length ?? 0) > 0

    Repeater {
        model: root.actions ?? []

        Rectangle {
            required property var modelData

            radius: 7
            color: hover.hovered ? Theme.surface : Theme.track
            implicitWidth: at.implicitWidth + 24
            implicitHeight: at.implicitHeight + 6

            Text {
                id: at
                anchors.centerIn: parent
                text: parent.modelData.text
                font.family: Theme.font
                font.pixelSize: 11
                color: Theme.bright
            }
            HoverHandler { id: hover }
            MouseArea {
                anchors.fill: parent
                onClicked: parent.modelData.invoke()
            }
        }
    }
}
