import QtQuick
import "../../common"

// ---- jobs popout (click the jobs cell) ----
// One card per cron job (common/Jobs.qml): status dot, name, schedule, last
// and next run, run-now button. Click a card for the last log lines.
Popout {
    id: jp

    panelName: "jobs"
    implicitWidth: 360
    rowSpacing: 8

    // Jobs.jobs is republished every poll; cards are keyed by index so hover and
    // animations survive, and the expanded card is kept by name
    property string expanded: ""

    function dotColor(s) {
        return s === "ok" ? Theme.ok : s === "failed" ? Theme.urgent : s === "running" ? Theme.warn : Theme.dim;
    }

    Text {
        visible: Jobs.count === 0
        text: "no jobs"
        font.family: Theme.font; font.pixelSize: 13
        color: Theme.dim
    }

    Repeater {
        model: Jobs.count
        Rectangle {
            id: card
            required property int index
            readonly property var job: Jobs.jobs[index] ?? ({ name: "", sched: "", status: "", last: 0, next: "", code: "", desc: "", log: [] })
            readonly property bool open: jp.expanded === job.name
            width: jp.contentWidth
            height: head.height + (open ? logText.height + 18 : 0) + 16
            radius: 10
            color: Theme.track
            clip: true

            MouseArea {
                anchors.fill: parent
                onClicked: jp.expanded = card.open ? "" : card.job.name
            }

            Item {
                id: head
                x: 10; y: 8
                width: parent.width - 20
                height: card.job.desc ? 48 : 34

                Rectangle {
                    id: dot
                    width: 9; height: 9; radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: jp.dotColor(card.job.status)
                    SequentialAnimation on opacity {
                        running: card.job.status === "running"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }
                Column {
                    anchors { left: dot.right; leftMargin: 10; right: runBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width
                        text: card.job.name + "  ·  " + card.job.sched
                        font.family: Theme.font; font.pixelSize: 13; font.bold: true
                        color: Theme.bright
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: card.job.desc !== ""
                        width: parent.width
                        text: card.job.desc
                        font.family: Theme.font; font.pixelSize: 11
                        color: Theme.dim
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: (card.job.status === "running" ? "running now"
                              : card.job.status === "failed" ? "failed " + Jobs.ago(card.job.last)
                                  + (card.job.code !== "" ? " (exit " + card.job.code + ")" : " (died)")
                              : card.job.status === "never" ? "never run"
                              : Jobs.ago(card.job.last)) + "  ·  next " + card.job.next
                        font.family: Theme.font; font.pixelSize: 11
                        color: card.job.status === "failed" ? Theme.urgent : Theme.dim
                        elide: Text.ElideRight
                    }
                }
                Icon {
                    id: runBtn
                    name: "play"; size: 16
                    color: card.job.status === "running" ? Theme.track : (runArea.containsMouse || activeFocus ? Theme.bright : Theme.dim)
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    activeFocusOnTab: true
                    Keys.onReturnPressed: if (card.job.status !== "running") Jobs.runNow(card.job)
                    MouseArea {
                        id: runArea
                        anchors { fill: parent; margins: -6 }
                        hoverEnabled: true
                        onClicked: if (card.job.status !== "running") Jobs.runNow(card.job)
                    }
                }
            }

            Text {
                id: logText
                visible: card.open
                x: 10; y: head.height + 14
                width: parent.width - 20
                text: card.job.log.length ? card.job.log.join("\n") : "no log"
                wrapMode: Text.WrapAnywhere
                font.family: Theme.font; font.pixelSize: 10
                color: Theme.text
            }
        }
    }
}
