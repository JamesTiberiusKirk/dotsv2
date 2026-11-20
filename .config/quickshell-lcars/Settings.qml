import Quickshell
import QtQuick
import QtQuick.Layouts
import "."
import "Cmds.js" as Cmds

// SETTINGS station: DISPLAY, INPUT, LOOK, OVERRIDES. All data and actions via `ship`.
// Display scale/refresh changes start a 15s keep-or-revert owned by ship (LiveData), shown as the
// banner next to the tabs on every page. LOOK and OVERRIDES write ~/.local/state/lcars/overrides,
// which hypr/lcars.lua applies on top of the normal Hyprland config.
Item {
    id: st
    required property var ship
    property alias page: tabs.page

    PageTabs { id: tabs; pages: ["DISPLAY", "INPUT", "LOOK", "OVERRIDES"] }

    readonly property string want: "settings." + ["display", "input", "look", "overrides"][page]
    onWantChanged: ship.view = want
    Component.onCompleted: ship.view = want
    Component.onDestruction: if (String(ship.view).indexOf("settings.") === 0) ship.view = ""

    readonly property real pageTop: tabs.height + 16
    function ago(t) {
        const s = Math.max(0, Math.floor((Date.now() - t) / 1000));
        return s < 60 ? "NOW" : s < 3600 ? Math.floor(s / 60) + "M AGO" : s < 86400 ? Math.floor(s / 3600) + "H AGO" : Math.floor(s / 86400) + "D AGO";
    }
    function show(k, v) { return v === "true" ? "ON" : v === "false" ? "OFF" : v; }

    // ---- keep-or-revert banner (always on top of the tab row; stays usable while the console resizes) ----
    Rectangle {
        visible: st.ship.confirmKind !== ""
        anchors { left: tabs.right; leftMargin: 24; right: parent.right; top: parent.top }
        height: tabs.height
        radius: height / 2
        color: Lc.track; border.width: 3; border.color: Lc.red
        RowLayout {
            anchors { fill: parent; leftMargin: 26; rightMargin: 12 }
            spacing: 12
            Label {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: "KEEP " + st.ship.confirmText + "?  REVERTING IN " + st.ship.confirmLeft
                color: Lc.red; font.pixelSize: 22
            }
            Pill { Layout.alignment: Qt.AlignVCenter; text: "KEEP"; tint: Lc.green; height: 44; labelSize: 20; implicitWidth: 100; onClicked: st.ship.keepDisplay() }
            Pill { Layout.alignment: Qt.AlignVCenter; text: "REVERT"; tint: Lc.red; height: 44; labelSize: 20; implicitWidth: 120; onClicked: st.ship.revertDisplay() }
        }
    }

    // ================= DISPLAY =================
    Loader {
        active: st.page === 0
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 2; Layout.fillHeight: true
                    Repeater {
                        model: ScriptModel { values: st.ship.monitorList; objectProp: "name" }
                        ColumnLayout {
                            id: card
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            SectHead { text: card.modelData.name + (card.modelData.off ? "  OFF" : ""); code: Lc.code(card.modelData.name) }
                            Label {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                text: card.modelData.desc.toUpperCase() + "  " + card.modelData.w + "X" + card.modelData.h + " @ " + card.modelData.hz + " HZ  SCALE " + card.modelData.scale
                                color: Lc.tan; font.pixelSize: 18
                            }
                            Label { visible: !card.modelData.off; text: "SCALE"; color: Lc.lilac; font.pixelSize: 16 }
                            Flow {
                                visible: !card.modelData.off
                                Layout.fillWidth: true; spacing: 8
                                Repeater {
                                    model: Cmds.scales(card.modelData)
                                    Pill {
                                        required property real modelData
                                        text: String(modelData); toggle: true; tint: Lc.orange
                                        on: Math.abs(card.modelData.scale - modelData) < 0.01
                                        implicitWidth: 100; height: 48; labelSize: 20
                                        enabled: st.ship.confirmKind === ""
                                        onClicked: st.ship.applyScale(card.modelData.name, modelData)
                                    }
                                }
                            }
                            Label { visible: !card.modelData.off; text: "REFRESH" + (st.ship.ultra ? "  (LOCKED: ULTRA SAVE)" : card.modelData.ext ? "  (EXTERNALS CAPPED AT 120)" : ""); color: Lc.lilac; font.pixelSize: 16 }
                            Flow {
                                visible: !card.modelData.off
                                Layout.fillWidth: true; spacing: 8
                                Repeater {
                                    model: card.modelData.rates
                                    Pill {
                                        required property int modelData
                                        text: modelData + " HZ"; toggle: true; tint: Lc.blue
                                        on: card.modelData.hz === modelData
                                        implicitWidth: 120; height: 48; labelSize: 20
                                        enabled: st.ship.confirmKind === "" && !st.ship.ultra && !card.modelData.mirror
                                        onClicked: st.ship.applyRefresh(card.modelData.name, modelData)
                                    }
                                }
                            }
                            Label { visible: card.modelData.off; text: "PANEL DARK (KEYBOARD DOCKED OR LID SHUT)"; color: Lc.lilac; font.pixelSize: 18 }
                        }
                    }
                    Label { visible: st.ship.monitorList.length === 0; text: "NO DISPLAY DATA"; color: Lc.lilac; font.pixelSize: 22 }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "ARRANGEMENT"; code: Lc.code("arrange") }
                    Pill { text: "SAVE ARRANGEMENT"; tint: Lc.sky; height: 56; labelSize: 20; onClicked: st.ship.saveArrangement() }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: "SCALING EITHER BUILT-IN PANEL SCALES BOTH. ONLY SCALES WITH A WHOLE-NUMBER SCREEN SIZE ARE OFFERED. A CHANGE REVERTS IN 15 SECONDS UNLESS YOU KEEP IT. A REFRESH REVERT RE-APPLIES THE SAVED LAYOUT, SO UNSAVED LIVE ARRANGEMENT CHANGES ARE LOST."
                        color: Lc.tan; font.pixelSize: 18
                    }
                    SectHead { text: "COLOUR"; code: Lc.code("colour") }
                    Pill { text: "NIGHT LIGHT"; toggle: true; on: st.ship.night; tint: Lc.lilac; height: 56; labelSize: 20; onClicked: st.ship.setNight(!on) }
                }
            }
        }
    }

    // ================= INPUT =================
    Loader {
        active: st.page === 1
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "KEYBOARD"; code: Lc.code("keyboard") }
                    CodedRow { Layout.fillWidth: true; label: "LAYOUT"; value: String(st.ship.inputInfo.kb).toUpperCase() || "--"; tint: Lc.blue }
                    CodedRow { Layout.fillWidth: true; label: "REPEAT RATE"; value: st.ship.inputInfo.rate !== "" ? st.ship.inputInfo.rate + " /S" : "--"; tint: Lc.blue }
                    CodedRow { Layout.fillWidth: true; label: "REPEAT DELAY"; value: st.ship.inputInfo.delay !== "" ? st.ship.inputInfo.delay + " MS" : "--"; tint: Lc.blue }
                    Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "READ FROM THE LIVE COMPOSITOR. CHANGE THEM IN HYPR/BASE.LUA."; color: Lc.tan; font.pixelSize: 18 }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "TOUCH AND PEN MAP"; code: Lc.code("touchmap") }
                    Repeater {
                        model: st.ship.inputInfo.touch
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name.toUpperCase(); value: modelData.output; tint: Lc.lilac
                        }
                    }
                    Label { visible: st.ship.inputInfo.touch.length === 0; text: "NO DIGITIZER MAP FOUND"; color: Lc.lilac; font.pixelSize: 22 }
                    Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "READ ONLY. SOURCE: HYPR/BASE.LUA DEVICE RULES. EACH DIGITIZER IS PINNED TO ITS OWN PANEL."; color: Lc.tan; font.pixelSize: 18 }
                }
            }
        }
    }

    // ================= LOOK =================
    Loader {
        active: st.page === 2
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 3; Layout.fillHeight: true
                    SectHead { text: "WINDOW FRAME"; code: Lc.code("frame") }
                    Repeater {
                        model: Cmds.LOOK
                        CodedRow {
                            id: row
                            required property var modelData
                            readonly property string cur: st.ship.lookNow[modelData.key] ?? ""
                            readonly property bool over: st.ship.overrides.some(o => o.key === modelData.key)
                            Layout.fillWidth: true
                            label: modelData.label
                            note: over ? "OVERRIDDEN" : "FROM YOUR CONFIG"
                            tint: over ? Lc.orange : Lc.lilac; hot: over
                            value: modelData.type === "int" ? (cur !== "" ? cur : "--") : ""
                            level: modelData.type === "int" && cur !== "" ? Number(cur) / 40 : -1
                            Pill {
                                visible: row.modelData.type === "int"
                                text: "-"; tint: Lc.blue; height: 48; implicitWidth: 80; labelSize: 28
                                enabled: row.cur !== ""
                                onClicked: st.ship.setOverride(row.modelData.key, String(Math.max(0, Number(row.cur) - 1)))
                            }
                            Pill {
                                visible: row.modelData.type === "int"
                                text: "+"; tint: Lc.blue; height: 48; implicitWidth: 80; labelSize: 28
                                enabled: row.cur !== ""
                                onClicked: st.ship.setOverride(row.modelData.key, String(Math.min(40, Number(row.cur) + 1)))
                            }
                            Pill {
                                visible: row.modelData.type === "bool"
                                text: row.cur === "true" ? "ON" : "OFF"; toggle: true; on: row.cur === "true"; tint: Lc.orange
                                height: 48; implicitWidth: 110; labelSize: 20
                                enabled: row.cur !== ""
                                onClicked: st.ship.setOverride(row.modelData.key, row.cur === "true" ? "false" : "true")
                            }
                        }
                    }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 2; Layout.fillHeight: true
                    SectHead { text: "SHELL GLASS"; code: Lc.code("glass") }
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Pill { text: "GLASS"; toggle: true; on: st.ship.lookFlags.glass; tint: Lc.sky; height: 56; labelSize: 20; onClicked: st.ship.setLookFlag("glass", !on) }
                        Pill { text: "TRANSPARENCY"; toggle: true; on: st.ship.lookFlags.transparency; tint: Lc.sky; height: 56; labelSize: 20; onClicked: st.ship.setLookFlag("transparency", !on) }
                        Pill { text: "BAR"; toggle: true; on: st.ship.lookFlags.bar; tint: Lc.sky; height: 56; labelSize: 20; onClicked: st.ship.setLookFlag("bar", !on) }
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: "FRAME CHANGES ARE OVERRIDES: LIVE NOW, KEPT ON DISK, UNDONE FROM THE OVERRIDES PAGE. GLASS USES THE SHELL'S OWN LOOK FLAGS."
                        color: Lc.tan; font.pixelSize: 18
                    }
                }
            }
        }
    }

    // ================= OVERRIDES =================
    Loader {
        active: st.page === 3
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            RowLayout {
                anchors.fill: parent
                spacing: 30
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "ACTIVE OVERRIDES  " + st.ship.overrides.length; code: Lc.code("overrides") }
                    Repeater {
                        model: ScriptModel { values: st.ship.overrides; objectProp: "key" }
                        CodedRow {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.label
                            note: modelData.old === "" ? "RESTORES ON RELOAD" : "YOUR CONFIG " + st.show(modelData.key, modelData.old)
                            value: st.show(modelData.key, modelData.value); valueColor: Lc.orange
                            tint: Lc.orange; hot: true
                            Pill { text: "COPY LUA"; tint: Lc.sky; height: 48; labelSize: 18; implicitWidth: 130; onClicked: st.ship.copyOverride(modelData.key) }
                            Pill { text: "CLEAR"; tint: Lc.rose; height: 48; labelSize: 18; implicitWidth: 100; onClicked: st.ship.clearOverride(modelData.key) }
                        }
                    }
                    Label { visible: st.ship.overrides.length === 0; text: "NO OVERRIDES. THE SHIP RUNS YOUR CONFIG."; color: Lc.lilac; font.pixelSize: 22 }
                    ConfirmSlider {
                        visible: st.ship.overrides.length > 0
                        text: "CLEAR ALL OVERRIDES"
                        onConfirmed: st.ship.clearAllOverrides()
                    }
                }
                ScrollCol {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true
                    SectHead { text: "CHANGE LOG"; code: Lc.code("changelog") }
                    Repeater {
                        model: st.ship.ovrLog
                        CodedRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            label: Cmds.labelOf(modelData.key)
                            note: modelData.what + "  " + st.ago(modelData.t)
                            value: st.show(modelData.key, modelData.old) + " > " + st.show(modelData.key, modelData.new)
                            tint: Lc.lilac
                            Pill { text: "UNDO"; tint: Lc.blue; height: 48; labelSize: 18; implicitWidth: 100; onClicked: st.ship.undoLog(index) }
                        }
                    }
                    Label { visible: st.ship.ovrLog.length === 0; text: "NOTHING LOGGED YET"; color: Lc.lilac; font.pixelSize: 22 }
                }
            }
        }
    }
}
