// The moon, dithered the way the reference draws it.
//
// QS's Components/MoonPhaseIcon.qml paints the disc on a Canvas: the phase gives
// the terminator, and a 4x4 Bayer matrix stipples the band around it (its
// `ditherBand` is 0.45 of the radius), so the edge reads as dots of falling
// density rather than a smooth gradient. This is that, in one function.
//
// `values: phase` — 0 is new, 0.5 full, 1 new again, the fraction
// WeatherIcons.moonAge returns. `colors: moon, dark`.
fn shade(s: Shader) -> vec4<f32> {
    let p = s.a.x;
    let q = vec2<f32>(s.uv.x * 2.0 - 1.0, s.uv.y * 2.0 - 1.0);
    let rr = dot(q, q);
    let inDisc = 1.0 - smoothstep(1.0 - 2.0 / s.size.x, 1.0, rr);

    // The terminator: cos(pi * (1 - 2p)) is 1 at new (nothing lit), 0 at the
    // quarters (a straight edge), -1 at full (all lit), and the lit part is a half
    // disc whose straight edge bows into that ellipse.
    let bowed = -cos(3.14159265 * (1.0 - 2.0 * p));
    let half = sqrt(max(0.0, 1.0 - q.y * q.y));
    let edge = select(bowed * half, -bowed * half, p > 0.5);
    let across = select(q.x - edge, edge - q.x, p > 0.5);

    // QS's band: `ditherBand` 0.45 of the radius either side of the terminator,
    // the same width in the disc's own units here.
    let band = 0.45 * 2.0;
    let coverage = clamp(across / band + 0.5, 0.0, 1.0);

    // A 4x4 Bayer matrix, the reference's own: the cell's threshold decides
    // whether it takes the lit or the dark tone, so the band comes out as dots.
    var bayer = array<f32, 16>(
        0.0, 8.0, 2.0, 10.0,
        12.0, 4.0, 14.0, 6.0,
        3.0, 11.0, 1.0, 9.0,
        15.0, 7.0, 13.0, 5.0,
    );
    let cell = vec2<u32>(u32(abs(s.pos.x)), u32(abs(s.pos.y)));
    let index = (cell.y % 4u) * 4u + (cell.x % 4u);
    let threshold = (bayer[index] + 0.5) / 16.0;
    let lit = step(threshold, coverage);

    let tone = mix(s.color2.rgb, s.color.rgb, lit);
    return vec4<f32>(tone, inDisc);
}
