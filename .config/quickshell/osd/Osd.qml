import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import "../common"

// Bottom-centre island. Three sizes: a sliver on the screen edge (default),
// compact (auto, ~1.4 s: the old OSD row on a volume/brightness/kbd change,
// or the track on a track change), expanded (hover / interacting: player
// tabs, art, transport, seek, volume + brightness sliders).
Scope {
    id: osd

    property bool compact: false
    Timer { id: hideTimer; interval: 1400; onTriggered: osd.compact = false }

    property string mode: "vol" // "vol" | "mic" | "bright" | "kbd" | "track"
    property var flashPlayer: null // player whose track change compact shows

    // keyboard backlight is 0-3 (duo(1) pushes the new level on each keypress —
    // the hardware exposes no readable sysfs node for it)
    property int kbdLevel: 0

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [osd.sink, osd.source] }

    // suppress the initial property flurry when pipewire binds
    property bool armed: false
    Timer { interval: 1500; running: true; onTriggered: osd.armed = true }

    function show(m) {
        mode = m;
        compact = true;
        hideTimer.restart();
    }

    Connections {
        target: osd.sink?.audio ?? null
        function onVolumeChanged() { if (osd.armed) osd.show("vol"); }
        function onMutedChanged() { if (osd.armed) osd.show("vol"); }
    }
    // XF86AudioMicMute is bound but showed nothing, so the only way to find out
    // whether the mic was actually muted was to open the audio panel
    Connections {
        target: osd.source?.audio ?? null
        function onVolumeChanged() { if (osd.armed) osd.show("mic"); }
        function onMutedChanged() { if (osd.armed) osd.show("mic"); }
    }
    Connections {
        target: Media
        function onTrackChanged(p) { if (osd.armed) { osd.flashPlayer = p; osd.show("track"); } }
    }

    IpcHandler {
        target: "osd"
        function brightness(): void {
            Sys.refreshBacklight();
            osd.show("bright");
        }
        function kbd(level: string): void {
            osd.kbdLevel = parseInt(level);
            Sys.kbdBacklight = osd.kbdLevel;
            osd.show("kbd");
        }
    }
    // media keys land on the island's selected player, not playerctl's first
    IpcHandler {
        target: "media"
        function playPause(): void { Media.player?.togglePlaying(); }
        function next(): void { Media.player?.next(); }
        function previous(): void { Media.player?.previous(); }
    }

    readonly property bool muted: mode === "vol" ? (sink?.audio?.muted ?? false)
                                : mode === "mic" ? (source?.audio?.muted ?? false)
                                : false
    readonly property real level: mode === "vol" ? (sink?.audio?.volume ?? 0)
                                : mode === "mic" ? (source?.audio?.volume ?? 0)
                                : mode === "kbd" ? kbdLevel / 3
                                : Math.max(0, Sys.backlight)

    readonly property var p: Media.player

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: root
            required property var modelData

            screen: modelData
            anchors { bottom: true }
            // capsule geometry shared with the bar islands (Bar.qml): fill under the
            // frame band, concave fillets into it, rounded outer corners
            readonly property int nT: Theme.frameT
            readonly property int nf: 8
            readonly property int cr: 14
            // collapsed keeps the expanded width so hovering only grows it downward
            readonly property int cardW: compact ? 240 : 340
            // sliver: a short capsule stemming out of the band — fillet and
            // corner radii shrink to fit (capsule.f / capsule.c)
            // collapsed with media: the same card, just cut off after the title
            // and the first slice of the art
            readonly property int cardH: expanded ? body.implicitHeight + 24 : compact ? 44 : Media.active ? 21 : 12
            // the window stays at the expanded size and the capsule animates inside
            // it: resizing a layer surface is a compositor reconfigure per frame
            implicitWidth: 340 + 2 * nf
            implicitHeight: body.implicitHeight + 24 + nT
            mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            // Overlay so the volume/track pop still shows over a fullscreen video;
            // the sliver and hover are what must not peek over one, so those go
            // (window unmapped) while the focused toplevel is fullscreen
            WlrLayershell.layer: WlrLayer.Overlay
            // per screen: a fullscreen video on the other monitor must not show
            // the sliver there just because focus is here
            readonly property bool fullscreen: Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen ?? false
            // with no media the island is dead weight on the edge: it only comes
            // out for the transient vol/brightness/track pop
            readonly property bool live: Media.active || compact
            visible: live && (!fullscreen || compact)
            WlrLayershell.namespace: "quickshell-osd"


            // hover holds expanded; grace so a slip off the edge does not collapse it
            readonly property bool expanded: !fullscreen && (hover.hovered || graceTimer.running || seek.held)
            // the pop shows on the focused screen only; the sliver peeks everywhere
            readonly property bool compact: osd.compact && Hyprland.focusedMonitor?.name === screen.name
            Timer { id: graceTimer; interval: 300 }
            // position is not pushed by the service; ask for it while it is on screen
            Timer {
                interval: 1000; repeat: true
                running: root.expanded && (osd.p?.isPlaying ?? false)
                onTriggered: osd.p.positionChanged()
            }


            Item {
                id: card
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: root.cardW + 2 * root.nf
                height: root.cardH + root.nT
                clip: true
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                HoverHandler { id: hover; onHoveredChanged: if (!hovered) graceTimer.restart() }

                // the capsule is part of the screen chrome (bar/Chrome.qml);
                // this window only says where it is
                // height 0 tells the chrome to skip the notch entirely
                function publish() { ShellState.setOsd(root.screen.name, [capsule.cw, root.live ? capsule.by : 0]); }
                onWidthChanged: publish()
                onHeightChanged: publish()
                Component.onCompleted: publish()
                Connections { target: root; function onLiveChanged() { card.publish(); } }

                // the bar island capsule, flipped: hangs up from the bottom
                // frame strip. Only painted over a fullscreen window: the chrome
                // is under the video there, this window is on the overlay
                Shape {
                    id: capsule
                    anchors.fill: parent
                    visible: root.fullscreen
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real cw: card.width - 2 * root.nf
                    readonly property real by: card.height - root.nT // band top
                    // radii shrink with the card: the sliver is shorter than fillet + corner
                    readonly property real f: Math.min(root.nf, by / 2)
                    readonly property real c: Math.min(root.cr, by - f)
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: Theme.island
                        startX: 0; startY: capsule.by
                        PathArc { x: root.nf; y: capsule.by - capsule.f; radiusX: root.nf; radiusY: capsule.f; direction: PathArc.Counterclockwise }
                        PathLine { x: root.nf; y: capsule.c }
                        PathArc { x: root.nf + capsule.c; y: 0; radiusX: capsule.c; radiusY: capsule.c }
                        PathLine { x: root.nf + capsule.cw - capsule.c; y: 0 }
                        PathArc { x: root.nf + capsule.cw; y: capsule.c; radiusX: capsule.c; radiusY: capsule.c }
                        PathLine { x: root.nf + capsule.cw; y: capsule.by - capsule.f }
                        PathArc { x: card.width; y: capsule.by; radiusX: root.nf; radiusY: capsule.f; direction: PathArc.Counterclockwise }
                    }
                    ShapePath {
                        strokeColor: Theme.islandBorder
                        strokeWidth: 1
                        fillColor: "transparent"
                        startX: 0; startY: capsule.by
                        PathArc { x: root.nf; y: capsule.by - capsule.f; radiusX: root.nf; radiusY: capsule.f; direction: PathArc.Counterclockwise }
                        PathLine { x: root.nf; y: capsule.c }
                        PathArc { x: root.nf + capsule.c; y: 0; radiusX: capsule.c; radiusY: capsule.c }
                        PathLine { x: root.nf + capsule.cw - capsule.c; y: 0 }
                        PathArc { x: root.nf + capsule.cw; y: capsule.c; radiusX: capsule.c; radiusY: capsule.c }
                        PathLine { x: root.nf + capsule.cw; y: capsule.by - capsule.f }
                        PathArc { x: card.width; y: capsule.by; radiusX: root.nf; radiusY: capsule.f; direction: PathArc.Counterclockwise }
                    }
                }

                // ---- compact: the OSD row, or the track that just changed ----
                Item {
                    anchors { fill: parent; leftMargin: root.nf; rightMargin: root.nf; bottomMargin: root.nT }
                    visible: opacity > 0
                    opacity: (root.compact && !root.expanded) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    Row {
                        id: label
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Icon {
                            name: osd.mode === "track" ? Media.icon(osd.flashPlayer)
                                : osd.mode === "bright" ? "white-balance-sunny"
                                : osd.mode === "kbd" ? "keyboard"
                                : osd.mode === "mic" ? (osd.muted ? "microphone-off" : "microphone")
                                : Audio.volIcon(osd.level, osd.muted)
                            color: Theme.bright
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: osd.mode === "track" ? (osd.flashPlayer?.trackTitle || "")
                                : osd.mode === "bright" ? Math.round(osd.level * 100) + "%"
                                : osd.mode === "kbd" ? (osd.kbdLevel === 0 ? "off" : osd.kbdLevel + "/3")
                                : osd.mode === "mic" ? (osd.muted ? "muted" : Math.round(osd.level * 100) + "%")
                                : osd.muted ? "muted"
                                : Math.round(osd.level * 100) + "%"
                            width: osd.mode === "track" ? root.cardW - 44 : implicitWidth
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            color: Theme.bright
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
                        visible: osd.mode !== "track"
                        anchors { left: label.right; right: parent.right; leftMargin: 12; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        height: 4
                        radius: 2
                        color: Theme.track
                        Rectangle {
                            width: parent.width * Math.min(1, osd.level)
                            height: parent.height
                            radius: 2
                            color: osd.muted ? Theme.dim : Theme.accent
                        }
                    }
                }

                // ---- expanded ----
                // drag on a track; value 0..1. Live while held so the poll cannot snap it.
                component TrackDrag: MouseArea {
                    property bool held: false
                    property real shown: 0
                    signal commit(real v)
                    anchors.fill: parent
                    anchors.margins: -8
                    preventStealing: true
                    function at(x) { return Math.max(0, Math.min(1, (x - 8) / (width - 16))); }
                    onPressed: m => { held = true; shown = at(m.x); }
                    onPositionChanged: m => { if (held) { shown = at(m.x); commit(shown); } }
                    onReleased: m => { held = false; commit(shown); }
                    onWheel: w => { commit(Math.max(0, Math.min(1, shown + (w.angleDelta.y > 0 ? 0.05 : -0.05)))); }
                }
                component Track: Rectangle {
                    property real value: 0
                    property bool seekable: true
                    signal commit(real v)
                    readonly property alias held: d.held
                    readonly property real frac: d.held ? d.shown : value
                    onValueChanged: if (!d.held) d.shown = value
                    height: 4; radius: 2
                    color: Theme.track
                    Rectangle { width: parent.width * parent.frac; height: parent.height; radius: 2; color: Theme.accent }
                    TrackDrag { id: d; enabled: parent.seekable; onCommit: v => parent.commit(v) }
                }
                component Btn: Item {
                    property string icon
                    property bool on: true
                    signal clicked
                    width: 30; height: 30
                    opacity: on ? 1 : 0.3
                    Icon { name: parent.icon; size: 22; color: Theme.bright; anchors.centerIn: parent }
                    MouseArea { anchors.fill: parent; enabled: parent.on; onClicked: parent.clicked() }
                }

                // per-player X: drops this player from the island until it plays
                // again (Media.dismiss). Only reachable while expanded.
                Btn {
                    anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: root.nf + 8 }
                    icon: "close"
                    visible: root.expanded && !!osd.p
                    onClicked: Media.dismiss(osd.p)
                }

                Column {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: root.nf + 12; rightMargin: root.nf + 12 }
                    spacing: 10
                    visible: opacity > 0
                    // the collapsed sliver is this same column with the card
                    // clipped down to its top rows — no separate peek widget
                    opacity: (root.compact && !root.expanded) ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    // tab chips: only when there is something to switch between
                    Item {
                        visible: Media.players.length > 1
                        width: body.width - 26; height: 22
                        Row {
                            spacing: 14
                            Repeater {
                                model: Media.players
                                Item {
                                    required property var modelData
                                    readonly property bool on: modelData === osd.p
                                    width: tabRow.width; height: 22
                                    Row {
                                        id: tabRow
                                        spacing: 4
                                        Icon { name: Media.icon(modelData); size: 13; color: on ? Theme.bright : Theme.dim; anchors.verticalCenter: parent.verticalCenter }
                                        Text {
                                            text: modelData.trackTitle || modelData.identity
                                            width: Math.min(implicitWidth, 110); elide: Text.ElideRight
                                            font.family: Theme.font; font.pixelSize: 11; font.bold: on
                                            color: on ? Theme.bright : Theme.dim
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent; visible: on }
                                    MouseArea { anchors.fill: parent; onClicked: Media.select(modelData) }
                                }
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.track }
                    }

                    // media: art + title/artist/transport stacked; the transport
                    // sits in the column flow so a two-line title cannot land on it
                    Item {
                        width: body.width; height: Math.max(56, meta.implicitHeight)
                        Rectangle {
                            id: art
                            width: 56; height: 56; radius: 8
                            color: Theme.track
                            clip: true
                            Image {
                                id: cover
                                anchors.fill: parent
                                source: osd.p?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        Column {
                            id: meta
                            anchors { left: art.right; right: parent.right; leftMargin: 10; rightMargin: 26; top: parent.top }
                            spacing: 2
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: osd.p ? (osd.p.trackTitle || osd.p.identity) : "nothing playing"
                                font.family: Theme.font; font.pixelSize: 13; font.bold: true
                                // collapsed the card is just a peek: quiet it down
                                color: root.expanded && osd.p ? Theme.bright : Theme.dim
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: osd.p?.trackArtist ?? ""
                                visible: text !== ""
                                font.family: Theme.font; font.pixelSize: 11
                                color: root.expanded ? Theme.text : Theme.dim
                            }
                            Item {
                                width: parent.width; height: 30
                                Row {
                                    anchors { left: parent.left; leftMargin: -4; verticalCenter: parent.verticalCenter }
                                    Btn { icon: "skip-previous"; on: osd.p?.canGoPrevious ?? false; onClicked: osd.p.previous() }
                                    Btn { icon: (osd.p?.isPlaying ?? false) ? "pause" : "play"; on: osd.p?.canPlay ?? false; onClicked: osd.p.togglePlaying() }
                                    Btn { icon: "skip-next"; on: osd.p?.canGoNext ?? false; onClicked: osd.p.next() }
                                }
                                Text {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    visible: osd.p?.lengthSupported ?? false
                                    text: Media.fmt(seek.frac * (osd.p?.length ?? 0)) + " / " + Media.fmt(osd.p?.length ?? 0)
                                    font.family: Theme.font; font.pixelSize: 10
                                    color: Theme.dim
                                }
                            }
                        }
                    }
                    Track {
                        id: seek
                        width: body.width
                        visible: osd.p?.lengthSupported ?? false
                        value: (osd.p?.length ?? 0) > 0 ? osd.p.position / osd.p.length : 0
                        seekable: osd.p?.canSeek ?? false
                        onCommit: v => osd.p.position = v * osd.p.length
                    }

                }
            }
        }
    }
}
