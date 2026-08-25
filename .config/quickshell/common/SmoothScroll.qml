import QtQuick

// Browser-grade scrolling for a Flickable, whatever the input device.
//
// Touch already behaves: Flickable's own drag handling has inertia and
// rubberbanding. The other two devices did not —
//
//   wheel     Qt moves contentY 1:1 per notch. A hard jump, no travel.
//   touchpad  Wayland sends pixel deltas with no momentum phase (that is a
//             macOS-only thing in Qt), so the list tracks the fingers and then
//             stops dead the instant they lift. Nothing glides, nothing bounces.
//
// Declare it inside the Flickable and hand it the id:
//
//     ListView { id: list; SmoothScroll { flick: list } }
//
// The id is not optional: a handler declared inside a Flickable is reparented
// to its contentItem, so `parent` here is the content, not the view. That
// reparenting is also why this needs no wrapper item — the contentItem always
// covers the viewport, so the handler sees every wheel event over the list
// without adding a child that a surrounding Column would try to lay out.
WheelHandler {
    id: root

    required property Flickable flick
    // Mouse only, by default. Wayland reports two-finger scroll as a TouchPad
    // device, so without this the touchpad never reached the handler at all —
    // the Flickable underneath took it 1:1, which was the whole complaint.
    acceptedDevices: PointerDevice.AllDevices
    // one notch ≈ one and a bit notification rows
    property real step: 110
    // how far past the end the fingers can drag, and how stiffly
    property real overshoot: 80
    property real resistance: 0.35
    // Touchpad deltas arrive at ~7px per event here, which tracks the fingers
    // faithfully and feels like wading. Browsers scale it up; so does this.
    property real gain: 2.2

    Component.onCompleted: {
        flick.boundsBehavior = Flickable.DragAndOvershootBounds;
        // Flickable's fling defaults are tuned for a finger on glass — short
        // glide, low cap. A touchpad fling wants to carry further.
        flick.flickDeceleration = 700;
        flick.maximumFlickVelocity = 8000;
    }

    // ---- wheel: animated ticks ---------------------------------------------
    readonly property NumberAnimation anim: NumberAnimation {
        target: root.flick
        property: "contentY"
        duration: 260
        easing.type: Easing.OutCubic
    }

    // ---- touchpad: follow the fingers, then fling ---------------------------
    // Velocity is an exponential average of the last few deltas rather than the
    // very last one: the final event before the fingers lift is usually a
    // small, slow one, and flinging off that alone barely moves the list.
    property real vy: 0
    property real lastT: 0
    // Not every stack sends the ScrollEnd phase reliably. If the updates just
    // stop coming, treat that as the end.
    readonly property Timer settle: Timer {
        interval: 60
        onTriggered: root.release()
    }

    function release() {
        settle.stop();
        const f = root.flick;
        const max = Math.max(0, f.contentHeight - f.height);
        if (f.contentY < 0 || f.contentY > max) {
            f.returnToBounds();
        } else if (Math.abs(root.vy) > 40) {
            // Flickable's own fling: deceleration, overshoot and rebound come
            // with it, tuned by flickDeceleration/maximumFlickVelocity.
            f.flick(0, root.vy);
        }
        root.vy = 0;
    }

    onWheel: event => {
        const f = root.flick;
        const max = Math.max(0, f.contentHeight - f.height);

        // A phase event with no movement (ScrollBegin, or an empty update)
        // must not fall through to the wheel branch: that starts an animation
        // to the current position, which pins the list and kills a glide.
        if (event.pixelDelta.y === 0 && event.angleDelta.y === 0 && event.phase !== Qt.ScrollEnd)
            return;

        if (event.pixelDelta.y !== 0 || event.phase === Qt.ScrollEnd) {
            // Not released here. Flickable processes the ScrollEnd after this
            // handler returns and resets its own motion when it does — a fling
            // started synchronously in here died in the same frame it began.
            // One tick later it is past that.
            if (event.phase === Qt.ScrollEnd) { event.accepted = true; settle.interval = 16; settle.restart(); return; }

            root.anim.stop();
            f.cancelFlick();

            const now = Date.now();
            const dt = Math.max(1, now - root.lastT);
            root.lastT = now;
            const dy = event.pixelDelta.y * root.gain;
            // px/ms → px/s, blended
            const inst = dy / dt * 1000;
            root.vy = root.lastT && dt < 200 ? root.vy * 0.6 + inst * 0.4 : inst;

            // Past either end the fingers still move the list, just less —
            // the browser feel that says "this is the end" without a wall.
            let y = f.contentY - dy;
            if (y < 0)        y = Math.max(-root.overshoot, y * root.resistance);
            else if (y > max) y = Math.min(max + root.overshoot, max + (y - max) * root.resistance);
            f.contentY = y;

            settle.interval = 60;
            settle.restart();
            return;
        }

        // Chain off wherever the current animation is headed rather than off
        // the live position, so spinning the wheel adds up instead of
        // restarting from whatever frame it happened to be on.
        const clamp = v => Math.max(0, Math.min(max, v));
        const from = root.anim.running ? root.anim.to : f.contentY;
        root.anim.stop();
        root.anim.from = f.contentY;
        root.anim.to = clamp(from - (event.angleDelta.y / 120) * root.step);
        root.anim.start();
    }
}
