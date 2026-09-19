#version 320 es
precision highp float;

// HyprWindowShade: dim and desaturate a window while it is not focused.
//
// Attached by files/gui/hypr/hyprwindowshade.lua to the terminal classes. The
// shader stays attached while the window *is* focused (is_active = 1) so focus
// changes blend instead of snapping; HyprShade-compatible interface plus the
// plugin's per-frame uniforms.

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;
uniform float is_active;

void main() {
    vec4 src = texture(tex, v_texcoord);

    float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 muted = mix(src.rgb, vec3(luma), 0.55);  // pull the colour out
    vec3 target = muted * 0.62;                   // and take the light down

    float unfocused = clamp(1.0 - is_active, 0.0, 1.0);
    fragColor = vec4(mix(src.rgb, target, unfocused), src.a);
}
