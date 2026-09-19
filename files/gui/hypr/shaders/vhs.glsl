#version 320 es
precision highp float;

// HyprWindowShade: VHS tape — tracking bands dragging sideways, chroma bleed,
// rolling noise and a tired, slightly blown-out picture. time drives it.

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;
uniform vec2 surface_size;
uniform float time;

float hash(float x) {
    return fract(sin(x * 12.9898) * 43758.5453);
}

void main() {
    vec2 uv = v_texcoord;
    vec2 px = 1.0 / max(surface_size, vec2(1.0));

    // Tracking: a few bands crawl up the frame and drag the picture with them.
    float band = sin(uv.y * 9.0 - time * 0.8);
    float tracking = smoothstep(0.86, 1.0, band) * (0.02 + 0.03 * hash(floor(uv.y * 90.0) + floor(time * 3.0)));
    uv.x += tracking;
    uv.y += 0.0015 * sin(time * 1.7 + uv.x * 12.0);  // tape wobble

    // Chroma bleed: colour is stored on a wider, sloppier carrier than luma.
    vec2 bleed = vec2(px.x * 2.5, 0.0);
    vec4 base = texture(tex, uv);
    vec4 col;
    col.r = texture(tex, uv + bleed).r;
    col.g = base.g;
    col.b = texture(tex, uv - bleed).b;
    col.a = base.a;

    // Tape noise, strongest in the shadows.
    float grain = hash(uv.x * surface_size.x + uv.y * surface_size.y * 17.0 + floor(time * 24.0) * 3.1);
    col.rgb += (grain - 0.5) * (0.06 + 0.10 * (1.0 - dot(col.rgb, vec3(0.333))));

    // Audio-head switching: a thin bright bar rolls through every few seconds.
    float roll = fract(uv.y + time * 0.12);
    col.rgb += vec3(0.05) * smoothstep(0.996, 1.0, roll);

    // Washed-out colour and a soft knee instead of hard clipping.
    float luma = dot(col.rgb, vec3(0.2126, 0.7152, 0.0722));
    col.rgb = mix(col.rgb, vec3(luma), 0.25);
    col.rgb = col.rgb / (col.rgb + 0.85) * 1.85;

    fragColor = vec4(clamp(col.rgb, 0.0, 1.0), col.a);
}
