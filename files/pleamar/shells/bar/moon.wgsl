// The moon, dithered the way the reference draws it.
//
// QS's Components/MoonPhaseIcon.qml paints the disc on a Canvas: the phase gives
// the terminator, and a 4x4 Bayer matrix stipples the band around it, so the edge
// reads as dots rather than a smooth gradient. This is the same idea in one
// function: a point is lit or dark, and within a couple of pixels of the
// terminator a checker asks which of the two it takes.
//
// `values: phase` — 0 is new, 0.5 full, 1 new again, the same fraction
// WeatherIcons.moonAge returns. `colors: moon, dark`.
fn shade(s: Shader) -> vec4<f32> {
    let p = s.a.x;
    // The point in the disc's own frame: -1..1 across the box.
    let q = vec2<f32>(s.uv.x * 2.0 - 1.0, s.uv.y * 2.0 - 1.0);
    let rr = dot(q, q);
    // A circle with one pixel of edge, so a 12 px disc is not a polygon.
    let inDisc = 1.0 - smoothstep(1.0 - 2.0 / s.size.x, 1.0, rr);

    // The terminator: the lit part is a half disc whose straight edge bows into an
    // ellipse as the moon fills. cos(pi * (1 - 2p)) is 1 at new (nothing lit), 0 at
    // the quarters (a straight terminator), -1 at full (all lit).
    let bowed = -cos(3.14159265 * (1.0 - 2.0 * p));
    let half = sqrt(max(0.0, 1.0 - q.y * q.y));
    // Waxing fills from the right, waning from the left.
    let edge = select(bowed * half, -bowed * half, p > 0.5);
    let across = select(q.x - edge, edge - q.x, p > 0.5);

    // The band around the terminator, and a 2x2 Bayer threshold inside it: the
    // coverage falls off across the band and each cell takes the colour its
    // threshold allows, which is how QS's 4x4 matrix turns the edge into dots of
    // falling density instead of a hard line.
    let coverage = clamp(across / 1.6 + 0.5, 0.0, 1.0);
    let bx = u32(abs(s.pos.x)) % 2u;
    let by = u32(abs(s.pos.y)) % 2u;
    var threshold = 0.125;
    if (bx == 1u && by == 0u) { threshold = 0.375; }
    if (bx == 0u && by == 1u) { threshold = 0.625; }
    if (bx == 1u && by == 1u) { threshold = 0.875; }
    let lit = step(threshold, coverage);

    let tone = mix(s.color2.rgb, s.color.rgb, lit);
    return vec4<f32>(tone, inDisc);
}
