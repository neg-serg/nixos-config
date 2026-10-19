#version 450
// Textured quad with rounded corners, used for album art.
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 2) in vec4 v_color2;
layout(location = 3) in vec4 v_params;
layout(location = 0) out vec4 out_color;
layout(binding = 0) uniform sampler2D tex;
float rounded_box_sdf(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}
void main() {
    vec2 size = v_params.yz;
    vec2 p = v_uv * size - size * 0.5;
    float d = rounded_box_sdf(p, size * 0.5, v_params.x);
    float alpha = smoothstep(0.7, -0.7, d);
    if (alpha <= 0.001) discard;
    vec4 texel = texture(tex, v_uv);
    out_color = vec4(texel.rgb * v_color.rgb, texel.a * v_color.a * alpha);
}
