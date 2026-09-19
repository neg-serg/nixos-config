#version 320 es
precision highp float;

// HyprWindowShade: an old CRT television — curved glass, scanlines, RGB phosphor
// triads, chroma misalignment and a vignette. Works on a window or a layer.
//
// Uniforms come from the plugin: surface_size keeps the scanline pitch tied to
// pixels rather than to the window's aspect, time makes the beam crawl.

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;
uniform vec2 surface_size;
uniform float time;

void main() {
    // Barrel distortion: the tube bows the picture out at the edges.
    vec2 c = v_texcoord * 2.0 - 1.0;
    float r2 = dot(c, c);
    c *= 1.0 + 0.055 * r2 + 0.03 * r2 * r2;
    vec2 uv = c * 0.5 + 0.5;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);  // the glass edge
        return;
    }

    // Chroma misalignment: the three guns never quite agree.
    vec2 px = 1.0 / max(surface_size, vec2(1.0));
    vec4 base = texture(tex, uv);
    vec4 col;
    col.r = texture(tex, uv + vec2(px.x * 1.5, 0.0)).r;
    col.g = base.g;
    col.b = texture(tex, uv - vec2(px.x * 1.5, 0.0)).b;
    col.a = base.a;

    // Scanlines: dark gaps between the lines, crawling slowly upwards.
    float lines = sin((uv.y * surface_size.y + time * 18.0) * 3.14159 * 0.5);
    col.rgb *= 0.78 + 0.22 * lines * lines;

    // Aperture grille: alternate columns lean towards one phosphor.
    float triad = fract(uv.x * surface_size.x / 3.0);
    col.rgb *= vec3(0.92 + 0.16 * step(0.66, triad),
                    0.92 + 0.16 * step(0.33, triad) * step(triad, 0.66),
                    0.92 + 0.16 * (1.0 - step(0.33, triad)));

    // The picture is dimmer towards the corners, and never truly black.
    float vignette = clamp(1.0 - 0.42 * r2, 0.0, 1.0);
    col.rgb = col.rgb * vignette + vec3(0.015, 0.018, 0.025);

    fragColor = col;
}
