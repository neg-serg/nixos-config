#version 440 core

// Generic triangle clipper: zeroes alpha inside a wedge at one side.
// Parameters:
//  params0.x = wedge width normalized (0..1 of total width)
//  params0.y = slopeUp flag (>=0.5 => bottom-left → top-right, else top-left → bottom-right)
//  params0.z = side (+1.0 = wedge at right edge, -1.0 = wedge at left edge)
//  params0.w = unused
//  params1.x = feather width normalized (soft edge) in [0..0.25]
//  params1.yzw = unused
//  params2.x = debug overlay opacity (0 = off). When > 0, fills the wedge
//              region with a diagnostic color to confirm geometry.
//  params2.y = force shader paint (when > 0, ignore clipping and paint
//              a translucent magenta over the whole rect). Useful to
//              verify that the ShaderEffect is actually rendering.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D sourceSampler;

layout(std140, binding = 0) uniform qt_ubuf {
    vec4 params0;
    vec4 params1;
    vec4 params2; // x=debug opacity
};

void main() {
    vec2 uv = clamp(qt_TexCoord0, 0.0, 1.0);
    vec4 base = texture(sourceSampler, uv);

    // Hard debug: force visible paint over entire rect
    if (params2.y > 0.5) {
        vec3 dbg = vec3(1.0, 0.0, 1.0);
        float a = clamp(params2.x > 0.0 ? params2.x : 0.6, 0.0, 1.0);
        fragColor = vec4(mix(base.rgb, dbg, a), max(base.a, a));
        return;
    }

    float w = clamp(params0.x, 1e-6, 1.0);
    float slopeUp = step(0.5, params0.y);
    float side = params0.z; // +1 = right edge wedge, -1 = left edge wedge
    float t = mix(uv.y, 1.0 - uv.y, slopeUp);

    // Compute signed distance to triangle interior along X.
    // For right-edge wedge: inside if x >= x_line(y).
    // For left-edge wedge:  inside if x <= x_line(y).
    float dInside;
    if (side > 0.0) {
        float x0 = 1.0 - w;
        float xLine = x0 + t * w; // from (x0, y=1 or 0) to 1.0
        dInside = uv.x - xLine;   // >= 0 => inside
    } else {
        float xLine = w * t;      // from 0.0 to w
        dInside = xLine - uv.x;   // >= 0 => inside
    }

    float feather = clamp(params1.x, 0.0, 0.25);
    float aKeep = 1.0 - smoothstep(0.0, max(feather, 1e-5), max(0.0, dInside));

    vec4 outColor = vec4(base.rgb, base.a * aKeep);

    // Optional debug overlay to visualize the wedge region
    float debugA = clamp(params2.x, 0.0, 1.0);
    if (debugA > 0.0) {
        float inside = step(0.0, dInside); // 1.0 inside triangle, 0.0 outside
        vec3 dbg = vec3(1.0, 0.0, 1.0);    // magenta
        float oa = debugA * inside;
        outColor.rgb = mix(outColor.rgb, dbg, oa);
        outColor.a = max(outColor.a, oa);
    }

    fragColor = outColor;
}
