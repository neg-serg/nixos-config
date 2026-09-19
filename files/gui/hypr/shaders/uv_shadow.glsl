#version 320 es
precision highp float;

// HyprWindowShade: ultraviolet shadow for scratchpad windows.
//
// Scratchpads float above the desk, and the compositor draws no shadow in this
// setup (decoration.shadow is off by design), so the depth has to come from
// inside the surface: a violet rim lit from the top edge, brighter while the
// window holds focus, plus a contact shade bleeding inward from the edges.
// Everything stays inside the window box — a fragment shader runs on the
// window's own texture and cannot paint outside it.
//
// Widths are in device pixels via `surface_size`, so the rim keeps the same
// visual weight on a 576 px Telegram panel and a 1904 px teardown window.
// Static effect: no `time` uniform, so no continuous redraws.

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;
uniform vec2  surface_size;
uniform float is_active;

const vec3  UV_COLOR  = vec3(0.545, 0.0, 1.0); // #8B00FF
const float RIM_PX    = 24.0;  // width of the lit rim
const float RIM_POWER = 2.2;   // falloff toward the middle, 1 = linear
const float RIM_ON    = 0.50;  // rim gain while focused
const float RIM_OFF   = 0.26;  // rim gain while unfocused
const float SHADE_PX  = 140.0; // how far the contact shade reaches inward
const float SHADE_MAX = 0.42;  // shade strength right at the edge
const float HAZE      = 0.10;  // violet mixed into the shaded band

void main() {
    vec4 src = texture(tex, v_texcoord);

    // Distance to the nearest edge, in device pixels.
    vec2  px   = v_texcoord * surface_size;
    vec2  d    = min(px, surface_size - px);
    float edge = min(d.x, d.y);

    float rim   = pow(1.0 - clamp(edge / RIM_PX, 0.0, 1.0), RIM_POWER);
    float shade = 1.0 - clamp(edge / SHADE_PX, 0.0, 1.0);

    // Light from above: the top edge catches the violet, the bottom edge takes
    // the shade, the way a real shadow reads.
    float low = clamp(v_texcoord.y, 0.0, 1.0);
    rim   *= mix(1.0, 0.55, low);
    shade *= mix(0.60, 1.0, low);

    float gain = mix(RIM_OFF, RIM_ON, clamp(is_active, 0.0, 1.0));

    vec3 col = src.rgb * (1.0 - SHADE_MAX * shade);
    // Added light is premultiplied by the surface alpha, same as the input.
    col += (UV_COLOR * rim * gain + UV_COLOR * shade * HAZE) * src.a;

    fragColor = vec4(min(col, vec3(src.a)), src.a);
}
