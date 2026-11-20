import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import "../common"

// Bottom-centre island: the volume/mic/brightness/kbd pop. Hidden by default;
// a change shows a compact capsule for ~1.4 s on the focused screen.
// Also owns the `media` IPC target the media keys call.
Scope {
    id: osd

    property bool compact: false
    Timer { id: hideTimer; interval: 1400; onTriggered: osd.compact = false }

    property string mode: "vol" // "vol" | "mic" | "bright" | "kbd"

    // keyboard backlight is 0-3 (duo(1) pushes the new level on each keypress —
    // the hardware exposes no readable sysfs node for it)
    property int kbdLevel: 0

    // brightness of whichever monitor the keys just moved (duo passes it),
    // 0-1 — not the top panel's, which would misreport an external
    property real brightLevel: 0

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
    // hasFullscreen can go stale across monitors (capsule not painted over a
    // fullscreen video on an unfocused screen); re-read it from hyprctl
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (["fullscreen", "focusedmon", "activewindowv2"].includes(e.name))
                Hyprland.refreshWorkspaces();
        }
    }

    IpcHandler {
        target: "osd"
        function brightness(pct: int): void {
            osd.brightLevel = Math.min(100, Math.max(0, pct)) / 100;
            Sys.refreshBacklight();
            osd.show("bright");
        }
        function kbd(level: string): void {
            osd.kbdLevel = parseInt(level);
            Sys.kbdBacklight = osd.kbdLevel;
            osd.show("kbd");
        }
    }
    // media keys land on the selected player, not playerctl's first
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
                                : brightLevel

    Variants {
        // LCARS owns the eDP panels while on, so no capsule there
        model: ShellState.lcarsScreens

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
            readonly property int cardW: 240
            readonly property int cardH: compact ? 44 : 0
            // the window stays at full size and the capsule animates inside it:
            // resizing a layer surface is a compositor reconfigure per frame
            implicitWidth: cardW + 2 * nf
            implicitHeight: 44 + nT
            mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            // Overlay so the pop still shows over a fullscreen video
            WlrLayershell.layer: WlrLayer.Overlay
            // per screen: a fullscreen video on another monitor must not paint the
            // capsule here just because focus is elsewhere
            readonly property bool fullscreen: Hyprland.monitorFor(screen)?.activeWorkspace?.hasFullscreen ?? false
            visible: compact
            WlrLayershell.namespace: "quickshell-osd"

            // the pop shows on the focused screen only
            readonly property bool compact: osd.compact && Hyprland.focusedMonitor?.name === modelData.name

            Item {
                id: card
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: root.cardW + 2 * root.nf
                height: root.cardH + root.nT
                clip: true
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // the capsule is part of the screen chrome (bar/Chrome.qml);
                // this window only says where it is
                // height 0 tells the chrome to skip the notch entirely
                function publish() { ShellState.setOsd(root.screen.name, [capsule.cw, root.compact ? capsule.by : 0]); }
                onWidthChanged: publish()
                onHeightChanged: publish()
                Component.onCompleted: publish()
                Connections { target: root; function onCompactChanged() { card.publish(); } }

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
                    // radii shrink with the card while it animates open
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

                // the vol/mic/brightness/kbd row
                Item {
                    anchors { fill: parent; leftMargin: root.nf; rightMargin: root.nf; bottomMargin: root.nT }

                    Row {
                        id: label
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        Icon {
                            name: osd.mode === "bright" ? "white-balance-sunny"
                                : osd.mode === "kbd" ? "keyboard"
                                : osd.mode === "mic" ? (osd.muted ? "microphone-off" : "microphone")
                                : Audio.volIcon(osd.level, osd.muted)
                            color: Theme.bright
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: osd.mode === "bright" ? Math.round(osd.level * 100) + "%"
                                : osd.mode === "kbd" ? (osd.kbdLevel === 0 ? "off" : osd.kbdLevel + "/3")
                                : osd.mode === "mic" ? (osd.muted ? "muted" : Math.round(osd.level * 100) + "%")
                                : osd.muted ? "muted"
                                : Math.round(osd.level * 100) + "%"
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            color: Theme.bright
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
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
            }
        }
    }
}
