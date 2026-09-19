#version 320 es
precision highp float;

// HyprWindowShade: a monochrome amber-phosphor monitor — the terminal look of
// machines that only ever had one colour. Luma drives an amber ramp, with
// scanlines, a soft glow around bright text and the usual rounded-corner falloff.

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;
uniform vec2 surface_size;
uniform float time;

void main() {
    vec2 px = 1.0 / max(surface_size, vec2(1.0));
    vec4 base = texture(tex, v_texcoord);

    // Glow: a cheap wide sample around the pixel, so lit text bleeds.
    vec3 glow = vec3(0.0);
    glow += texture(tex, v_texcoord + vec2(px.x * 2.0, 0.0)).rgb;
    glow += texture(tex, v_texcoord - vec2(px.x * 2.0, 0.0)).rgb;
    glow += texture(tex, v_texcoord + vec2(0.0, px.y * 2.0)).rgb;
    glow += texture(tex, v_texcoord - vec2(0.0, px.y * 2.0)).rgb;
    glow /= 4.0;

    float luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
    float halo = max(dot(glow, vec3(0.2126, 0.7152, 0.0722)) - luma, 0.0);
    float level = clamp(luma + halo * 0.6, 0.0, 1.0);

    // Amber ramp: deep brown shadows up to a warm near-white highlight.
    vec3 amber_lo = vec3(0.16, 0.06, 0.00);
    vec3 amber_hi = vec3(1.00, 0.72, 0.28);
    vec3 col = mix(amber_lo, amber_hi, pow(level, 0.85));

    // Scanlines and a slow breathing flicker of the beam.
    float lines = sin((v_texcoord.y * surface_size.y + time * 12.0) * 3.14159 * 0.5);
    col *= 0.80 + 0.20 * lines * lines;
    col *= 1.0 + 0.015 * sin(time * 5.0);

    // Corners fall off; keep a faint glow so black is never quite black.
    vec2 c = v_texcoord * 2.0 - 1.0;
    col *= clamp(1.0 - 0.30 * dot(c, c), 0.0, 1.0);
    col += vec3(0.02, 0.008, 0.0);

    fragColor = vec4(clamp(col, 0.0, 1.0), base.a);
}
