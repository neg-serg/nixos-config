// AccentSampler.js — shared dominant-color extraction from Canvas ImageData
// Used by Media.qml and Music.qml to derive an accent color from album art.

// sampleAccent(imageData, opts) → { r, g, b } | null
// imageData: result of ctx.getImageData(0, 0, w, h)
// opts (all optional):
//   satMin      – strict saturation floor (default 10)
//   lumMin      – strict luminance floor  (default 20)
//   lumMax      – strict luminance ceil   (default 235)
//   satRelax    – relaxed saturation floor (default 8)
//   lumRelaxMin – relaxed luminance floor  (default 20)
//   lumRelaxMax – relaxed luminance ceil   (default 240)
function sampleAccent(imageData, opts) {
    if (!imageData || !imageData.data) return null;
    var data = imageData.data;
    var len = data.length;
    var o = opts || {};
    var satMin = (o.satMin !== undefined) ? o.satMin : 10;
    var lumMin = (o.lumMin !== undefined) ? o.lumMin : 20;
    var lumMax = (o.lumMax !== undefined) ? o.lumMax : 235;
    var satRelax = (o.satRelax !== undefined) ? o.satRelax : 8;
    var lumRelaxMin = (o.lumRelaxMin !== undefined) ? o.lumRelaxMin : 20;
    var lumRelaxMax = (o.lumRelaxMax !== undefined) ? o.lumRelaxMax : 240;

    var rs = 0, gs = 0, bs = 0, n = 0;
    for (var i = 0; i < len; i += 4) {
        var a = data[i + 3]; if (a < 128) continue;
        var r = data[i], g = data[i + 1], b = data[i + 2];
        var maxv = Math.max(r, g, b), minv = Math.min(r, g, b);
        var sat = maxv - minv; if (sat < satMin) continue;
        var lum = (r + g + b) / 3; if (lum < lumMin || lum > lumMax) continue;
        rs += r; gs += g; bs += b; ++n;
    }
    if (n === 0) {
        rs = 0; gs = 0; bs = 0; n = 0;
        for (var j = 0; j < len; j += 4) {
            var a2 = data[j + 3]; if (a2 < 128) continue;
            var r2 = data[j], g2 = data[j + 1], b2 = data[j + 2];
            var max2 = Math.max(r2, g2, b2), min2 = Math.min(r2, g2, b2);
            var sat2 = max2 - min2; if (sat2 < satRelax) continue;
            var lum2 = (r2 + g2 + b2) / 3; if (lum2 < lumRelaxMin || lum2 > lumRelaxMax) continue;
            rs += r2; gs += g2; bs += b2; ++n;
        }
    }
    if (n > 0) {
        return {
            r: Math.min(255, Math.round(rs / n)),
            g: Math.min(255, Math.round(gs / n)),
            b: Math.min(255, Math.round(bs / n))
        };
    }
    return null;
}
