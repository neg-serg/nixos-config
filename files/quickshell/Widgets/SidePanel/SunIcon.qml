import QtQuick
import qs.Settings
import "../../Helpers/Color.js" as Color

// The animated sun of the weather card: a radial glow plus a ring of shimmering
// rays around it. It lives in its own file because it used to be a single ~1.3k
// character line — a Canvas whose onPaint and its 50 ms repaint Timer shared one
// line with the whole ray loop — which made it both unreadable and more
// expensive than the picture warrants.
//
// What changed with the split: the per-ray math (angles, the three sine terms,
// line widths) is a function of the ray index only and is computed once, into
// tables, instead of ~7 trigonometric calls per ray per frame; the ring has 72
// rays instead of 360 (sub-pixel differences at this size: the icon is ~70 px
// across, so 360 rays put four of them on every pixel of the circumference);
// and the repaint interval is 100 ms, not 50 — the shimmer is a slow wobble.
// Together that is ~5× less work per frame and 2× fewer frames, for the same
// visual result.
//
// The animation runs only while the card is actually on screen: `animate` is
// bound to the window's visibility by the caller.
Canvas {
    id: root

    // Keep repainting (the caller stops it when the overlay is not visible)
    property bool animate: false
    // Rays around the ring
    property int rayCount: 72
    // Milliseconds between repaints
    property int frameInterval: 100

    onWidthChanged: requestPaint()
    onAnimateChanged: if (animate) requestPaint()
    onRayCountChanged: { _buildTable(); requestPaint() }
    onFillColorChanged: requestPaint()
    onCoreColorChanged: requestPaint()

    // Theme colours, exposed so the caller keeps owning the palette
    property color fillColor: Theme.accentPrimary
    property color coreColor: "white"

    // Per-ray constants: angle and the three wiggle phases. Index-only, so they
    // are computed once per rayCount change and not per frame.
    property var _angles: []
    property var _wiggle: []
    property var _width: []

    function _buildTable() {
        var n = Math.max(8, rayCount);
        var angles = new Array(n);
        var wiggle = new Array(n);
        var width = new Array(n);
        for (var i = 0; i < n; i++) {
            angles[i] = Math.PI * 2 * i / n;
            wiggle[i] = { a: i * 4.7, b: i * 13.3, c: i * 21.1 };
            // The time-dependent part of the old formula is added per frame below
            width[i] = 0.4;
        }
        _angles = angles;
        _wiggle = wiggle;
        _width = width;
    }

    Component.onCompleted: _buildTable()

    Timer {
        interval: root.frameInterval
        repeat: true
        running: root.animate
        onTriggered: root.requestPaint()
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const s = width;
        const r = s * 0.30;
        const cx = s / 2;
        const cy = s / 2;
        const t = Date.now() * 0.001;

        // Glow
        const glow = ctx.createRadialGradient(cx, cy, r * 0.05, cx, cy, r * 1.5);
        glow.addColorStop(0, "rgba(255,255,255,1)");
        glow.addColorStop(0.12, "rgba(255,255,240,0.95)");
        glow.addColorStop(0.35, Color.withAlpha(fillColor, 0.5));
        glow.addColorStop(0.65, Color.withAlpha(fillColor, 0.1));
        glow.addColorStop(1, "transparent");
        ctx.fillStyle = glow;
        ctx.beginPath();
        ctx.arc(cx, cy, r * 1.5, 0, Math.PI * 2);
        ctx.fill();

        // Shimmering rays
        ctx.globalCompositeOperation = "lighter";
        ctx.strokeStyle = fillColor;
        const n = _angles.length;
        for (let i = 0; i < n; i++) {
            const a = _angles[i];
            const w = _wiggle[i];
            const wig = Math.sin(w.a + t * 0.8) * 0.35 + Math.sin(w.b - t * 0.5) * 0.2 + Math.sin(w.c + t * 1.1) * 0.12;
            const len = r * (0.5 + wig);
            const ca = Math.cos(a);
            const sa = Math.sin(a);
            ctx.globalAlpha = (0.15 + Math.abs(wig) * 0.7) * 0.3;
            ctx.lineWidth = _width[i] + Math.abs(Math.sin((23.7 * i) + t * 3.1));
            ctx.beginPath();
            ctx.moveTo(cx + ca * r * 0.25, cy + sa * r * 0.25);
            ctx.lineTo(cx + ca * len, cy + sa * len);
            ctx.stroke();
        }
        ctx.globalCompositeOperation = "source-over";
    }
}
