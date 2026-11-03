// The Paper theme's worn sheet, ported from Vitreus
// (https://github.com/natepayn3/Vitreus/blob/main/paper.wgsl, MIT License,
// Copyright (c) 2025 natepayn3). The tear, the wear and the grain runs are the
// original's; the call site (`pages/theme.plm`) decides the box and the tones.
//
// The Paper theme's worn sheet, laid over a drawer's cream body. Its box is the drawer's, grown by a margin on every side (s.a.z), and it does three things:
//   - the TORN EDGE: a ragged fringe of paper just outside the clean body, its outline moving in and out like a tear, with a pale line of fibres along it;
//   - the WEAR: the edge rubbed darker, to a depth that wanders along it;
//   - the GRAIN: long fibres, soft mottling and a faint stain or two.
// The fringe is only painted in a thin ring at the body's edge, so nothing drawn inside the drawer is covered. Everything comes from the point's place:
// it never moves and costs nothing while nothing changes (it does not read `time`).
//
// s.a.x how strong the grain is (0 to 1) · s.a.y a seed, so two sheets are not the same, plus 100 times a mask of the sides that are buried in the frame and must stay clean (1 left, 2 right, 4 top, 8 bottom) · s.a.z the margin round the drawer · s.a.w the corner radius
// s.color the paper (the body's colour) · s.color2 the brown of the wear

fn hash(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(0.1031, 0.1030));
    q = q + dot(q, q.yx + vec2<f32>(33.33, 33.33));
    return fract((q.x + q.y) * q.x);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// One side's torn outline, 0 to 1, along `a` (the distance along that side) with the side's own key.
fn tear_line(a: f32, key: f32) -> f32 {
    let temper = 0.4 + 0.6 * vnoise(vec2<f32>(key * 0.37, 1.3));
    let busy = smoothstep(0.22, 0.7, vnoise(vec2<f32>(a * 0.035, key + 11.0)));
    let slow = vnoise(vec2<f32>(a * 0.07, key));
    let mid = vnoise(vec2<f32>(a * 0.33, key + 3.7));
    let ridged = 1.0 - abs(2.0 * vnoise(vec2<f32>(a * 0.19, key + 6.2)) - 1.0);
    let fine = vnoise(vec2<f32>(a * 1.9, key + 9.1));
    let raw = slow * 0.34 + mid * 0.26 + ridged * ridged * 0.26 + fine * 0.14;
    return clamp(raw * mix(0.18, 1.25, busy) * temper + 0.04 * fine, 0.0, 1.0);
}

fn shade(s: Shader) -> vec4<f32> {
    let m = s.a.z;
    let mask = floor(s.a.y / 100.0 + 0.001);
    let sd = s.a.y - 100.0 * mask;
    let m_l = mask - 2.0 * floor(mask / 2.0);
    let m_r = floor(mask / 2.0) - 2.0 * floor(mask / 4.0);
    let m_t = floor(mask / 4.0) - 2.0 * floor(mask / 8.0);
    let m_b = floor(mask / 8.0);
    let buried = max(max(m_l * (1.0 - smoothstep(m + 16.0, m + 22.0, s.pos.x)), m_r * (1.0 - smoothstep(m + 16.0, m + 22.0, s.size.x - s.pos.x))),
                     max(m_t * (1.0 - smoothstep(m + 16.0, m + 22.0, s.pos.y)), m_b * (1.0 - smoothstep(m + 16.0, m + 22.0, s.size.y - s.pos.y))));
    let seed = vec2<f32>(sd * 91.7, sd * 37.3);
    let p = s.pos + seed;

    // How far this point is from the drawer's edge (negative inside), as a rounded rectangle.
    let half = (s.size - vec2<f32>(2.0 * m, 2.0 * m)) * 0.5;
    let q = abs(s.pos - s.size * 0.5) - half + vec2<f32>(s.a.w, s.a.w);
    let d = length(max(q, vec2<f32>(0.0, 0.0))) + min(max(q.x, q.y), 0.0) - s.a.w;

    // Where along the nearest edges this point is. The pattern is tied to the panel, not to the box: a side's noise runs along that side from its top or left
    // corner, with a key of its own for each of the four, so when the panel opens, closes or wobbles the tear travels with it instead of crawling.
    let dxl = s.pos.x - m;
    let dxr = s.size.x - m - s.pos.x;
    let dyt = s.pos.y - m;
    let dyb = s.size.y - m - s.pos.y;
    let key_v = mix(31.0, 7.0, step(dxl, dxr)) * 13.7 + sd * 3.1;
    let key_h = mix(53.0, 19.0, step(dyt, dyb)) * 13.7 + sd * 3.1;
    let near_v = min(dxl, dxr);
    let near_h = min(dyt, dyb);
    let on_v = smoothstep(-8.0, 8.0, near_h - near_v);       // 1 where a left or right side is the nearer, 0 for a top or bottom one
    let av = s.pos.y;
    let ah = s.pos.x;

    // The tear: the outline sits between 0.4 and 7.8 px outside the body. Each side has its own temper (some nearly clean, some ragged), and along a side
    // the tear comes and goes: calm stretches, then a run of deep chewed notches with sharp points, all fraying finely.
    let tear_v = tear_line(av, key_v);
    let tear_h = tear_line(ah, key_h);
    let tear = mix(tear_h, tear_v, on_v);
    let reach = 0.4 + 7.4 * tear;
    let into = reach - d;                                   // how far inside the torn outline (negative: outside it)
    let cover = clamp(into + 0.5, 0.0, 1.0);
    let ring = smoothstep(-4.0, -2.0, d);                   // the fringe is only painted where the body ends, never inside the drawer

    // The wear: rubbed darker at the edge, to a depth that wanders (along the sides, like the tear).
    let wander = mix(vnoise(vec2<f32>(ah * 0.06, key_h + 5.3)), vnoise(vec2<f32>(av * 0.06, key_v + 5.3)), on_v);
    let depth = 3.0 + 15.0 * wander * wander + 4.0 * tear;
    let blot = 0.55 + 0.9 * vnoise(p * 0.21);               // rubbed unevenly, in patches
    let wear = pow(clamp(1.0 - into / depth, 0.0, 1.0), 1.6) * blot;
    // The grain.
    let fib = vnoise(vec2<f32>(p.x * 0.85, p.y * 0.1)) * vnoise(vec2<f32>(p.x * 0.09, p.y * 0.75));
    let crumple = vnoise(p * 0.045) * 0.6 + vnoise(p * 0.13 + vec2<f32>(3.0, 8.0)) * 0.4;   // soft creases and mottling, no dots
    let stain = smoothstep(0.66, 0.92, vnoise(p * 0.017 + vec2<f32>(7.0, 2.0)));

    let over = clamp((wear * 0.34 + fib * 0.07 + (crumple - 0.5) * 0.12 + stain * 0.08) * s.a.x, 0.0, 0.6) * cover;
    // The pale line of fibres along the tear, broken up so it is not a stroke.
    let pale = (1.0 - smoothstep(0.0, 2.4, into)) * smoothstep(0.25, 0.7, vnoise(p * 0.9)) * cover;
    let paper = mix(s.color.rgb, vec3<f32>(1.0, 0.985, 0.94), pale * 0.75);

    let under = cover * ring;
    let alpha = (over + under * (1.0 - over)) * (1.0 - buried);
    let rgb = (s.color2.rgb * over + paper * under * (1.0 - over)) / max(alpha, 0.0001);
    return vec4<f32>(rgb, alpha);
}
