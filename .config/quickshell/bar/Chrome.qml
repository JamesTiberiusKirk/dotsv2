import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "../common"

// The screen's chrome as one shape: the bezel bands on all four edges, the
// bar's band swelling into the island capsules, the OSD capsule on the bottom
// edge, the notches between them, the concave fillets where a capsule meets
// a perpendicular band, the rounded screen corners. One fullscreen layer
// surface, one even-odd path.
//
// It used to be a dozen rectangles and arcs stitched across four windows.
// The chrome is translucent, and translucent pieces only look like one piece
// if every pixel is painted exactly once: at 1.5x scale a join between two
// pieces lands between device pixels, and shows as a bright hairline (gap)
// or a dark one (double alpha). hyprglass then refracts along every such
// edge. One path has no joins.
PanelWindow {
    id: win

    required property var bar   // the bar PanelWindow this chrome belongs to

    screen: bar.screen
    visible: bar.chromeMapped
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // click-through everywhere; the bar and OSD windows take the input
    mask: Region {}
    WlrLayershell.namespace: "quickshell-frame"

    Item {
        id: c
        anchors.fill: parent

        readonly property real t: Theme.frameT
        readonly property real f: Theme.frameFillet
        readonly property real nf: 8           // notch fillet radius
        // capsule protrusion below the band; sinks to nothing when the bar
        // hides, on the same curve as the cells
        readonly property real d: (bar.barBodyHeight - t) * bar.islandFade
        // the bar window is inset from the corners by the side bands' zones;
        // this one is not
        readonly property real off: ((bar.vertical ? height : width) - bar.along) / 2

        // The inner hole, clockwise: top, right, bottom, left. Each edge is
        // built in its own frame (u along the edge, v inward) and mapped to
        // screen coords by a rotation, so the same builder serves all four
        // and arc sweeps stay put. A "bump" is a capsule hanging off an edge:
        // the bar's islands on its side, the OSD on the bottom.
        // The path is rebuilt from the bar's layout, i.e. inside the bar
        // window's polish pass. A Shape in this window that picks the change
        // up there renders the previous path (nvidia/deathstar: capsules
        // stuck one cell short). Hand it over from the event loop instead.
        property string holeNow: hole
        onHoleChanged: holeSettle.restart()
        Timer { id: holeSettle; interval: 0; onTriggered: c.holeNow = c.hole }
        readonly property string hole: {
            const W = width, H = height;
            const L = [W, H, W, H];
            const map = (e, u, v) => e === 0 ? [u, v] : e === 1 ? [W - v, u] : e === 2 ? [W - u, H - v] : [v, H - u];
            const bumps = [[], [], [], []];

            const be = { top: 0, right: 1, bottom: 2, left: 3 }[ShellState.side];
            // band thickness per edge: full on the bar's edge, thin elsewhere
            const T = [0, 1, 2, 3].map(e => e === be ? t : Theme.frameTEdge);
            for (const g of bar.islandGeom) {
                if (!g[2]) continue;
                const a = g[0] + off, b = a + g[1];
                // bottom and left run against the screen axis
                bumps[be].push(be >= 2 ? { u0: L[be] - b, u1: L[be] - a, D: t + d, cr: 12 }
                                       : { u0: a, u1: b, D: t + d, cr: 12 });
            }
            const o = ShellState.osd[win.screen.name];
            if (o && o[1] > 0)
                bumps[2].push({ u0: W / 2 - o[0] / 2, u1: W / 2 + o[0] / 2, D: T[2] + o[1], cr: 14 });

            for (let e = 0; e < 4; e++) {
                const l = bumps[e].sort((a, b) => a.u0 - b.u0);
                // a bump within a notch of a corner is capped there: its body
                // starts at the perpendicular band's inner edge
                const tS = T[(e + 3) % 4], tE = T[(e + 1) % 4];
                for (const b of l) {
                    if (b.u0 <= tS + nf) b.u0 = tS;
                    if (b.u1 >= L[e] - tE - nf) b.u1 = L[e] - tE;
                }
                // overlapping bumps (bar at the bottom over the OSD) merge
                const m = [];
                for (const b of l) {
                    const p = m[m.length - 1];
                    if (p && b.u0 < p.u1) { p.u1 = Math.max(p.u1, b.u1); p.D = Math.max(p.D, b.D); }
                    else m.push(b);
                }
                bumps[e] = m;
            }
            // chrome depth at each edge's start / end corner
            const ds = e => { const l = bumps[e]; return l.length && l[0].u0 === T[(e + 3) % 4] ? l[0].D : T[e]; };
            const de = e => { const l = bumps[e]; return l.length && l[l.length - 1].u1 === L[e] - T[(e + 1) % 4] ? l[l.length - 1].D : T[e]; };

            const p = [];
            const pt = (e, u, v) => { const s = map(e, u, v); return s[0] + " " + s[1]; };
            for (let e = 0; e < 4; e++) {
                const prev = (e + 3) % 4, next = (e + 1) % 4;
                const ln = (u, v) => p.push("L " + pt(e, u, v));
                const arc = (r, sweep, u, v) => p.push("A " + r + " " + r + " 0 0 " + sweep + " " + pt(e, u, v));
                const uS = de(prev) + f, uE = L[e] - ds(next) - f;
                p.push((e ? "L " : "M ") + pt(e, uS, ds(e)));
                const l = bumps[e];
                for (let i = 0; i < l.length; i++) {
                    const b = l[i];
                    const dd = b.D - T[e], rc = Math.min(b.cr, dd / 2);
                    if (b.u0 !== T[prev]) {
                        // notch down from the band: fillet fits the gap to the
                        // previous bump (or the corner fillet) and the protrusion
                        const pu = i ? l[i - 1].u1 : uS;
                        const r = Math.max(0, Math.min(nf, (b.u0 - pu) / 2, dd / 2));
                        ln(b.u0 - r, T[e]);
                        arc(r, 1, b.u0, T[e] + r);
                        ln(b.u0, b.D - rc);
                        arc(rc, 0, b.u0 + rc, b.D);
                    }
                    if (b.u1 !== L[e] - T[next]) {
                        const nu = i + 1 < l.length ? l[i + 1].u0 : uE;
                        const r = Math.max(0, Math.min(nf, (nu - b.u1) / 2, dd / 2));
                        ln(b.u1 - rc, b.D);
                        arc(rc, 0, b.u1, b.D - rc);
                        ln(b.u1, T[e] + r);
                        arc(r, 1, b.u1 + r, T[e]);
                    } else {
                        ln(uE, b.D);
                    }
                }
                if (de(e) === T[e]) ln(uE, T[e]);
                arc(f, 1, L[e] - ds(next), de(e) + f);   // concave corner fillet
            }
            p.push("Z");
            return p.join(" ");
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // the chrome itself: screen rect minus the hole
            ShapePath {
                strokeColor: "transparent"
                fillColor: Theme.island
                fillRule: ShapePath.OddEvenFill
                PathSvg { path: "M 0 0 H " + c.width + " V " + c.height + " H 0 Z " + c.holeNow }
            }
            // its inner edge
            ShapePath {
                strokeColor: Theme.islandBorder
                strokeWidth: 1
                fillColor: "transparent"
                PathSvg { path: c.holeNow }
            }
            // rounded screen corners: bezel black outside the arc
            ShapePath {
                id: corners
                strokeColor: "transparent"
                fillColor: Theme.bezel
                readonly property real r: Theme.frameRadius
                readonly property real w: c.width
                readonly property real h: c.height
                PathSvg {
                    path: "M 0 " + corners.r + " V 0 H " + corners.r + " A " + corners.r + " " + corners.r + " 0 0 0 0 " + corners.r + " Z"
                        + " M " + corners.w + " " + corners.r + " V 0 H " + (corners.w - corners.r) + " A " + corners.r + " " + corners.r + " 0 0 1 " + corners.w + " " + corners.r + " Z"
                        + " M 0 " + (corners.h - corners.r) + " V " + corners.h + " H " + corners.r + " A " + corners.r + " " + corners.r + " 0 0 1 0 " + (corners.h - corners.r) + " Z"
                        + " M " + corners.w + " " + (corners.h - corners.r) + " V " + corners.h + " H " + (corners.w - corners.r) + " A " + corners.r + " " + corners.r + " 0 0 0 " + corners.w + " " + (corners.h - corners.r) + " Z"
                }
            }
        }
    }
}
