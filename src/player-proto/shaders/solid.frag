#version 450
// Rounded box with optional vertical gradient, border and soft shadow.
// params.x = corner radius (px), params.yz = quad size (px), params.w = shadow blur (px).
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 2) in vec4 v_color2;
layout(location = 3) in vec4 v_params;
layout(location = 0) out vec4 out_color;

float rounded_box_sdf(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    vec2 size = v_params.yz;
    vec2 p = v_uv * size - size * 0.5;
    float d = rounded_box_sdf(p, size * 0.5, v_params.x);
    float blur = v_params.w;
    // blur > 0.5 means "shadow": soft falloff growing outwards
    float alpha = blur > 0.5
        ? smoothstep(blur, 0.0, d)
        : smoothstep(0.7, -0.7, d);
    if (alpha <= 0.001) discard;
    vec4 fill = mix(v_color, v_color2, v_uv.y);
    out_color = vec4(fill.rgb, fill.a * alpha);
}
