import Quickshell
import QtQuick
import QtQuick.Layouts
import "."

// CREW station: AWAY TEAMS (gtmux sessions), DILITHIUM (agent usage).
// Away team rows are ship.crew: { name, windows, agent }. `agent` is "" until phase 6, then
// WORKING / NEEDS ORDERS / IDLE and the tag in the row lights up with no other change.
Item {
    id: st
    required property var ship
    property alias page: tabs.page

    PageTabs { id: tabs; pages: ["AWAY TEAMS", "DILITHIUM"] }

    // LiveData polls gtmux only while this is "crew.away" (and shown + attended)
    readonly property string want: "crew." + ["away", "dilithium"][page]
    onWantChanged: ship.view = want
    Component.onCompleted: ship.view = want
    Component.onDestruction: if (String(ship.view).indexOf("crew.") === 0) ship.view = ""

    readonly property real pageTop: tabs.height + 16
    // The shell env has GTMUX set and gtmux refuses a nested attach: strip it. One launch per 1.5s
    // (a double tap must not open two terminals); LiveData re-polls shortly after.
    property double lastLaunch: 0
    function launch(args) {
        const n = Date.now();
        if (n - lastLaunch < 1500) return;
        lastLaunch = n;
        ship.run(["wezterm", "start", "--", "env", "-u", "GTMUX", "gtmux"].concat(args));
        ship.crewSoon();
    }
    function agentTint(a) { return a === "WORKING" ? Lc.green : a === "NEEDS ORDERS" ? Lc.orange : a === "IDLE" ? Lc.sky : Lc.lilac; }

    // ================= AWAY TEAMS =================
    Loader {
        active: st.page === 0
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            ScrollCol {
                // NEW MISSION: one pill per workspace (workspaces.yaml) opens that workspace's project picker
                Flow {
                    Layout.fillWidth: true
                    spacing: 12
                    Label { text: "NEW MISSION"; color: Lc.orange; font.pixelSize: 22; height: 56; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        model: st.ship.projectWs
                        Pill { required property string modelData; text: modelData; tint: Lc.orange; height: 56; labelSize: 20; onClicked: st.launch(["ws", modelData]) }
                    }
                    Pill { text: "TEMP AWAY TEAM"; tint: Lc.lilac; height: 56; labelSize: 20; holdMs: 600; onClicked: st.launch(["t"]) }
                }
                SectHead { text: "AWAY TEAMS  " + st.ship.crew.length; code: Lc.code("away") }
                Repeater {
                    model: ScriptModel { values: st.ship.crew; objectProp: "name" }
                    CodedRow {
                        required property var modelData
                        Layout.fillWidth: true
                        onClicked: st.launch(["attach", modelData.name])
                        label: modelData.name
                        note: modelData.windows + (modelData.windows === 1 ? " WINDOW" : " WINDOWS")
                        tint: Lc.lilac
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 190; horizontalAlignment: Text.AlignRight
                            visible: modelData.agent !== ""
                            text: modelData.agent
                            color: st.agentTint(modelData.agent)
                            font.pixelSize: 20
                        }
                        Pill { text: "ATTACH"; tint: Lc.blue; height: 48; labelSize: 20; onClicked: st.launch(["attach", modelData.name]) }
                    }
                }
                Label { visible: !st.ship.crewOk; text: "GTMUX SERVER OFFLINE"; color: Lc.red; font.pixelSize: 22 }
                Label { visible: st.ship.crewOk && st.ship.crew.length === 0; text: "NO AWAY TEAMS DEPLOYED"; color: Lc.lilac; font.pixelSize: 22 }
            }
        }
    }

    // ================= DILITHIUM =================
    Loader {
        active: st.page === 1
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                Repeater {
                    model: st.ship.agents
                    ScrollCol {
                        required property var modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                        // tap = select, same as the agent chips in the bar's clanker popout
                        CodedRow {
                            Layout.fillWidth: true
                            label: modelData.name.toUpperCase()
                            note: modelData.status !== "" ? modelData.status : modelData.tier
                            value: st.ship.agentSel === modelData.id ? "PINNED" : "PIN TO BAR"
                            valueColor: st.ship.agentSel === modelData.id ? Lc.orange : Lc.tan
                            tint: Lc.orange; hot: st.ship.agentSel === modelData.id
                            onClicked: st.ship.selectAgent(modelData.id)
                        }
                        SectHead { text: "DILITHIUM CELLS"; code: Lc.code(modelData.id) }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: st.ship.agents.length === 1 ? 2 : 1; columnSpacing: 24; rowSpacing: 14
                            Repeater {
                                model: modelData.limits
                                CodedRow {
                                    required property var modelData
                                    Layout.fillWidth: true; Layout.preferredWidth: 1
                                    label: String(modelData.title).toUpperCase()
                                    note: modelData.reset !== "" ? "RESETS IN " + modelData.reset.toUpperCase() : ""
                                    value: modelData.pct >= 0 ? Math.round(modelData.pct * 100) + "%" : "--"
                                    valueColor: modelData.pct >= 0.9 ? Lc.red : Lc.peach
                                    level: modelData.pct >= 0 ? modelData.pct : -1
                                    tint: modelData.pct >= 0.9 ? Lc.red : Lc.green
                                }
                            }
                        }
                        CodedRow {
                            Layout.fillWidth: true; visible: !!modelData.balance
                            label: "BALANCE"
                            note: modelData.balance ? modelData.balance.spent.toFixed(2) + " OF " + modelData.balance.funded.toFixed(2) + " SPENT" : ""
                            value: modelData.balance ? modelData.balance.remaining.toFixed(2) + " " + modelData.balance.currency + (modelData.balance.estimated ? " ~" : "") : ""
                            level: modelData.balance && modelData.balance.funded > 0 ? modelData.balance.remaining / modelData.balance.funded : -1
                            tint: Lc.blue
                        }
                        Label { visible: modelData.limits.length === 0 && !modelData.balance; text: "NO LIMIT DATA"; color: Lc.lilac; font.pixelSize: 22 }
                    }
                }
                Label { visible: st.ship.agents.length === 0; text: "NO AGENT TELEMETRY"; color: Lc.lilac; font.pixelSize: 22 }
            }
        }
    }
}
