import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import "../common"
import "MenuModel.js" as MenuModel

// App launcher (wofi drun replacement), dmenu mode for scripts, and the
// central menu.
// Toggle apps:  qs ipc call launcher toggle
// Dmenu:        ~/.scripts/qsmenu --prompt "..."  (feeds stdin, blocks on a
//               fifo until a selection — or "" on cancel — is written back)
// Menu:         qs ipc call menu toggle  (tree declared in common/Menu.qml)
PanelWindow {
    id: root

    visible: false
    implicitWidth: 480
    implicitHeight: 440
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None


    property bool dmenu: false
    property string dmenuPrompt: ""
    property string dmenuOut: ""
    property var dmenuItems: []

    // ---- central menu (SUPER+SPACE) ----
    // Rows come from Menu.items, already in memory and bound to Sys for live
    // state. The tree is the path: "display/rotate/left-up" nests two deep,
    // and a row is a submenu purely because other rows continue past it —
    // nothing declares hierarchy, so nothing can disagree about it.
    property bool menu: false
    readonly property var menuItems: Menu.items
    property var menuLevel: []   // segments of the open submenu
    // The row awaiting a yes/no, or null. Held here rather than in a separate
    // dialog window: the confirm is just two rows in the list already on screen,
    // so it works identically whether the row was reached by walking or search.
    property var pending: null

    onVisibleChanged: {
        if (visible) {
            query.text = "";
            list.currentIndex = 0;
            query.forceActiveFocus();
            // any popout goes, which also drops the popout submap — the two
            // would otherwise fight over Esc
            Sys.closeAll();
        }
        // While open, Hyprland sits in the `launcher` submap (binds.lua): the
        // whole keymap minus the ALT nav layer, so ALT+hjkl reach this surface.
        Hyprland.dispatch(visible ? 'hl.dsp.submap("launcher")' : 'hl.dsp.submap("reset")');
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (root.visible)
                root.finish(null);
            else
                root.visible = true;
        }
    }
    IpcHandler {
        target: "dmenu"
        function open(prompt: string, inFile: string, outFile: string): void {
            if (root.visible)
                root.finish(null);
            root.dmenuPrompt = prompt;
            root.dmenuOut = outFile;
            reader.command = ["cat", inFile];
            reader.running = true;
        }
    }
    IpcHandler {
        target: "menu"
        function toggle(): void {
            if (root.visible) {
                root.finish(null);
                return;
            }
            root.menuLevel = [];
            root.menu = true;
            root.visible = true;
        }
    }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                root.dmenuItems = text.split("\n").filter(l => l.trim() !== "");
                root.dmenu = true;
                root.visible = true;
            }
        }
    }

    readonly property var apps: DesktopEntries.applications.values
        .filter(a => !a.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))
    // Ranking lives in MenuModel.js so `node MenuModel.js` can exercise the
    // same code this imports — see the self-check at the bottom of that file.
    function score(text, q) { return MenuModel.score(text, q); }
    function ranked(rows, q) { return MenuModel.ranked(rows, q); }

    // Rows of the open level: every distinct next segment under the current
    // prefix, in Menu.items order. A segment is a leaf when nothing continues
    // past it.
    readonly property var menuRows: {
        const prefix = menuLevel.length > 0 ? menuLevel.join("/") + "/" : "";
        const seen = {}, rows = [];
        // Apps are native rather than generated: DesktopEntries already gives
        // icons and .execute(), both of which a "path<TAB>command" line loses.
        if (menuLevel.length === 0)
            rows.push({ label: "apps", path: "apps", cmd: "", leaf: false, icon: "view-grid" });
        for (const it of menuItems) {
            if (!it.path.startsWith(prefix))
                continue;
            const rest = it.path.slice(prefix.length);
            const cut = rest.indexOf("/");
            const seg = cut === -1 ? rest : rest.slice(0, cut);
            if (seen[seg])
                continue;
            seen[seg] = true;
            rows.push(cut === -1
                ? Object.assign({ label: seg, leaf: true }, it)
                : { label: seg, path: prefix + seg, leaf: false, icon: Menu.groupIcons[prefix + seg] || "" });
        }
        return rows;
    }

    readonly property var matches: {
        const q = query.text.toLowerCase();
        if (menu) {
            // Cancel first, so a stray Return while the prompt appears backs out
            // rather than powering the machine off.
            if (pending !== null)
                return [
                    { label: "cancel", leaf: true, icon: "close", cancel: true },
                    { label: pending.label + "?", leaf: true, icon: pending.icon || "check", confirm: true }
                ];
            // Searching spans the whole tree, not the open level — typing
            // "hibernate" from the root should find it without walking there,
            // and an app name should find the app.
            if (q !== "") {
                const hits = menuItems.map(it => Object.assign({ label: it.path, leaf: true }, it));
                const appHits = apps.map(a =>
                    ({ label: "apps/" + a.name, app: a, leaf: true }));
                const rows = ranked(hits.concat(appHits), q);
                // Spotlight-style sum: an arithmetic query gets its answer as
                // the first row; Return copies it. MenuModel.calc is null for
                // anything that is not an expression, so searches are untouched.
                const v = MenuModel.calc(query.text);
                if (v !== null)
                    rows.unshift({ label: "= " + v, leaf: true, icon: "calculator", calc: true,
                                   run: () => Quickshell.execDetached(["wl-copy", "--", String(v)]) });
                return rows;
            }
            if (menuLevel.length === 1 && menuLevel[0] === "apps")
                return apps.map(a => ({ label: a.name, app: a, leaf: true }));
            return menuRows;
        }
        if (dmenu) {
            return q === "" ? dmenuItems
                            : dmenuItems.filter(l => l.toLowerCase().includes(q));
        }
        if (q === "")
            return apps;
        return apps.map(a => ({ a: a, s: root.score(a.name, q) }))
            .filter(x => x.s >= 0)
            .sort((x, y) => x.s - y.s || x.a.name.length - y.a.name.length)
            .map(x => x.a);
    }

    // Close the window; sel is a dmenu line, or null for cancel / app mode.
    function finish(sel) {
        if (dmenu && dmenuOut !== "") {
            // unblock the qsmenu client waiting on the fifo
            Quickshell.execDetached(["sh", "-c", 'printf %s "$0" > "$1"', sel ?? "", dmenuOut]);
        }
        dmenu = false;
        dmenuOut = "";
        dmenuItems = [];
        menu = false;
        menuLevel = [];
        pending = null;
        visible = false;
    }

    // Up one level; closes the menu when already at the root.
    function menuBack() {
        if (pending !== null) {
            pending = null;
            query.text = "";
            list.currentIndex = 0;
            return;
        }
        if (menuLevel.length === 0) {
            finish(null);
            return;
        }
        menuLevel = menuLevel.slice(0, -1);
        query.text = "";
        list.currentIndex = 0;
    }

    // A leaf runs either a JS function (Sys setters) or a shell command.
    function run(row) {
        if (row.run) row.run();
        else if (row.cmd) Quickshell.execDetached(["sh", "-c", row.cmd]);
    }

    function activate() {
        const m = matches[list.currentIndex];
        if (m === undefined)
            return;
        if (menu) {
            if (m.cancel) {
                pending = null;
                query.text = "";
                list.currentIndex = 0;
                return;
            }
            if (m.confirm) {
                const p = pending;
                pending = null;
                run(p);
                finish(null);
                return;
            }
            if (!m.leaf) {
                menuLevel = menuLevel.concat([m.label]);
                query.text = "";
                list.currentIndex = 0;
                return;
            }
            if (m.confirm) {
                pending = m;
                query.text = "";
                list.currentIndex = 0;
                return;
            }
            if (m.app !== undefined)
                m.app.execute();
            else
                run(m);
            finish(null);
            return;
        }
        if (dmenu) {
            finish(m);
        } else {
            m.execute();
            finish(null);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Theme.surface
        border.color: Theme.islandBorder
        border.width: 1

        TextInput {
            id: query

            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            height: 24
            font.family: Theme.font
            font.pixelSize: 13
            color: Theme.bright
            clip: true
            onTextChanged: list.currentIndex = 0

            Keys.onEscapePressed: root.menu ? root.menuBack() : root.finish(null)
            Keys.onReturnPressed: root.activate()
            Keys.onDownPressed: list.incrementCurrentIndex()
            Keys.onUpPressed: list.decrementCurrentIndex()
            // Left goes up a level and Right descends, but only with an empty
            // query — otherwise they are cursor keys. A Keys.onXPressed
            // handler accepts the event whether or not it did anything, so
            // the pass-through has to be explicit or the caret never moves.
            Keys.onLeftPressed: event => {
                if (root.menu && query.text === "") root.menuBack();
                else event.accepted = false;
            }
            Keys.onRightPressed: event => {
                const m = root.matches[list.currentIndex];
                if (root.menu && query.text === "" && m !== undefined && !m.leaf) root.activate();
                else event.accepted = false;
            }
            // ALT+hjkl as arrows. Hyprland's nav layer cannot deliver these
            // here (see the `launcher` submap in binds.lua), so the launcher
            // takes the raw chord.
            Keys.onPressed: event => {
                if (!(event.modifiers & Qt.AltModifier)) return;
                const k = event.key;
                if (k === Qt.Key_J) list.incrementCurrentIndex();
                else if (k === Qt.Key_K) list.decrementCurrentIndex();
                else if (k === Qt.Key_H) { if (root.menu && query.text === "") root.menuBack(); else query.cursorPosition = Math.max(0, query.cursorPosition - 1); }
                else if (k === Qt.Key_L) {
                    const m = root.matches[list.currentIndex];
                    if (root.menu && query.text === "" && m !== undefined && !m.leaf) root.activate();
                    else query.cursorPosition = Math.min(query.text.length, query.cursorPosition + 1);
                }
                else return;
                event.accepted = true;
            }

            Text {
                visible: query.text === ""
                text: root.pending !== null ? "confirm — esc to cancel"
                    : root.menu ? (root.menuLevel.length > 0 ? root.menuLevel.join(" / ") : "menu")
                    : root.dmenu ? root.dmenuPrompt : "search apps…"
                font: query.font
                color: Theme.dim
            }
        }
        Rectangle {
            id: divider
            anchors { top: query.bottom; left: parent.left; right: parent.right; leftMargin: 14; rightMargin: 14; topMargin: 4 }
            height: 1
            color: Theme.track
        }

        ListView {
            id: list

            anchors { top: divider.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
            spacing: root.menu ? 2 : 0
            clip: true
            model: root.matches
            highlightMoveDuration: 60
            SmoothScroll { flick: list }

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: list.width
                height: root.menu ? 42 : 34
                radius: 10
                color: list.currentIndex === index ? Qt.alpha(Theme.accent, 0.13) : "transparent"

                // Icon name from a "# menu-icon:" directive; app rows use the
                // real desktop icon below instead. A name rather than a pasted
                // glyph, so a menu script says "cog" instead of carrying a
                // private-use character no editor will render.
                Icon {
                    id: glyph
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    visible: name !== ""
                    name: (root.menu && !modelData.app) ? (modelData.icon || "") : ""
                    size: 18
                    color: modelData.confirm ? Theme.urgent
                        : list.currentIndex === index ? Theme.accent : Theme.text
                }
                IconImage {
                    id: aicon
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    implicitSize: root.menu ? 22 : 18
                    visible: String(source) !== ""
                    source: root.dmenu ? ""
                        : root.menu ? (modelData.app ? Quickshell.iconPath(modelData.app.icon, true) : "")
                        : Quickshell.iconPath(modelData.icon, true)
                }
                Text {
                    id: rowText
                    readonly property string raw: root.menu ? modelData.label : root.dmenu ? modelData : modelData.name
                    anchors {
                        left: parent.left
                        leftMargin: root.dmenu ? 8
                            : root.menu ? ((aicon.visible || glyph.visible) ? 44 : 14)
                            : 34
                        right: side.left
                        verticalCenter: parent.verticalCenter
                    }
                    // breadcrumb (MenuModel.highlight); the match marker is
                    // drawn behind, below
                    textFormat: Text.StyledText
                    // parents a step lighter than Theme.dim: at 13px on the
                    // island the plain dim dropped out
                    text: modelData.calc ? raw
                        : MenuModel.highlight(raw, query.text.toLowerCase(), Qt.lighter(Theme.dim, 1.5), Theme.bright)
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: root.menu ? 13 : Theme.fontSize
                    // the icon carries the "this one asks first" red; a whole
                    // red row read as an error, not a warning
                    color: list.currentIndex === index ? Theme.bright : Theme.text

                    // Highlighter swipes: one rounded rectangle per matched
                    // run, sized from the font's advance width of the text
                    // before and inside the run. Behind the glyphs (z below).
                    FontMetrics { id: fm; font: rowText.font }
                    Repeater {
                        model: modelData.calc ? [] : MenuModel.markRuns(rowText.raw, query.text.toLowerCase())
                        Rectangle {
                            required property var modelData
                            readonly property string shown: MenuModel.displayText(rowText.raw)
                            z: -1
                            x: fm.advanceWidth(shown.slice(0, modelData[0])) - 2
                            width: fm.advanceWidth(shown.slice(modelData[0], modelData[0] + modelData[1])) + 4
                            y: (rowText.height - fm.height) / 2
                            height: fm.height
                            radius: 4
                            // warn, not accent: the accent is the selected
                            // row's fill, and a mark in the same colour
                            // vanished on exactly the row you were looking at
                            color: Qt.alpha(Theme.warn, 0.4)
                        }
                    }
                }
                Text {
                    id: side
                    anchors { right: parent.right; rightMargin: root.menu ? 14 : 8; verticalCenter: parent.verticalCenter }
                    text: root.menu ? (modelData.leaf ? "" : "›")
                        : root.dmenu ? "" : (modelData.genericName || "")
                    font.family: Theme.font
                    font.pixelSize: root.menu ? 15 : 10
                    color: Theme.dim
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { list.currentIndex = index; root.activate(); }
                }
            }
        }
    }
}
