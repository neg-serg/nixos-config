#version 320 es
precision highp float;

// HyprWindowShade: blocky pixelation, used for the Telegram window while it is
// unfocused (keeps a chat unreadable from the side). surface_size is the drawn
// view's own size in logical pixels, so the block count stays stable across
// resizes instead of swimming with the monitor resolution.

in vec2 v_texcoord;
out vec4 fragColor;

uniform sampler2D tex;
uniform vec2 surface_size;

void main() {
    const float BLOCKS = 64.0;  // blocks along the longer side
    float block = max(surface_size.x, surface_size.y) / BLOCKS;

    vec2 cells = surface_size / block;
    vec2 uv = (floor(v_texcoord * cells) + 0.5) / cells;

    fragColor = texture(tex, clamp(uv, vec2(0.0), vec2(1.0)));
}
