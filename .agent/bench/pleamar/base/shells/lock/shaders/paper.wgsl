// paper.wgsl — the lock backdrop: posterise, dither, then run the tube.
//
// One scene shader carrying the two QML passes of the greeter:
// greeter/shaders/posterize_dither.frag (the wallpaper pushed to four levels
// through an ordered dither) and greeter/shaders/crt_screen.frag (barrel
// curve, chromatic aberration, bloom, scanlines, aperture grille, vignette,
// and the dot-grid fallback of BackgroundImage.qml when there is no wallpaper).
//
// They are one shader because a group may carry only one `shader:` and group
// effects cannot nest: `inside(s, at)` is the raw wallpaper image the group
// holds, and this file does the two passes on each sample — the tube warp
// decides *where* to look, the dither decides *what* the looked-at pixel
// becomes. The order still follows the legacy: posterise/dither first, then
// bloom, scanlines and vignette.
//
// What is dropped, and why (README.md, "What is ported"):
//   · the blue-noise mask (mode 1) and the Yliluoma pair search (mode 2): both
//     need a texture input, and a scene shader may not declare bindings; the
//     ordered Bayer 4x4 of mode 0 is the one that survives;
//   · the wallpaper k-means palette (BackgroundImage's four Oklab colours):
//     a group's `shader:` takes numbers, not colours, so the ramp is the two
//     tones below with the source mixed back in (`s.b.z` tube amount? see the
//     values table);
//   · the brightness sweep and the flicker: theme defaults are 0 and they are
//     the only parts that would repaint a still screen forever.
//
// values: s.a.x barrel, s.a.y aberration, s.a.z scanlines, s.a.w grille,
//         s.b.x bloom, s.b.y vignette, s.b.z dither amount, s.b.w dither cell.

const PI: f32 = 3.141592653589793;
const RAMP_DARK: vec3<f32> = vec3<f32>(0.024, 0.031, 0.043);
const RAMP_LIGHT: vec3<f32> = vec3<f32>(0.90, 0.93, 0.965);
const LEVELS: f32 = 3.0;
const MIX_BACK: f32 = 0.55;
const GAMMA: f32 = 1.0;

fn bayer2(x: f32, y: f32) -> f32 {
    if (x < 0.5) {
        if (y < 0.5) { return 0.0; }
        return 2.0;
    }
    if (y < 0.5) { return 3.0; }
    return 1.0;
}

fn bayer4(p: vec2<f32>) -> f32 {
    let m = floor(p);
    let lo = bayer2(m.x % 2.0, m.y % 2.0);
    let hi = bayer2(floor(m.x / 2.0) % 2.0, floor(m.y / 2.0) % 2.0);
    return (4.0 * lo + hi) / 16.0;
}

// The posteriser: four luminance levels distributed by the Bayer threshold,
// the source colour mixed back into the ramp so the picture keeps its hue.
fn posterise(rgb: vec3<f32>, at: vec2<f32>, amount: f32, cell: f32) -> vec3<f32> {
    let lum0 = pow(clamp(dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722)), 0.0, 1.0), GAMMA);
    let mask = bayer4(at / max(cell, 1.0));
    let level = clamp(floor((lum0 + (mask - 0.5) * clamp(amount, 0.0, 2.0)) * LEVELS + 0.5) / LEVELS, 0.0, 1.0);
    let ramp = mix(RAMP_DARK, RAMP_LIGHT, level);
    return mix(ramp, mix(ramp, rgb, 0.45), MIX_BACK);
}

// The legacy dot grid: near-black with a dot every 48 px.
fn dots(p: vec2<f32>) -> vec3<f32> {
    let cell = vec2<f32>(48.0, 48.0);
    let c = (floor(p / cell) + 0.5) * cell;
    let d = length(p - c);
    let dot = 1.0 - smoothstep(1.0, 2.2, d);
    return mix(vec3<f32>(0.039, 0.039, 0.047), vec3<f32>(0.102, 0.102, 0.125), dot);
}

fn shade(s: Shader) -> vec4<f32> {
    let amount = clamp(s.b.z, 0.0, 2.0);
    let cell = max(s.b.w, 1.0);

    // The tube: barrel distortion, with the black border where it ends.
    let uv = s.uv;
    var c = uv * 2.0 - 1.0;
    c = c * (1.0 + clamp(s.a.x, 0.0, 0.5) * dot(c, c));
    let suv = c * 0.5 + 0.5;
    if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    // The wallpaper sample at the warped point; no wallpaper, the dot grid.
    let src = inside(s, suv * s.size);
    let known = src.a >= 0.01;
    var col: vec3<f32>;
    if (known) {
        // Chromatic aberration: the three guns do not land on the same spot.
        let shift = normalize(c + vec2<f32>(1e-5, 1e-5)) * clamp(s.a.y, 0.0, 4.0) * 0.0025 * (0.35 + dot(c, c));
        let r = inside(s, (suv + shift) * s.size);
        let b = inside(s, (suv - shift) * s.size);
        col = vec3<f32>(
            posterise(r.rgb, (suv + shift) * s.size, amount, cell).r,
            posterise(src.rgb, suv * s.size, amount, cell).g,
            posterise(b.rgb, (suv - shift) * s.size, amount, cell).b);
    } else {
        col = dots(suv * s.size);
    }

    // Bloom: six taps around the pixel, only the bright part contributes.
    var glow = vec3<f32>(0.0);
    if (known) {
        for (var i = 0; i < 6; i++) {
            let a = f32(i) * (PI / 3.0);
            let off = vec2<f32>(cos(a), sin(a)) * vec2<f32>(0.009, 0.005) * s.size;
            let tap = inside(s, suv * s.size + off);
            glow += max(posterise(tap.rgb, suv * s.size + off, amount, cell) - vec3<f32>(0.72), vec3<f32>(0.0));
        }
    }
    col += glow * clamp(s.b.x, 0.0, 1.0);

    // Scanlines and the aperture grille (legacy crtLineSpacing 3 px).
    let lines = max(80.0, s.size.y / 3.0);
    let scan = 0.5 - 0.5 * sin(suv.y * lines * PI);
    col *= 1.0 - clamp(s.a.z, 0.0, 1.0) * scan;
    let grille = 0.5 - 0.5 * sin(suv.x * lines * PI * 0.85);
    col *= 1.0 - clamp(s.a.w, 0.0, 1.0) * grille;

    // Vignette, centred like the legacy radial gradient.
    col *= 1.0 - clamp(s.b.y, 0.0, 1.0) * smoothstep(0.4, 1.3, length(c));
    return vec4<f32>(col, 1.0);
}
