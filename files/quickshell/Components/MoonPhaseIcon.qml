import QtQuick
import qs.Settings
import "../Helpers/WeatherIcons.js" as WeatherIcons

// Monochromatic moon phase icon with ordered (Bayer) dithering.
// Draws the current lunar phase as a pixel-art disc using Canvas.
Canvas {
    id: root
    property real phase: WeatherIcons.moonAge(new Date())
    property color moonColor: Theme.textPrimary
    property color rimColor: Theme.textSecondary
    property int size: Math.round(Theme.fontSizeSmall * Theme.scale(Screen))
    // Dithering cell size in logical pixels; 1 = per-pixel
    property int cellSize: 1
    // Width of the dithered transition band (0..1, fraction of radius)
    property real ditherBand: 0.45

    width: size
    height: size

    onPhaseChanged: requestPaint()
    onMoonColorChanged: requestPaint()
    onSizeChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        var R = width / 2;
        var cx = R;
        var cy = height / 2;
        var p = phase;
        var cs = Math.max(1, cellSize);
        var band = ditherBand * R;

        // 4x4 Bayer threshold matrix (normalized 0..1)
        var bayer = [
            [ 0/16,  8/16,  2/16, 10/16],
            [12/16,  4/16, 14/16,  6/16],
            [ 3/16, 11/16,  1/16,  9/16],
            [15/16,  7/16, 13/16,  5/16]
        ];

        ctx.fillStyle = root.moonColor;

        for (var py = 0; py < height; py += cs) {
            for (var px = 0; px < width; px += cs) {
                var dx = px + cs * 0.5 - cx;
                var dy = py + cs * 0.5 - cy;
                var dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > R - 0.5) continue;

                // Terminator x-extent at this y-level
                var yNorm = dy / R;
                var y2 = yNorm * yNorm;
                if (y2 >= 1) continue;
                var xExtent = Math.sqrt(1 - y2) * R;
                var tX = Math.cos(2 * Math.PI * p) * xExtent;

                // Illumination: smooth ramp across the terminator
                var signedDist;
                if (p <= 0.5) {
                    signedDist = dx - tX;           // positive = lit (right side)
                } else {
                    signedDist = -(dx + tX);        // positive = lit (left side)
                }
                var illum = (band > 0) ? 0.5 + 0.5 * signedDist / band : (signedDist >= 0 ? 1 : 0);
                illum = Math.max(0, Math.min(1, illum));

                // Ordered dithering
                var bx = Math.floor(px / cs) % 4;
                var by = Math.floor(py / cs) % 4;
                if (bx < 0) bx += 4;
                if (by < 0) by += 4;

                if (illum > bayer[by][bx]) {
                    ctx.fillRect(px, py, cs, cs);
                }
            }
        }

        // Thin rim so the disc outline is visible even at new moon
        ctx.beginPath();
        ctx.arc(cx, cy, R - 0.5, 0, 2 * Math.PI);
        ctx.strokeStyle = root.rimColor;
        ctx.lineWidth = 1;
        ctx.stroke();
    }
}
