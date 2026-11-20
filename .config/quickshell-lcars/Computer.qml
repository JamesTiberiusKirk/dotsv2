import Quickshell
import QtQuick
import QtQuick.Layouts
import "."

// COMPUTER station: a typed chat with the ship's computer (claude -p via ComputerBrain).
// Pages: CHAT, CONFIG. TALK pill = listen.sh via brain.talk().
// Keyboard: tapping the input field sets brain.typing; only then does Lcars.qml give the console window
// Exclusive keyboard focus (Esc, 4 s idle, a tap anywhere else in the console, page or station change, polkit prompt or release hand it back).
Item {
    id: st
    required property var ship
    property alias page: tabs.page
    property alias sub: subTabs.page   // CONFIG sub-tab: 0 SESSIONS, 1 BRAIN, 2 VOICE, 3 ACCESS, 4 SERVERS
    Component.onCompleted: if (brain.keepVoice) brain.warm()   // KEEP VOICE LOADED: the station opening starts the voice engine
    onPageChanged: if (brain) { brain.typing = false; brain.zoomPath = ""; brain.attachOpen = false; }   // the CONFIG tab has nothing to type in; the enlarged picture closes
    Component.onDestruction: if (brain) { brain.zoomPath = ""; brain.attachOpen = false; }

    PageTabs { id: tabs; pages: ["CHAT", "CONFIG"] }
    PageTabs {
        id: subTabs
        visible: st.page === 1
        pages: ["SESSIONS", "BRAIN", "VOICE", "ACCESS", "SERVERS"]
        anchors { top: tabs.bottom; topMargin: 12 }
    }
    // small building blocks for the CONFIG sub-tabs
    component Opt: Pill { toggle: true; tint: Lc.orange; height: 52; labelSize: 20 }
    component Note: Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Lc.tan; font.pixelSize: 18 }
    component Opts: Flow { Layout.fillWidth: true; spacing: 12 }
    function ago(t) {
        const d = Math.max(0, Math.floor(Date.now() / 1000) - t);
        return d < 90 ? "JUST NOW" : d < 5400 ? Math.round(d / 60) + " MIN AGO" : d < 129600 ? Math.round(d / 3600) + " H AGO" : Math.round(d / 86400) + " DAYS AGO";
    }
    // window-wide way out: Esc always hands the keyboard back, whatever has focus
    Shortcut { sequence: "Escape"; enabled: st.brain.typing; onActivated: st.brain.typing = false }
    readonly property real pageTop: tabs.height + 16
    readonly property real subTop: pageTop + 56 + 12 + 14
    readonly property var models: ["haiku", "sonnet", "opus", "fable"]

    readonly property var brain: ship.computer   // owned by LiveData/FakeData so chat survives station switches
    readonly property color modeTint: brain.mode === "LISTENING" || brain.pending > 0 ? Lc.red : brain.mode === "WORKING" ? Lc.orange
        : brain.mode === "SPEAKING" ? Lc.lilac : Lc.green

    // Scanning bar: one Timer, running only while WORKING / VOICE LOADING (fast sweep) or SPEAKING (slow wave). Idle = no timer, bar hidden (OLED).
    readonly property string scanKind: brain.mode === "LISTENING" || brain.pending > 0 ? ""
        : brain.mode === "WORKING" || brain.voiceState === "LOADING" ? "scan" : brain.mode === "SPEAKING" ? "calm" : ""
    readonly property int scanN: 8
    property int tick: 0
    onScanKindChanged: tick = 0
    Timer { interval: 110; repeat: true; running: st.scanKind !== ""; onTriggered: st.tick++ }
    // position of the lit block: scan bounces end to end, calm drifts one way at a fifth of the speed
    readonly property int scanPos: scanKind === "calm" ? Math.floor(tick / 5) % scanN : Math.abs(tick % (2 * scanN - 2) - (scanN - 1))

    // state readout + controls, right of the tabs
    Row {
        id: readout
        anchors { right: parent.right; verticalCenter: tabs.verticalCenter }
        spacing: 12
        // the docked panel is narrow: the mode text gets what the tabs, the bar and the buttons leave over
        readonly property real room: st.width - tabs.width - 24 - (scanRow.visible ? scanRow.width + spacing : 0) - (trustedLbl.visible ? trustedLbl.width + spacing : 0)
            - (allPill.visible ? allPill.width + spacing : 0) - voicePill.width - spacing - newPill.width - spacing - (stopPill.visible ? stopPill.width + spacing : 0) - spacing
        Row {
            id: scanRow
            visible: st.scanKind !== ""
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: st.scanN
                Rectangle {
                    required property int index
                    // lit block full, the block behind it half (scan only), the rest a dark track
                    readonly property int d: st.scanKind === "scan" && st.tick % (2 * st.scanN - 2) >= st.scanN ? index - st.scanPos : st.scanPos - index
                    width: 12; height: 30
                    color: d === 0 ? st.modeTint : d === 1 && st.scanKind === "scan" ? Qt.darker(st.modeTint, 2.2) : Lc.track
                }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Label {
                anchors.right: parent.right
                width: Math.max(80, Math.min(implicitWidth, readout.room))
                elide: Text.ElideLeft
                text: (brain.voiceState !== "" ? "VOICE " + brain.voiceState + "   " : "") + brain.mode
                color: st.modeTint
                font.pixelSize: 26
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: brain.shutUp() }   // tap the readout to silence the computer
            }
            Label {
                anchors.right: parent.right
                width: Math.min(implicitWidth, readout.room)
                elide: Text.ElideRight
                visible: brain.activity !== "" && brain.activity !== brain.mode
                text: brain.activity
                color: Lc.tan
                font.pixelSize: 18
            }
        }
        Label { id: trustedLbl; visible: brain.trusted; anchors.verticalCenter: parent.verticalCenter; text: "TRUSTED"; color: Lc.red; font.pixelSize: 26 }
        // follow-up watching for every task at once; only while a task exists
        Pill { id: allPill; visible: brain.watches.length > 0; text: brain.watches.some(t => t.on) ? "WATCH ALL OFF" : "WATCH ALL ON"; tint: Lc.blue; height: 56; labelSize: 18; onClicked: brain.watchAllToggle() }
        // spoken replies on or off, same setting as MUTE on the VOICE tab
        Pill { id: voicePill; text: brain.mute ? "VOICE OFF" : "VOICE ON"; tint: brain.mute ? Lc.dim : Lc.sky; height: 56; labelSize: 18; onClicked: brain.mute = !brain.mute }
        Pill { id: newPill; text: "NEW"; tint: Lc.rose; height: 56; labelSize: 18; onClicked: brain.newSession() }
        Pill { id: stopPill; text: "STOP"; tint: Lc.red; height: 56; labelSize: 18; visible: brain.working; onClicked: brain.stop() }
    }

    // ================= CHAT =================
    Loader {
        active: st.page === 0
        anchors { top: parent.top; topMargin: st.pageTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            Item {
                id: chat
                focus: true
                ListView {
                    id: list
                    anchors { top: parent.top; left: parent.left; right: parent.right; bottom: extras.top; bottomMargin: 14 }
                    clip: true
                    interactive: contentHeight > height   // a short chat never takes a drifting tap
                    spacing: 16
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothScroll { flick: list; tune: false; step: 220 }   // mouse wheel and touchpad glide (the shell's own helper, linked in); touch is untouched
                    model: brain.entries
                    // stick to the bottom as entries arrive or grow
                    onCountChanged: Qt.callLater(() => list.positionViewAtEnd())
                    cacheBuffer: 6000   // keep picture rows alive off screen: a reloading picture changes its row height and makes the scroll jump
                    onContentHeightChanged: if (!list.moving && (list.atYEnd || list.contentHeight - list.contentY - list.height < 200)) Qt.callLater(() => list.positionViewAtEnd())
                    Component.onCompleted: Qt.callLater(() => list.positionViewAtEnd())

                    delegate: Item {
                        id: d
                        required property string kind
                        required property string text
                        required property string title
                        required property string aid
                        required property string resp
                        required property bool slide
                        required property bool always
                        required property string img
                        width: list.width
                        height: kind === "panel" ? panelBox.boxH : kind === "ask" ? askBox.boxH : kind === "image" || kind === "attach" ? imgBox.boxH : line.lineH

                        // one-line kinds: user, spoken, text, tool, error
                        Row {
                            id: line
                            visible: d.kind !== "panel" && d.kind !== "ask" && d.kind !== "image" && d.kind !== "attach"
                            width: parent.width
                            spacing: 14
                            readonly property real lineH: Math.max(msg.implicitHeight, 30)
                            Rectangle {
                                width: 10; height: line.lineH; radius: 5
                                color: d.kind === "user" ? Lc.sky : d.kind === "spoken" ? Lc.lilac
                                     : d.kind === "error" ? Lc.red : d.kind === "tool" ? Lc.blue : d.kind === "saved" ? Lc.green : d.kind === "report" ? Lc.orange : Lc.dim
                            }
                            Label {
                                width: 110; height: 30; verticalAlignment: Text.AlignVCenter
                                text: d.kind === "user" ? "YOU" : d.kind === "spoken" ? "SPOKEN" : d.kind === "error" ? "ERROR" : d.kind === "tool" ? "TOOL" : d.kind === "saved" ? "SAVED" : d.kind === "report" ? "FOLLOW-UP" : "NOTE"
                                color: d.kind === "user" ? Lc.sky : d.kind === "spoken" ? Lc.lilac : d.kind === "error" ? Lc.red : d.kind === "tool" ? Lc.blue : d.kind === "saved" ? Lc.green : d.kind === "report" ? Lc.orange : Lc.tan
                                font.pixelSize: 18
                            }
                            Label {
                                id: msg
                                width: parent.width - 10 - 110 - 2 * parent.spacing
                                wrapMode: Text.Wrap
                                text: d.text
                                textFormat: Text.PlainText
                                font.capitalization: Font.MixedCase   // tool rows carry file paths and urls: case matters
                                font.pixelSize: d.kind === "text" || d.kind === "tool" || d.kind === "saved" ? 20 : 28
                                color: d.kind === "user" ? Lc.sky : d.kind === "spoken" ? Lc.peach
                                     : d.kind === "error" ? Lc.red : d.kind === "tool" ? Lc.blue : d.kind === "saved" ? Lc.green : d.kind === "report" ? Lc.orange : Qt.darker(Lc.tan, 1.7)
                            }
                        }

                        // ask: permission / confirm card. The full text is shown (wrapped anywhere, scrolls past 300 px), never cut.
                        // Pending = red; the outcome stays in the chat afterwards. Answers come only from taps here (brain.settle).
                        Item {
                            id: askBox
                            visible: d.kind === "ask"
                            width: parent.width; height: boxH
                            readonly property bool open: d.resp === "pending"
                            readonly property color tone: open ? Lc.red : d.resp === "allow" ? Lc.green : d.resp === "deny" ? Lc.rose : Lc.dim
                            readonly property real detailH: Math.min(detail.implicitHeight, open ? 300 : 110)
                            // ALLOW / the slider only appear once the whole text has been on screen (a harmless top must not hide the tail). DENY is always live.
                            property bool reached: false
                            // ALLOW is inert for the first second of a card (brain.settle): shown dimmed until then, so a tap that does nothing is not a mystery
                            property bool armed: Date.now() - (brain.born[d.aid] ?? 0) >= 1000
                            Timer { running: askBox.open && !askBox.armed; interval: 100; repeat: true; onTriggered: askBox.armed = Date.now() - (brain.born[d.aid] ?? 0) >= 1000 }
                            readonly property bool seenEnd: detail.implicitHeight <= 300 + 1 || reached
                            readonly property real boxH: 44 + 18 + detailH + (open ? 18 + 64 : 14 + 32) + 18
                            Rectangle {
                                id: abar
                                x: 0; y: 0; width: parent.width; height: 44; color: askBox.tone; topLeftRadius: 22
                                Label { anchors { left: parent.left; leftMargin: 70; bottom: parent.bottom; bottomMargin: 2 } width: Math.max(0, parent.width - 70 - 16 - 24 - abarTag.implicitWidth); elide: Text.ElideRight
                                    text: d.title; textFormat: Text.PlainText; color: "black"; font.pixelSize: 30 }
                                Label { id: abarTag; anchors { right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 4 } text: askBox.open ? "AUTHORISATION REQUIRED" : Lc.code("ask" + d.aid); color: "black"; font.pixelSize: 16 }
                            }
                            Rectangle { x: 0; y: abar.height + 6; width: 44; height: parent.height - y; color: Qt.darker(askBox.tone, 1.3); bottomLeftRadius: 22 }
                            Flickable {
                                x: 70; y: abar.height + 18
                                width: parent.width - x - 20; height: askBox.detailH
                                contentWidth: width; contentHeight: detail.implicitHeight
                                clip: true; interactive: contentHeight > height + 1
                                boundsBehavior: Flickable.StopAtBounds
                                onContentYChanged: if (contentHeight > height + 1 && contentY + height >= contentHeight - 2) askBox.reached = true
                                Label {
                                    id: detail
                                    width: parent.width
                                    wrapMode: Text.WrapAnywhere
                                    text: d.text
                                    textFormat: Text.PlainText
                                    font.capitalization: Font.MixedCase
                                    font.family: "monospace"
                                    font.pixelSize: 22
                                    color: Lc.peach
                                }
                            }
                            Rectangle {   // more text below the visible part
                                visible: detail.implicitHeight > askBox.detailH + 1
                                anchors { right: parent.right; rightMargin: 20; top: parent.top; topMargin: abar.height + 18 + askBox.detailH - 22 }
                                width: scrollHint.implicitWidth + 16; height: 22; radius: 11; color: Lc.track
                                Label { id: scrollHint; anchors.centerIn: parent; text: "SCROLL FOR MORE"; color: Lc.tan; font.pixelSize: 14 }
                            }
                            Row {
                                visible: askBox.open
                                x: 70; y: abar.height + 18 + askBox.detailH + 18
                                spacing: 24
                                // DENY first, on the left, always live: a tap that lands short of the slider can only refuse
                                Pill { text: "DENY"; tint: Lc.red; height: 64; labelSize: 26; onClicked: brain.settle(d.aid, "deny") }
                                Label { visible: !askBox.seenEnd; height: 64; verticalAlignment: Text.AlignVCenter; text: "SCROLL TO THE END TO ANSWER"; color: Lc.tan; font.pixelSize: 24 }
                                Pill { visible: askBox.seenEnd && !d.slide; opacity: askBox.armed ? 1 : 0.35; text: "ALLOW"; tint: Lc.green; height: 64; labelSize: 26; onClicked: brain.settle(d.aid, "allow") }
                                Pill { visible: askBox.seenEnd && !d.slide && d.always; opacity: askBox.armed ? 1 : 0.35; text: "ALWAYS ALLOW"; tint: Lc.tan; height: 64; labelSize: 22; onClicked: brain.settle(d.aid, "always") }
                                ConfirmSlider { visible: askBox.seenEnd && d.slide; opacity: askBox.armed ? 1 : 0.35; width: 560; text: "SLIDE TO " + d.title; onConfirmed: brain.settle(d.aid, "allow") }
                            }
                            Label {
                                visible: !askBox.open
                                x: 70; y: abar.height + 18 + askBox.detailH + 14
                                text: d.resp === "allow" ? "ALLOWED" : d.resp === "deny" ? "DENIED" : "EXPIRED"
                                color: askBox.tone; font.pixelSize: 26
                            }
                        }

                        // image / attach: LCARS framed panel with one to four local pictures in a row, tap one to enlarge. Files only (brain.fileUrl), never a URL.
                        // Image shows a gif's first frame (nothing animates). sourceSize keeps a huge file from eating memory. A file that is gone shows IMAGE MISSING.
                        Item {
                            id: imgBox
                            visible: d.kind === "image" || d.kind === "attach"
                            width: parent.width; height: boxH
                            readonly property color tone: d.kind === "attach" ? Lc.sky : Lc.orange
                            readonly property var paths: d.img === "" ? [] : d.img.split("\n")
                            readonly property var caps: d.text.split("\n")
                            readonly property int n: Math.max(1, paths.length)
                            readonly property real gap: 14
                            readonly property real cellW: (width - 70 - 20 - (n - 1) * gap) / n
                            readonly property real maxH: n === 1 ? 480 : n === 2 ? 380 : 260
                            readonly property real boxH: 44 + 18 + cells.childrenRect.height + 24
                            Rectangle {
                                id: ibar
                                x: 0; y: 0; width: parent.width; height: 44; color: imgBox.tone; topLeftRadius: 22
                                Label { anchors { left: parent.left; leftMargin: 70; bottom: parent.bottom; bottomMargin: 2 } text: d.kind === "attach" ? "YOUR ATTACHMENT" : "IMAGE"; color: "black"; font.pixelSize: 30 }
                                Label { anchors { right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 4 } text: Lc.code("img" + d.img); color: "black"; font.pixelSize: 16 }
                            }
                            Rectangle { x: 0; y: ibar.height + 6; width: 44; height: parent.height - y; color: d.kind === "attach" ? Lc.blue : Lc.lilac; bottomLeftRadius: 22 }
                            Row {
                                id: cells
                                x: 70; y: ibar.height + 18
                                spacing: imgBox.gap
                                Repeater {
                                    model: imgBox.paths
                                    Item {
                                        id: cell
                                        required property string modelData
                                        required property int index
                                        readonly property string cap: imgBox.caps[index] ?? ""
                                        width: imgBox.cellW
                                        height: pic.height + (cap !== "" ? capLbl.implicitHeight + 6 : 0)
                                        Image {
                                            id: pic
                                            source: brain.fileUrl(cell.modelData)
                                            asynchronous: true; cache: false
                                            fillMode: Image.PreserveAspectFit
                                            horizontalAlignment: Image.AlignLeft
                                            verticalAlignment: Image.AlignTop
                                            sourceSize.width: 1400; sourceSize.height: 1400
                                            width: parent.width
                                            height: status === Image.Ready ? Math.min(imgBox.maxH, width * implicitHeight / Math.max(1, implicitWidth)) : 60
                                        }
                                        Label { visible: pic.status === Image.Error; anchors { left: parent.left; verticalCenter: pic.verticalCenter } text: "IMAGE MISSING"; color: Lc.red; font.pixelSize: 22 }
                                        Label { visible: pic.status === Image.Loading; anchors { left: parent.left; verticalCenter: pic.verticalCenter } text: "LOADING"; color: Lc.dim; font.pixelSize: 18 }
                                        Label { id: capLbl; y: pic.height + 6; width: parent.width; text: cell.cap; textFormat: Text.PlainText; wrapMode: Text.Wrap
                                            font.capitalization: Font.MixedCase; font.pixelSize: 20; color: Lc.tan }
                                        MouseArea { width: pic.paintedWidth; height: pic.paintedHeight; enabled: pic.status === Image.Ready; onClicked: { brain.zoomPath = cell.modelData; brain.zoomCap = cell.cap; } }
                                    }
                                }
                                Label { visible: imgBox.paths.length === 0; text: "IMAGE MISSING"; color: Lc.red; font.pixelSize: 22 }
                            }
                        }

                        // panel: LCARS framed block, title bar + side bar
                        Item {
                            id: panelBox
                            visible: d.kind === "panel"
                            width: parent.width; height: boxH
                            readonly property real boxH: 44 + 18 + body.implicitHeight + 24
                            Rectangle {
                                id: pbar
                                x: 0; y: 0; width: parent.width; height: 44; color: Lc.orange; topLeftRadius: 22
                                Label { anchors { left: parent.left; leftMargin: 70; bottom: parent.bottom; bottomMargin: 2 } text: d.title; textFormat: Text.PlainText; color: "black"; font.pixelSize: 30 }
                                Label { anchors { right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 4 } text: Lc.code("panel" + d.title); color: "black"; font.pixelSize: 16 }
                            }
                            Rectangle { x: 0; y: pbar.height + 6; width: 44; height: parent.height - y; color: Lc.lilac; bottomLeftRadius: 22 }
                            Label {
                                id: body
                                x: 70; y: pbar.height + 18
                                width: parent.width - x - 20
                                wrapMode: Text.Wrap
                                text: d.text
                                textFormat: Text.PlainText
                                font.capitalization: Font.MixedCase
                                font.pixelSize: 24
                                color: Lc.peach
                            }
                        }
                    }
                }

                // above the input row: the image waiting to be sent, and the ATTACH chooser
                Column {
                    id: extras
                    anchors { left: parent.left; right: parent.right; bottom: bar.top }
                    spacing: 10
                    bottomPadding: brain.attached !== "" || brain.attachOpen || brain.watches.length > 0 ? 10 : 0
                    // follow-up list: one live row per watched task, straight from brain.watches (a cancelled or reported task is simply gone, no pill can outlive it)
                    Repeater {
                        model: brain.watches
                        delegate: Rectangle {
                            id: wrow
                            required property var modelData
                            readonly property string wstate: brain.stateOf(modelData)
                            width: extras.width; height: 60; radius: 16; color: Lc.track
                            RowLayout {
                                anchors { fill: parent; leftMargin: 18; rightMargin: 8 }
                                spacing: 12
                                Rectangle { Layout.preferredWidth: 10; Layout.preferredHeight: 36; radius: 5; color: wrow.wstate === "BLOCKED" ? Lc.red : wrow.wstate === "REPORT WAITING" ? Lc.orange : wrow.wstate === "WATCH OFF" ? Lc.dim : Lc.blue }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    Label { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; font.pixelSize: 22; color: Lc.peach; text: "WATCHING " + wrow.modelData.name }
                                    Label { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; font.capitalization: Font.MixedCase; font.pixelSize: 17; color: Lc.tan; text: wrow.modelData.sent }
                                }
                                Label { text: wrow.wstate; font.pixelSize: 20; color: wrow.wstate === "BLOCKED" ? Lc.red : wrow.wstate === "REPORT WAITING" ? Lc.orange : Lc.tan }
                                Pill { text: wrow.modelData.on ? "WATCH ON" : "WATCH OFF"; tint: Lc.blue; toggle: true; on: wrow.modelData.on; height: 46; labelSize: 18; onClicked: brain.watchToggle(wrow.modelData.sid) }
                                Pill { text: "CANCEL"; tint: Lc.rose; height: 46; labelSize: 18; onClicked: brain.watchCancel(wrow.modelData.sid) }
                            }
                        }
                    }
                    Rectangle {
                        visible: brain.attached !== ""
                        width: parent.width; height: 76; radius: 18; color: Lc.track
                        Row {
                            anchors { fill: parent; margins: 8 }
                            spacing: 18
                            Image { height: 60; width: 100; source: brain.attached !== "" ? brain.fileUrl(brain.attached) : ""; asynchronous: true; cache: false; fillMode: Image.PreserveAspectFit; sourceSize.width: 300; sourceSize.height: 300 }
                            Label { height: 60; verticalAlignment: Text.AlignVCenter; text: "IMAGE ATTACHED. IT GOES WITH YOUR NEXT MESSAGE."; color: Lc.sky; font.pixelSize: 22 }
                            Pill { text: "REMOVE"; tint: Lc.rose; height: 52; labelSize: 20; onClicked: brain.dropAttached() }
                        }
                    }
                    Rectangle {
                        visible: brain.attachOpen
                        width: parent.width; height: chooseCol.implicitHeight + 24; radius: 18; color: Lc.track
                        Column {
                            id: chooseCol
                            x: 14; y: 12; width: parent.width - 28
                            spacing: 10
                            Flow {
                                width: parent.width; spacing: 12
                                Repeater {
                                    model: brain.tFiles ? Quickshell.screens : []
                                    Pill { required property var modelData; text: "SCREENSHOT " + modelData.name; tint: Lc.lilac; height: 52; labelSize: 20; onClicked: brain.attachScreen(modelData.name) }
                                }
                                Pill { visible: brain.tFiles; text: "CLIPBOARD IMAGE"; tint: Lc.lilac; height: 52; labelSize: 20; onClicked: brain.attachClipboard() }
                                Pill { text: "CANCEL"; tint: Lc.rose; height: 52; labelSize: 20; onClicked: brain.attachOpen = false }
                            }
                            Label { visible: !brain.tFiles; width: parent.width; wrapMode: Text.Wrap; color: Lc.red; font.pixelSize: 18
                                text: "READ FILES IS OFF (ACCESS TAB): THE COMPUTER COULD NOT LOOK AT AN IMAGE, SO ATTACHING IS DISABLED." }
                            Label { visible: brain.tFiles; width: parent.width; wrapMode: Text.Wrap; color: Lc.tan; font.pixelSize: 18
                                text: "A SCREENSHOT SHOWS EVERYTHING ON THAT SCREEN AND IS SENT TO CLAUDE. A COPY STAYS IN ~/COMPUTER/ATTACHMENTS. CLIPBOARD: A PNG IMAGE." }
                            Label { visible: brain.attachBusy !== "" || brain.attachError !== ""; width: parent.width; font.pixelSize: 22
                                text: brain.attachBusy !== "" ? brain.attachBusy : brain.attachError; color: brain.attachBusy !== "" ? Lc.orange : Lc.red }
                        }
                    }
                }

                // input row
                RowLayout {
                    id: bar
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 64
                    spacing: 12
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 60
                        radius: 30; color: Lc.track
                        border.width: 3; border.color: input.activeFocus ? Lc.orange : brain.typing ? Lc.tan : Lc.dim
                        TextInput {
                            id: input
                            anchors { fill: parent; leftMargin: 26; rightMargin: 26 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Lc.peach; font.family: Lc.font; font.pixelSize: 28
                            clip: true
                            onAccepted: chat.submit()
                            onTextChanged: brain.touch()
                            Keys.onEscapePressed: { brain.typing = false; chat.forceActiveFocus(); }
                            Label { visible: input.text === "" && !input.activeFocus && !(brain.mode === "LISTENING" && brain.partialText !== ""); anchors.verticalCenter: parent.verticalCenter; text: brain.typing ? "TAP AGAIN TO TYPE" : "TAP HERE TO TYPE"; color: Lc.dim; font.pixelSize: 24 }
                        }
                        // live words while listening: dim italic, after any typed text, newest words kept. Read only: no focus, no typing flag.
                        Label {
                            id: live
                            visible: brain.mode === "LISTENING"
                            readonly property real used: input.text === "" ? 0 : input.contentWidth + 16
                            x: 26 + used
                            width: parent.width - 52 - used
                            anchors.verticalCenter: parent.verticalCenter
                            text: brain.partialText !== "" ? brain.partialText : input.text === "" ? "SPEAK NOW" : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideLeft
                            font.capitalization: Font.MixedCase
                            font.italic: true
                            font.pixelSize: 28
                            color: brain.partialText !== "" ? Qt.darker(Lc.peach, 1.6) : Lc.dim
                        }
                        MouseArea { anchors.fill: parent; onPressed: mouse => { brain.boxTap = true; brain.typing = true; brain.touch(); input.forceActiveFocus(); mouse.accepted = false; } }
                    }
                    Pill { text: "SEND"; tint: Lc.green; Layout.preferredHeight: 60; labelSize: 24; onClicked: chat.submit() }
                    Item {   // space for the mic meter is always reserved: ATTACH and TALK must not move under a finger
                        Layout.preferredWidth: 110; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter
                        Meter { visible: brain.mode === "LISTENING"; anchors.fill: parent; value: brain.micLevel / 100; tint: Lc.red }
                    }
                    Pill { text: "ATTACH"; tint: Lc.lilac; toggle: true; on: brain.tFiles; Layout.preferredHeight: 60; labelSize: 22; onClicked: brain.attachOpen = !brain.attachOpen }
                    Pill {
                        text: brain.mode === "STANDBY" ? "TALK" : brain.pending > 0 ? "WAITING" : brain.mode
                        tint: brain.mode === "STANDBY" ? Lc.blue : st.modeTint
                        Layout.preferredHeight: 60; labelSize: 22
                        onClicked: brain.talk()
                    }
                    Item {   // same: reserved
                        Layout.preferredWidth: 100; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter
                        Label { visible: brain.voiceState !== "" || brain.mute; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter } elide: Text.ElideRight
                            text: brain.mute ? "MUTED" : "VOICE " + brain.voiceState; color: brain.voiceState === "OFFLINE" ? Lc.red : Lc.dim; font.pixelSize: 16 }
                    }
                }
                function submit() {
                    // sending hands the keyboard back to the user's app; tap the box to type again
                    if (brain.send(input.text)) { input.text = ""; brain.typing = false; }
                }
            }
        }
    }

    // ---- enlarged picture: covers the station, tap anywhere to close ----
    Rectangle {
        visible: brain.zoomPath !== ""
        anchors.fill: parent
        z: 100
        color: "black"
        Image {
            anchors { fill: parent; margins: 20; bottomMargin: brain.zoomCap !== "" ? 76 : 56 }
            source: brain.zoomPath !== "" ? brain.fileUrl(brain.zoomPath) : ""
            asynchronous: true; cache: false
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 2400; sourceSize.height: 2400
        }
        Label { anchors { left: parent.left; leftMargin: 24; bottom: parent.bottom; bottomMargin: 14 } width: parent.width - 300; elide: Text.ElideRight
            text: brain.zoomCap; textFormat: Text.PlainText; font.capitalization: Font.MixedCase; font.pixelSize: 24; color: Lc.peach }
        Label { anchors { right: parent.right; rightMargin: 24; bottom: parent.bottom; bottomMargin: 14 } text: "TAP TO CLOSE"; color: Lc.tan; font.pixelSize: 20 }
        MouseArea { anchors.fill: parent; onClicked: brain.zoomPath = "" }
    }

    // ================= CONFIG =================
    // Every sub-tab is its own Loader + ScrollCol (scrolls when the docked panel is short).
    // Settings take effect on the NEXT message (ComputerBrain.buildArgs reads them at send time).

    // ---- SESSIONS ----
    Loader {
        active: st.page === 1 && st.sub === 0
        anchors { top: parent.top; topMargin: st.subTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        onLoaded: brain.refreshSessions()
        sourceComponent: Component {
            ScrollCol {
                RowLayout {
                    spacing: 16
                    Pill { text: "NEW CONVERSATION"; tint: Lc.rose; height: 56; labelSize: 20; onClicked: brain.newSession() }
                    Label { visible: brain.restoring; text: "RESTORING CHAT"; color: Lc.tan; font.pixelSize: 22 }
                }
                SectHead { text: "PREVIOUS CONVERSATIONS"; code: Lc.code("sessions") }
                Note { visible: brain.sessionList.length === 0; text: "NONE YET" }
                Repeater {
                    model: brain.sessionList
                    CodedRow {
                        id: row
                        required property var modelData
                        readonly property bool current: modelData.id === brain.sessionId
                        Layout.fillWidth: true
                        label: modelData.title !== "" ? modelData.title : "(NO TEXT)"
                        note: st.ago(modelData.mtime) + (current ? "   CURRENT" : "")
                        code: Lc.code(modelData.id)
                        hot: current
                        tint: current ? Lc.orange : Lc.lilac
                        Pill { visible: !row.current; text: "RESUME"; tint: Lc.green; height: 52; labelSize: 20; anchors.verticalCenter: parent.verticalCenter; onClicked: brain.resume(row.modelData.id) }
                        ConfirmSlider { visible: !(row.current && brain.working); width: 300; height: 52; text: "SLIDE TO DELETE"; anchors.verticalCenter: parent.verticalCenter; onConfirmed: brain.removeSession(row.modelData.id) }
                    }
                }
                Note { text: "THE CHAT OF THE CURRENT CONVERSATION COMES BACK AFTER A RELOAD. PERMISSION CARDS ARE NOT RESTORED." }
            }
        }
    }

    // ---- BRAIN ----
    Loader {
        active: st.page === 1 && st.sub === 1
        anchors { top: parent.top; topMargin: st.subTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            ScrollCol {
                SectHead { text: "MODEL"; code: Lc.code("model") }
                Opts {
                    Repeater { model: st.models; Opt { required property string modelData; text: modelData.toUpperCase(); on: brain.model === modelData; onClicked: brain.model = modelData } }
                }
                SectHead { text: "THINKING EFFORT"; code: Lc.code("effort") }
                Opts {
                    Repeater {
                        model: ["", "low", "medium", "high", "xhigh", "max"]
                        Opt { required property string modelData; text: modelData === "" ? "DEFAULT" : modelData.toUpperCase(); on: brain.effort === modelData; onClicked: brain.effort = modelData }
                    }
                }
                SectHead { text: "PERSONALITY"; code: Lc.code("persona") }
                Opts {
                    Opt { text: "SHIP COMPUTER"; on: brain.persona === "ship"; onClicked: brain.persona = "ship" }
                    Opt { text: "PLAIN"; on: brain.persona === "plain"; onClicked: brain.persona = "plain" }
                    Opt { text: "CUSTOM"; on: brain.persona === "custom"; onClicked: brain.persona = "custom" }
                    Pill { visible: brain.persona === "custom"; text: "EDIT CUSTOM TEXT"; tint: Lc.tan; height: 52; labelSize: 20; onClicked: brain.edit(brain.customPath, brain.dir + "/persona-ship.md") }
                }
                Note { visible: brain.persona === "custom"; text: "OPENS YOUR EDITOR ON A FILE THAT STARTS AS A COPY OF THE SHIP TEXT. AN EMPTY FILE FALLS BACK TO THE SHIP COMPUTER. THE RULES FOR TOOLS AND PERMISSIONS ALWAYS STAY." }
                SectHead { text: "SPOKEN STYLE"; code: Lc.code("style") }
                Opts {
                    Opt { text: "BRIEF"; on: !brain.chatty; onClicked: brain.chatty = false }
                    Opt { text: "CHATTY"; on: brain.chatty; onClicked: brain.chatty = true }
                    Opt { text: "HIDE NOTES " + (brain.hideNotes ? "ON" : "OFF"); on: brain.hideNotes; onClicked: brain.hideNotes = !brain.hideNotes }
                }
                Note { text: "HIDE NOTES: THE DIM PLAIN TEXT THE COMPUTER LEAVES BESIDE ITS SPOKEN LINES (USUALLY JUST DONE)." }
                SectHead { text: "USAGE GUARD"; code: Lc.code("guard") }
                Opts {
                    Repeater {
                        model: [0, 70, 80, 90]
                        Opt { required property int modelData; text: modelData === 0 ? "OFF" : "STOP AT " + modelData + "%"; on: brain.usageMax === modelData; onClicked: brain.usageMax = modelData }
                    }
                }
                RowLayout {
                    spacing: 16
                    Label { text: "CLAUDE USAGE NOW: " + (brain.usage >= 0 ? Math.round(brain.usage * 100) + "%" : "UNKNOWN"); color: Lc.peach; font.pixelSize: 24 }
                    Meter { visible: brain.usage >= 0; Layout.preferredWidth: 220; value: brain.usage; tint: brain.usageMax > 0 && brain.usage * 100 >= brain.usageMax ? Lc.red : Lc.orange }
                }
                Note { text: "ABOVE THE LIMIT, SENDING IS REFUSED (TYPED AND SPOKEN). UNKNOWN USAGE NEVER BLOCKS." }
                Note { text: "CHANGES APPLY TO THE NEXT MESSAGE." }
            }
        }
    }

    // ---- VOICE ----
    Loader {
        active: st.page === 1 && st.sub === 2
        anchors { top: parent.top; topMargin: st.subTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        sourceComponent: Component {
            ScrollCol {
                SectHead { text: "VOICE"; code: Lc.code("voice") }
                Repeater {
                    model: [{ t: "NOVA", v: "af_nova" }, { t: "EMMA", v: "bf_emma" }, { t: "KORE", v: "af_kore" },
                        { t: "NOVA AND EMMA", v: "af_nova(2)+bf_emma(1)" }, { t: "EMMA AND KORE", v: "bf_emma(1)+af_kore(1)" }]
                    RowLayout {
                        required property var modelData
                        spacing: 12
                        Opt { text: parent.modelData.t; Layout.preferredWidth: 300; on: brain.voice === modelData.v; onClicked: brain.voice = modelData.v }
                        Pill { text: "PREVIEW"; tint: Lc.blue; height: 52; labelSize: 20; onClicked: brain.preview(modelData.v) }
                    }
                }
                Note { text: brain.mute ? "MUTE IS ON: PREVIEW IS SILENT." : "PREVIEW SPEAKS ONE SHORT LINE. THE FIRST ONE WAITS FOR THE VOICE ENGINE TO LOAD." }
                SectHead { text: "SPEED"; code: Lc.code("speed") }
                Opts {
                    Repeater { model: [0.9, 1.0, 1.1, 1.2]; Opt { required property real modelData; text: modelData.toFixed(1) + "X"; on: brain.speed === modelData; onClicked: brain.speed = modelData } }
                }
                SectHead { text: "SOUND"; code: Lc.code("sound") }
                Opts {
                    Opt { text: "ECHO EFFECT " + (brain.fx ? "ON" : "OFF"); on: brain.fx; onClicked: brain.fx = !brain.fx }
                    Opt { text: "MUTE " + (brain.mute ? "ON" : "OFF"); on: brain.mute; tint: Lc.red; onClicked: brain.mute = !brain.mute }
                    Opt { text: "CHIRPS " + (brain.chirps ? "ON" : "OFF"); on: brain.chirps; onClicked: brain.chirps = !brain.chirps }
                    Opt { text: "KEEP VOICE LOADED " + (brain.keepVoice ? "ON" : "OFF"); on: brain.keepVoice; onClicked: brain.keepVoice = !brain.keepVoice }
                }
                Note { text: "MUTE: NOTHING IS PLAYED, CHIRPS INCLUDED, THE CHAT STAYS. KEEP VOICE LOADED: THE VOICE ENGINE (ABOUT 1.5 GB OF MEMORY) STARTS WHEN THE STATION OPENS AND IS NOT UNLOADED AFTER 10 MINUTES IDLE. OFF: IT STARTS WHEN YOU TALK, TYPE OR SEND." }
            }
        }
    }

    // ---- ACCESS ----
    Loader {
        active: st.page === 1 && st.sub === 3
        anchors { top: parent.top; topMargin: st.subTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        onLoaded: { brain.refreshFolders(); brain.refreshAttachments(); }
        sourceComponent: Component {
            ScrollCol {
                id: acc
                property bool askTrust: false      // the slide for TRUSTED is showing
                property bool askShell: false      // the slide for TERMINAL COMMANDS is showing
                SectHead { text: "PERMISSION MODE"; code: Lc.code("perm") }
                Opts {
                    Opt { text: "ASK"; on: brain.permMode === "ask" && !brain.trusted; onClicked: { brain.trusted = false; brain.permMode = "ask"; acc.askTrust = false; } }
                    Opt { text: "READ ONLY"; on: brain.permMode === "readonly"; onClicked: { brain.permMode = "readonly"; acc.askTrust = false; } }
                    Opt { text: "TRUSTED"; tint: Lc.red; on: brain.trusted; onClicked: { if (brain.trusted) brain.trusted = false; else acc.askTrust = !acc.askTrust; } }
                }
                ConfirmSlider { visible: acc.askTrust && !brain.trusted; Layout.preferredWidth: 560; text: "SLIDE FOR TRUSTED MODE"; onConfirmed: { brain.permMode = "ask"; brain.trusted = true; acc.askTrust = false; } }
                Note { text: brain.permMode === "readonly" ? "READ ONLY: NO COMMANDS OR FILE WRITES. THE LISTED CONTROLS STILL ASK WHERE THEY MUST."
                    : brain.trusted ? "TRUSTED: ALLOW CARDS ANSWER THEMSELVES AND STAY READABLE IN THE CHAT. SLIDE CARDS (POWER, KILL, START) STILL NEED YOU. IT ENDS ON EVERY RELOAD."
                    : "ASK: ANYTHING NOT PRE-APPROVED SHOWS A CARD." }
                Note { text: "IN TRUSTED MODE A WEB PAGE THE COMPUTER READS CAN RUN COMMANDS." }
                SectHead { text: "TOOLS"; code: Lc.code("tools") }
                Opts {
                    Opt { text: "WEB " + (brain.tWeb ? "ON" : "OFF"); on: brain.tWeb; onClicked: brain.tWeb = !brain.tWeb }
                    Opt { text: "READ FILES " + (brain.tFiles ? "ON" : "OFF"); on: brain.tFiles; onClicked: brain.tFiles = !brain.tFiles }
                    Opt { text: "SYSTEM CONTROLS " + (brain.tControls ? "ON" : "OFF"); on: brain.tControls; onClicked: brain.tControls = !brain.tControls }
                    Opt { text: "GTMUX AND AGENTS " + (brain.tCrew ? "ON" : "OFF"); on: brain.tCrew; onClicked: brain.tCrew = !brain.tCrew }
                    Opt { text: "OTHER CLAUDE SESSIONS " + (brain.tSess ? "ON" : "OFF"); on: brain.tSess; tint: Lc.red; onClicked: brain.tSess = !brain.tSess }
                    Opt { text: "TERMINAL COMMANDS " + (brain.tShell ? "ON" : "OFF"); on: brain.tShell; tint: Lc.red; onClicked: { if (brain.tShell) brain.tShell = false; else acc.askShell = !acc.askShell; } }
                }
                ConfirmSlider { visible: acc.askShell && !brain.tShell; Layout.preferredWidth: 560; text: "SLIDE TO ALLOW COMMANDS"; onConfirmed: { brain.tShell = true; acc.askShell = false; } }
                Note { Layout.fillWidth: true; color: Lc.red; text: "OTHER CLAUDE SESSIONS: WHEN ON, THE COMPUTER CAN READ YOUR OTHER CLAUDE SESSIONS' CHATS AND SCREENS WITHOUT A CARD. TYPING INTO THEM NEEDS ASK MODE AND A CARD." }
                Note { text: "SYSTEM CONTROLS: VOLUME, BRIGHTNESS, MEDIA, WIFI, BLUETOOTH, POWER, STATIONS, PROGRAMS. GTMUX AND AGENTS: LIST, OPEN, CLOSE AND START SESSIONS." }
                Note { Layout.fillWidth: true; color: Lc.red
                    text: "TERMINAL COMMANDS: SOME SIMPLE COMMANDS (FOR EXAMPLE ECHO TO /DEV/NULL) RUN WITHOUT A CARD. IT ALSO NEEDS ASK MODE" + (brain.tShell && brain.permMode !== "ask" ? " (NOT ACTIVE NOW)." : ".") }
                SectHead { text: "READ ACCESS"; code: Lc.code("read") }
                Opts {
                    Opt { text: "OWN FOLDERS"; on: brain.readOwn; onClicked: brain.readOwn = true }
                    Opt { text: "EVERYTHING EXCEPT PRIVATE"; on: !brain.readOwn; onClicked: brain.readOwn = false }
                    Pill { visible: brain.readOwn; text: "EDIT FOLDER LIST"; tint: Lc.tan; height: 52; labelSize: 20; onClicked: brain.edit(brain.foldersPath, brain.dir + "/folders-template.txt") }
                }
                Note { text: brain.readOwn ? "OWN FOLDERS: READ, SEARCH AND LIST ARE FREE ONLY IN ~/COMPUTER AND THE FOLDERS BELOW. ELSEWHERE: A CARD IN ASK MODE, A REFUSAL IN READ ONLY."
                    : "EVERYTHING EXCEPT PRIVATE: FREE ANYWHERE EXCEPT THE PRIVATE FOLDER LIST (KEYS, BROWSERS, MAIL, PASSWORDS)." }
                Note { visible: brain.readOwn; text: "ONE FOLDER PER LINE IN YOUR EDITOR. EACH MUST EXIST, BE INSIDE YOUR HOME FOLDER AND NOT BE PRIVATE. CHECKED WHEN THE EDITOR CLOSES OR THE FILE CHANGES." }
                Repeater { model: brain.readOwn ? brain.readDirs : []; Label { required property string modelData; text: "OK   " + modelData; color: Lc.green; font.pixelSize: 20; font.capitalization: Font.MixedCase } }
                Repeater { model: brain.readOwn ? brain.folderBad : []; Label { required property string modelData; text: modelData; color: Lc.red; font.pixelSize: 20 } }
                SectHead { text: "MEMORY NOTES"; code: Lc.code("memory") }
                Opts { Opt { text: "MEMORY NOTES " + (brain.memory ? "ON" : "OFF"); on: brain.memory; onClicked: brain.memory = !brain.memory } }
                Note { text: "ON: THE COMPUTER KEEPS NOTES IN ~/COMPUTER/NOTES AND READS THEM AT THE START OF A CONVERSATION. IT MAY WRITE ONLY THERE UNLESS TERMINAL COMMANDS IS ON (ASK MODE). A WEB PAGE COULD PLANT A NOTE." }
                Note { text: "SAVE NOTE (ALWAYS AVAILABLE, ALL MODES): WHEN YOU ASK IT TO COMPILE OR SAVE SOMETHING, IT WRITES A .MD OR .TXT FILE IN ~/COMPUTER/NOTES AND THE CHAT SHOWS A SAVED ROW WITH THE PATH. IT NEVER REPLACES A FILE UNLESS TOLD." }
                SectHead { text: "ATTACHMENTS"; code: Lc.code("attach") }
                RowLayout {
                    spacing: 20
                    Label { text: brain.attachCount + " FILES, " + (brain.attachBytes / 1048576).toFixed(1) + " MB"; color: Lc.peach; font.pixelSize: 24 }
                    ConfirmSlider { visible: brain.attachCount > 0; Layout.preferredWidth: 460; height: 52; text: "SLIDE TO CLEAR ATTACHMENTS"; onConfirmed: brain.clearAttachments() }
                }
                Note { text: "SCREENSHOTS, CLIPBOARD IMAGES AND WEB PICTURES ARE KEPT IN ~/COMPUTER/ATTACHMENTS. AFTER CLEARING, OLD CHATS SHOW IMAGE MISSING WHERE THEY WERE." }
                SectHead { text: "ALWAYS ALLOWED"; code: Lc.code("auto") }
                Note { visible: brain.autoAllow.length === 0; text: "NOTHING IS ALWAYS ALLOWED" }
                Repeater {
                    model: brain.autoAllow
                    CodedRow {
                        id: ar
                        required property string modelData
                        Layout.fillWidth: true
                        label: modelData
                        Pill { text: "REMOVE"; tint: Lc.rose; height: 52; labelSize: 20; anchors.verticalCenter: parent.verticalCenter; onClicked: brain.autoAllow = brain.autoAllow.filter(x => x !== ar.modelData) }
                    }
                }
                Note { text: "ROOT IS NEVER AVAILABLE." }
                Note { text: "THE PRIVATE FOLDER PROTECTION IS BEST EFFORT: A FILE OUTSIDE THE LIST CAN BE READ AND SENT OUT." }
            }
        }
    }
    // ---- SERVERS: the user's own MCP servers (from ~/.claude.json). All off by default. Calls always show a card. ----
    Loader {
        active: st.page === 1 && st.sub === 4
        anchors { top: parent.top; topMargin: st.subTop; left: parent.left; right: parent.right; bottom: parent.bottom }
        onLoaded: brain.refreshServers()
        sourceComponent: Component {
            ScrollCol {
                Note { visible: brain.permMode !== "ask"; color: Lc.red; text: "SERVERS ONLY RUN IN ASK MODE. NOW: READ ONLY, SO NONE OF THEM IS STARTED. CHOOSE ASK ON THE ACCESS TAB." }
                SectHead { text: "YOUR MCP SERVERS"; code: Lc.code("servers") }
                Note { visible: brain.serverList.length === 0; text: "NO SERVERS FOUND IN YOUR CLAUDE CONFIG" }
                Repeater {
                    model: brain.serverList
                    CodedRow {
                        id: sr
                        required property var modelData
                        readonly property bool isOn: brain.servers.indexOf(modelData.name) >= 0
                        readonly property string last: brain.serverStatus[modelData.name] ?? ""
                        Layout.fillWidth: true
                        label: modelData.name
                        note: (modelData.type === "stdio" ? "LOCAL COMMAND" : "REMOTE URL") + (modelData.note !== "" ? ", " + modelData.note : "")
                            + (isOn && last !== "" ? "   LAST RUN: " + last.toUpperCase() : "")
                        code: Lc.code(modelData.name)
                        hot: isOn
                        tint: isOn ? Lc.orange : Lc.lilac
                        Pill { text: sr.isOn ? "ON" : "OFF"; toggle: true; on: sr.isOn; tint: Lc.orange; height: 52; labelSize: 20; anchors.verticalCenter: parent.verticalCenter; onClicked: brain.toggleServer(sr.modelData.name) }
                    }
                }
                Note { text: "ALL OFF BY DEFAULT. EVERY CALL OF THEIR TOOLS SHOWS A CARD FIRST, ALSO IN TRUSTED MODE. ALWAYS ALLOW IS OFFERED PER EXACT TOOL, ONLY FOR READ-LIKE NAMES (GET, LIST, READ, SEARCH, DESCRIBE, STATUS, WHOAMI), NEVER FOR TOOLS WITH DELETE, DEPLOY, SEND, PAY OR RUN IN THE NAME." }
                Note { text: "EACH SWITCHED ON SERVER STARTS WITH EVERY MESSAGE: SLOWER AND MORE USAGE. ONE THAT NEEDS A SIGN-IN OR A BROWSER MAY FAIL: THE CHAT NAMES IT AND THE RUN GOES ON WITHOUT IT." }
                Note { text: "WHAT THEIR TOOLS RETURN IS UNTRUSTED TEXT. NOT LISTED: SERVERS FROM PLUGINS AND THE CLAUDE.AI CONNECTORS (MAIL, CALENDAR, DRIVE). CHANGES APPLY TO THE NEXT MESSAGE." }
            }
        }
    }
}
