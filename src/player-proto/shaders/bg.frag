#version 450
// Procedural wallpaper: flat, tunnel, plasma or spectrum, palette-tinted and capped to stay under text.
// params.x = mode, params.y = intensity/scale, params.z = unused (quad height), params.w = effect strength.
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 2) in vec4 v_color2;
layout(location = 3) in vec4 v_params;
layout(location = 0) out vec4 out_color;
layout(push_constant) uniform Push { vec4 params; } pc;  // xy = physical size, w = seconds

// Sin-free hash: deterministic on every driver, no texture, cheap enough per pixel.
float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// Mode 1: tunnel. Polar coordinates around the quad centre, marched through a fixed budget of depth
// slabs. This is the raycast look, not an SDF tracer: twelve slabs of an analytic density field,
// accumulated front to back with extinction, costs a handful of sin() and never diverges. The
// (1 + z * 5) factor samples far slabs at a wider scale, which is what recedes the rings.
vec3 tunnel(vec2 p, float t, float scale, vec3 base, vec3 accent) {
    const int SLABS = 12;
    float r = length(p) + 1e-4;
    float transmittance = 1.0;
    float lit = 0.0;
    for (int i = 0; i < SLABS; ++i) {
        float z = (float(i) + 0.5) / float(SLABS);          // 0 = near the viewer, 1 = far away
        vec2 q = p * (1.0 + z * 5.0) * (2.0 + scale * 3.0);
        float rq = length(q) + 1e-4;
        float aq = atan(q.y, q.x);
        // Rings travelling towards the viewer, cut into spokes by an angular term that twists with
        // depth — the twist is what makes the structure read as a tube rather than as flat circles.
        // Both are raised to a power: wide sines averaged over twelve slabs would sum into a flat
        // wash, while thin bands stay separate rings and let the depth ordering show.
        float rings = pow(0.5 + 0.5 * sin(rq * 9.0 - t * 1.7 - z * 6.0), 10.0);
        float spokes = pow(0.5 + 0.5 * sin(aq * 8.0 + t * 0.25 + z * 1.3), 2.0);
        float density = (rings * 0.85 + 0.10) * (0.30 + 0.70 * spokes) * 0.6;
        float fog = exp(-z * 2.4);                          // distance fog towards the ground colour
        lit += density * transmittance * fog;
        transmittance *= clamp(1.0 - density * 0.8, 0.0, 1.0);  // nearer slabs hide the far ones
    }
    // Vanishing point: fade the centre out so the tunnel opens into the dark ground, not a blob.
    // Squared so the falloff is quick — the rings have to stay dim in the middle of the frame.
    float vig = smoothstep(0.0, 0.55, r);
    float k = clamp(lit * 0.6 * vig * vig, 0.0, 1.0);
    return mix(base, accent, k);
}

// Mode 2: plasma. Four sines over rotated gradients of the centred coordinates; their interference
// is the classic lava-lamp field, and mapping the sum through base -> accent keeps it in the
// palette (no per-channel trickery, so it can never drift into a rainbow).
vec3 plasma(vec2 p, float t, float scale, vec3 base, vec3 accent) {
    // The multiplier sets the cell size: too small and the frame fills with two giant blobs, too
    // large and the interference breaks into noise finer than any glyph. params.y scales it.
    vec2 q = p * (3.5 + scale * 5.0);
    vec2 q1 = mat2(0.8, -0.6, 0.6, 0.8) * q;       // ~37 deg
    vec2 q2 = mat2(-0.1288, -0.9917, 0.9917, -0.1288) * q1;  // ~97 deg further, uncorrelated
    float v = sin(q.x * 3.1 + t * 0.70)
            + sin(q1.y * 2.6 - t * 0.53)
            + sin((q1.x + q2.y) * 1.7 + t * 0.31)
            + sin(length(q2) * 3.4 - t * 0.87);
    float k = 0.5 + v * 0.125;                     // four sines sum to [-4, 4], so k stays in 0..1
    k = k * k * (3.0 - 2.0 * k);                   // smoothstep: rounder blobs, darker low half
    k = pow(k, 1.8);                               // push the dark side down: a wallpaper, not a lamp
    return mix(base, accent, k * 0.85);
}

// Mode 3: spectrum. Vertical bars whose heights are pseudo-noise of (bar index, time), standing on a
// horizon line with a damped mirror image below it — the Winamp look, monochrome in the palette.
vec3 spectrum(vec2 uv, float t, float scale, vec3 base, vec3 accent) {
    const float horizon = 0.72;
    float bars = floor(mix(28.0, 72.0, clamp(scale, 0.0, 1.0)));  // params.y sets the bar count
    float x = uv.x * bars;
    float idx = floor(x);
    float f = fract(x);
    // Body mask with a gap between neighbours, else neighbouring bars merge into a solid block.
    float body = smoothstep(0.0, 0.08, f) * smoothstep(1.0, 0.92, f);
    // Heights only refresh ~7 times a second and cross-fade between slots, so the motion reads as
    // bouncing bars instead of per-frame noise.
    float tt = t * 7.0;
    float slot = floor(tt);
    float h = 0.06 + 0.30 * mix(hash21(vec2(idx, slot)), hash21(vec2(idx, slot + 1.0)), fract(tt));
    // Below the horizon the same profile is evaluated at the mirrored height and damped; that is
    // the cheap reflection — no second pass, and it stays inside the palette.
    float below = step(horizon, uv.y);
    float y = mix(uv.y, 2.0 * horizon - uv.y, below);
    float inside = step(y, horizon) * step(horizon - h, y);
    float fade = exp(-abs(y - horizon) * 2.2) * mix(1.0, 0.45, below);
    float halo = exp(-abs(uv.y - horizon) * 60.0) * 0.6;          // the horizon line itself
    float k = clamp(inside * body * fade + halo * 0.5, 0.0, 1.0);
    return mix(base * 0.85, accent, k);                            // floor darker than the ground
}

void main() {
    int mode = int(v_params.x + 0.5);
    vec3 base = v_color.rgb;
    vec3 accent = v_color2.rgb;
    if (mode == 0) {
        // Flat: byte-identical to clearing the frame to the ground colour, so a skin that wants no
        // wallpaper pays nothing visually and the quad is invisible under the UI.
        out_color = vec4(base, v_color.a);
        return;
    }
    float intensity = clamp(v_params.w, 0.0, 1.0);   // 0 kills the effect, 1 is the tuned default
    float scale = max(v_params.y, 0.05);
    float t = pc.params.w;
    // Aspect-corrected, centred coordinates: rings must stay circles and bars must stay vertical
    // when the window is not square.
    vec2 p = (v_uv - 0.5) * vec2(pc.params.x / max(pc.params.y, 1.0), 1.0);
    vec3 effect = mode == 1 ? tunnel(p, t, scale, base, accent)
                : mode == 2 ? plasma(p, t, scale, base, accent)
                            : spectrum(v_uv, t, scale, base, accent);
    vec3 col = mix(base, effect, intensity);
    // Everything above is built from the two palette colours, so this cap only bites where a mode
    // pushes past them. It is the guard that keeps the brightest background pixel at the accent
    // tint's level instead of drifting to white — text has to stay the brightest thing on screen,
    // and the ground colour is included in the max so a bright skin is never dimmed by its accent.
    float cap = max(max(base.r, max(base.g, base.b)), max(accent.r, max(accent.g, accent.b)));
    col = min(col, vec3(cap));
    out_color = vec4(col, v_color.a);
}
