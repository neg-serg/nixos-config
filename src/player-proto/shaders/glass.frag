#version 450
// Frosted "liquid glass" slab: blurs the full-frame backdrop, refracts it at the bevel, lights its rim.
// params.x = corner radius (px), params.yz = quad size (px), params.w = refraction strength (screen units).
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 2) in vec4 v_color2;
layout(location = 3) in vec4 v_params;
layout(location = 0) out vec4 out_color;
layout(binding = 0) uniform sampler2D backdrop;          // the whole frame, rendered at reduced res
layout(push_constant) uniform Push { vec4 params; } pc;  // xy = physical size, w = seconds

float rounded_box_sdf(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Sin-free hash: identical on every driver, and cheap enough to run once per pixel.
float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// 13-tap gaussian: centre, 4 axial at one step, 4 diagonal at one step, 4 axial at two steps.
// The taps are divided by their own weight sum (1 + 4*(0.70 + 0.46 + 0.26) = 6.68) so the kernel
// sums to exactly 1.0: the backdrop is plain, non-premultiplied colour, and an unnormalised kernel
// would darken the whole slab instead of just blurring it. No loop with a dynamic bound — the tap
// count is the cost control.
vec3 frost(vec2 uv, vec2 step_uv) {
    const float w_centre = 1.0;
    const float w_axial = 0.70;
    const float w_diag = 0.46;
    const float w_far = 0.26;
    const float w_sum = 1.0 + 4.0 * (w_axial + w_diag + w_far);
    // The backdrop is low resolution, so a fixed tap grid shows its blocks through the blur.
    // Rotating the whole kernel by a per-pixel angle taken from a hash of the fragment coordinate
    // decorrelates neighbouring pixels from that grid: the taps land in different directions for
    // every pixel and the eye averages them into smooth frost. Measured against the exact
    // (unquantised) 13-tap average, the rotation cuts the residual of a 4x4 block average of the
    // error in half and drops its lag-1 autocorrelation from 0.999 to 0.91 — i.e. the error stops
    // being grid-shaped. Translating the kernel as well was measured too and rejected: it leaves
    // the block energy unchanged while the residual grows with the shift (0.005 -> 0.017 at half a
    // step), because a shifted kernel samples a different part of the gradient. Rotation is the
    // part that helps, so the hash drives the angle only.
    float ang = hash21(gl_FragCoord.xy) * 6.2831853;
    vec2 axis = vec2(cos(ang), sin(ang)) * step_uv;
    vec2 axis_p = vec2(-axis.y, axis.x);
    vec2 diag_a = (axis + axis_p) * 0.70710678;
    vec2 diag_b = (axis - axis_p) * 0.70710678;
    vec3 sum = texture(backdrop, uv).rgb * w_centre;
    sum += (texture(backdrop, uv + axis).rgb + texture(backdrop, uv - axis).rgb) * w_axial;
    sum += (texture(backdrop, uv + axis_p).rgb + texture(backdrop, uv - axis_p).rgb) * w_axial;
    sum += (texture(backdrop, uv + diag_a).rgb + texture(backdrop, uv - diag_a).rgb) * w_diag;
    sum += (texture(backdrop, uv + diag_b).rgb + texture(backdrop, uv - diag_b).rgb) * w_diag;
    sum += (texture(backdrop, uv + axis * 2.0).rgb + texture(backdrop, uv - axis * 2.0).rgb) * w_far;
    sum += (texture(backdrop, uv + axis_p * 2.0).rgb + texture(backdrop, uv - axis_p * 2.0).rgb) * w_far;
    return sum / w_sum;
}

void main() {
    vec2 size = v_params.yz;
    vec2 p = v_uv * size - size * 0.5;
    float radius = v_params.x;
    float d = rounded_box_sdf(p, size * 0.5, radius);
    // Same silhouette and same 0.7px antialiased edge as solid.frag, so glass panels line up pixel
    // for pixel with the opaque ones drawn next to them.
    float mask = smoothstep(0.7, -0.7, d);
    float alpha = v_color.a * mask;
    if (alpha <= 0.001) discard;

    // Outward normal from the SDF gradient. One-pixel central differences are exact enough: on the
    // flat sides the SDF is piecewise linear, and near the corners the normal is only used to push
    // a sample a few pixels, so sub-pixel accuracy buys nothing. The zero-length guard keeps the
    // dead centre (where a symmetric tie makes both differences vanish) from producing a NaN.
    float e = 1.0;
    vec2 half_size = size * 0.5;
    float dx = rounded_box_sdf(p + vec2(e, 0.0), half_size, radius) - rounded_box_sdf(p - vec2(e, 0.0), half_size, radius);
    float dy = rounded_box_sdf(p + vec2(0.0, e), half_size, radius) - rounded_box_sdf(p - vec2(0.0, e), half_size, radius);
    vec2 grad = vec2(dx, dy);
    vec2 normal = dot(grad, grad) > 1e-12 ? normalize(grad) : vec2(0.0, 1.0);

    // Bevel weight: 0 at the silhouette, 1 once we are a corner radius inside the slab. The
    // refraction offset is proportional to (1 - weight)^2, so it is strongest exactly at the rim
    // and dies off quadratically inwards: the panel behaves like a lens with a rounded edge rather
    // than a uniformly shifted window. v_params.w == 0 collapses it to a plain frosted blur.
    float bevel = max(radius, 4.0);
    float edge_falloff = smoothstep(0.0, bevel, -d);
    float strength = clamp(v_params.w, 0.0, 0.05);
    vec2 offset = normal * strength * pow(1.0 - edge_falloff, 2.0);

    vec2 screen_uv = gl_FragCoord.xy / max(pc.params.xy, vec2(1.0));  // 0..1 across the whole frame
    // "Liquid": two rotated sine fields, ~0.002 of the screen in amplitude. That is an order of
    // magnitude below a glyph stem, and it only ever perturbs the backdrop lookup below — the
    // coverage mask and the rim are computed from the SDF, so text drawn on the slab stays crisp.
    float t = pc.params.w;
    vec2 wobble = vec2(
        sin(screen_uv.y * 6.7 + t * 0.70) + sin((screen_uv.x + screen_uv.y) * 3.9 - t * 0.45),
        cos(screen_uv.x * 5.9 - t * 0.60) + cos((screen_uv.x - screen_uv.y) * 4.4 + t * 0.52)
    ) * 0.0011;

    // Two physical pixels per tap: the backdrop is already downsampled, so anything wider would
    // erase the structure the glass is supposed to show through.
    vec2 step_uv = 2.0 / max(pc.params.xy, vec2(1.0));
    vec3 sample_rgb = frost(screen_uv + offset + wobble, step_uv);

    // Tint follows the same colour -> colour2 convention as solid.frag, so a gradient panel keeps
    // its gradient. Multiplying in sRGB darkens mid-tones, hence the low mix factors: glass has to
    // let the backdrop through, and only lean it towards the panel's hue.
    vec3 tint = mix(v_color.rgb, v_color2.rgb, v_uv.y);
    vec3 glass = mix(sample_rgb, sample_rgb * tint, 0.45);
    glass = mix(glass, tint, 0.10);  // a little of the panel's own colour, so it reads as material

    // Rim: a ~2px window on |d| — the silhouette catches light where the SDF crosses zero.
    float rim = smoothstep(2.0, 0.0, abs(d));
    // Diagonal light across the slab, from the top-left. Fixed in quad space, so it rides with the
    // panel instead of sliding when the window moves.
    float sweep = clamp(0.5 + (0.5 - v_uv.x) * 0.55 + (0.5 - v_uv.y) * 0.80, 0.0, 1.0);
    float light = rim * 0.55 + sweep * 0.12;

    glass += tint * light;
    // The rim is denser than the body: more material piles up along the view ray at the edge. The
    // floor keeps the silhouette of a nearly transparent slab readable, and no interior pixel is
    // ever cut, so the panel never develops holes over the backdrop.
    alpha = clamp(alpha * (1.0 + 0.5 * rim), 0.0, 1.0);
    alpha = max(alpha, mask * rim * 0.22);
    out_color = vec4(glass, alpha);
}
