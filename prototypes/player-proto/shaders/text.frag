#version 450
// Alpha-masked glyph quads sampling the single-channel glyph atlas.
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 2) in vec4 v_color2;
layout(location = 3) in vec4 v_params;
layout(location = 0) out vec4 out_color;
layout(binding = 0) uniform sampler2D atlas;
void main() {
    float a = texture(atlas, v_uv).r;
    if (a <= 0.004) discard;
    out_color = vec4(v_color.rgb, v_color.a * a);
}
