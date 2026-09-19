#version 320 es
precision highp float;

// HyprWindowShade: film noir — hard monochrome contrast with a little grain and
// a vignette. Cheap, and a good way to take the colour out of a video call.

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;
uniform vec2 surface_size;
uniform float time;

void main() {
    vec4 base = texture(tex, v_texcoord);
    float luma = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));

    // S-curve: crush the shadows, lift the highlights.
    float contrast = clamp((luma - 0.5) * 1.45 + 0.48, 0.0, 1.0);

    // Grain, animated so it reads as film rather than dirt on the glass.
    float grain = fract(sin(dot(v_texcoord * surface_size + floor(time * 24.0) * 7.0,
                                vec2(12.9898, 78.233))) * 43758.5453);
    float level = clamp(contrast + (grain - 0.5) * 0.055, 0.0, 1.0);

    vec3 col = vec3(level) * vec3(1.0, 0.995, 0.985);  // a hair warmer than pure grey

    vec2 c = v_texcoord * 2.0 - 1.0;
    col *= clamp(1.0 - 0.35 * dot(c, c), 0.0, 1.0);

    fragColor = vec4(col, base.a);
}
