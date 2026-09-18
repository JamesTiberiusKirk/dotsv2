import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts
import "../../common"

// ---- clanker panel (click the robot cell) ----
// omarchy's agents panel, in this bar's idiom: tab chips per
// agent, plan line, limit meters with reset countdowns, then
// tokens by day and by model. Hover a token row for the split.
Popout {
    id: clankerPanel

    panelName: "clanker"
    iconName: "robot"
    implicitWidth: 340
    // the cell and the menu row are both gated on having an agent
    available: Clanker.agents.length > 0

    readonly property var a: Clanker.agent

    // The chips pick an agent rather than switch a view, so the base's tab
    // state and Clanker's selection have to track each other. Both sides
    // compare before they assign, which is what stops the two handlers
    // bouncing the selection back and forth forever.
    // Empty below two agents, so a single-agent setup draws no chips, as before.
    function agentLabel(x) { return x ? (x.name || x.id) : ""; }
    tabs: Clanker.agents.length > 1 ? Clanker.agents.map(x => clankerPanel.agentLabel(x)) : []
    onCurrentTabChanged: {
        const m = Clanker.agents.find(x => clankerPanel.agentLabel(x) === clankerPanel.currentTab);
        if (m && m.id !== (clankerPanel.a ? clankerPanel.a.id : "")) Clanker.select(m.id);
    }
    Connections {
        target: Clanker
        function onAgentChanged() {
            const l = clankerPanel.agentLabel(Clanker.agent);
            if (l !== "" && l !== clankerPanel.currentTab) clankerPanel.currentTab = l;
        }
    }

    // label left, bar + value right; hover text swaps the value
    component TokenRow: Item {
        property string label
        property real value       // 0..1 of the heaviest row
        property string detail
        property string hover: ""
        property bool bold: false
        signal tapped()
        width: clankerPanel.contentWidth
        height: 16
        activeFocusOnTab: true
        Keys.onReturnPressed: tapped()
        Rectangle {
            anchors { fill: parent; margins: -2 }
            radius: 5
            color: parent.activeFocus ? Theme.track : "transparent"
        }
        Text {
            text: label
            font.family: Theme.font; font.pixelSize: 11; font.bold: bold
            color: Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            anchors { right: tvalue.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 90; height: 4; radius: 2
            color: Theme.track
            Rectangle { width: parent.width * Math.max(0, Math.min(1, value)); height: parent.height; radius: 2; color: Theme.accent }
        }
        Text {
            id: tvalue
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: (tHover.containsMouse || parent.activeFocus) && hover !== "" ? hover : detail
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.dim
        }
        MouseArea { id: tHover; anchors.fill: parent; hoverEnabled: true; onClicked: parent.tapped() }
    }
    component SectionHead: Text {
        font.family: Theme.font; font.pixelSize: 10
        color: Theme.dim
        topPadding: 4
    }

    // hero: name + plan, or the auth problem in its place
    Item {
        width: clankerPanel.contentWidth; height: 30
        Icon { id: heroIcon; name: clankerPanel.a ? "agent-" + clankerPanel.a.id : "robot"; size: 22; color: Theme.bright; anchors.verticalCenter: parent.verticalCenter }
        Column {
            anchors { left: heroIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            Text {
                text: clankerPanel.a ? clankerPanel.a.name : ""
                font.family: Theme.font; font.pixelSize: 13; font.bold: true
                color: Theme.bright
            }
            Text {
                readonly property string status: clankerPanel.a ? (clankerPanel.a.usageStatusText || "") : ""
                text: status !== "" ? status : (clankerPanel.a ? (clankerPanel.a.tierLabel || "") : "")
                font.family: Theme.font; font.pixelSize: 11
                color: status !== "" ? Theme.warn : Theme.dim
            }
        }
        Icon {
            name: "refresh"; size: 14; color: activeFocus ? Theme.bright : Theme.dim
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            activeFocusOnTab: true
            Keys.onReturnPressed: Clanker.refresh()
            MouseArea { anchors.fill: parent; onClicked: Clanker.refresh() }
        }
    }

    // limits could not be fetched: say how to fix it
    Rectangle {
        readonly property string help: clankerPanel.a && clankerPanel.a.usageStatusText ? (clankerPanel.a.authHelpText || "") : ""
        visible: help !== ""
        width: clankerPanel.contentWidth; height: helpText.height + 12; radius: 6
        color: Theme.track
        Text {
            id: helpText
            x: 8; y: 6; width: parent.width - 16
            text: parent.help
            wrapMode: Text.WordWrap
            font.family: Theme.font; font.pixelSize: 11
            color: Theme.warn
        }
    }

    // limits: % of each allowance and the time to reset;
    // click a row to pin it as the bar cell's stat (bold = pinned)
    Repeater {
        model: clankerPanel.a ? (clankerPanel.a.limits || []) : []
        TokenRow {
            required property var modelData
            required property int index
            readonly property real pct: Number(modelData.percent)
            readonly property string reset: Clanker.untilText(modelData.resetsAt)
            label: modelData.title || modelData.label
            bold: index === Clanker.limitIndex
            value: pct
            detail: (pct >= 0 ? Math.round(pct * 100) + "%" : "--") + (reset !== "" ? "  ·  " + reset : "")
            onTapped: Clanker.selectLimit(index)
        }
    }

    // prepaid agents report a balance instead of limits
    TokenRow {
        readonly property var b: clankerPanel.a ? clankerPanel.a.balance : null
        visible: !!b
        label: "balance"
        value: b && b.funded > 0 ? b.remaining / b.funded : 0
        detail: b ? b.remaining.toFixed(2) + " " + (b.currency || "") + (b.estimated ? " ~" : "") : ""
        hover: b ? b.spent.toFixed(2) + " of " + b.funded.toFixed(2) + " spent" : ""
    }

    // tokens by day, last week, today bold at the bottom
    SectionHead {
        visible: dayRep.count > 0
        readonly property var hosts: clankerPanel.a ? (clankerPanel.a.hosts || []) : []
        text: "tokens by day" + (hosts.length > 1 ? "  ·  " + hosts.join(" + ") : "")
    }
    Repeater {
        id: dayRep
        readonly property var days: clankerPanel.a ? (clankerPanel.a.recentDays || []) : []
        readonly property real peak: days.reduce((m, d) => Math.max(m, Number(d.messageCount) || 0), 0)
        model: days
        TokenRow {
            required property var modelData
            required property int index
            readonly property bool today: modelData.date === Clanker.todayStr()
            label: new Date(modelData.date + "T00:00").toLocaleDateString(Qt.locale(), "ddd d")
            bold: today
            value: dayRep.peak > 0 ? (Number(modelData.messageCount) || 0) / dayRep.peak : 0
            detail: Clanker.tokText(modelData.messageCount)
            hover: today && clankerPanel.a ? clankerPanel.a.todayPrompts + " prompts · " + clankerPanel.a.todaySessions + " sessions" : ""
        }
    }

    // tokens by model, heaviest first, hover for the split
    SectionHead { visible: modelRep.count > 0; text: "tokens by model" }
    Repeater {
        id: modelRep
        readonly property var rows: {
            const mu = clankerPanel.a ? (clankerPanel.a.modelUsage || {}) : {};
            const out = [];
            for (const k in mu) {
                const u = mu[k];
                const total = (u.inputTokens || 0) + (u.outputTokens || 0) + (u.cacheCreationInputTokens || 0) + (u.cacheReadInputTokens || 0);
                out.push({ model: k, total: total, u: u });
            }
            out.sort((x, y) => y.total - x.total);
            return out;
        }
        readonly property real peak: rows.length ? rows[0].total : 0
        model: rows
        TokenRow {
            required property var modelData
            label: modelData.model
            value: modelRep.peak > 0 ? modelData.total / modelRep.peak : 0
            detail: Clanker.tokText(modelData.total)
            hover: "in " + Clanker.tokText(modelData.u.inputTokens) + " · out " + Clanker.tokText(modelData.u.outputTokens)
                + " · cache " + Clanker.tokText((modelData.u.cacheCreationInputTokens || 0) + (modelData.u.cacheReadInputTokens || 0))
        }
    }
}
