#version 450
// Shared vertex shader for every UI pipeline. Pixel coordinates in, NDC out.
// xy = logical resolution, z = text gamma, w = reserved
layout(push_constant) uniform Push { vec4 params; } pc;
layout(location = 0) in vec2 in_pos;      // pixel position (top-left origin)
layout(location = 1) in vec2 in_uv;       // 0..1 across the quad, or atlas coords
layout(location = 2) in vec4 in_color;    // fill colour (top)
layout(location = 3) in vec4 in_color2;   // fill colour (bottom), gradient endpoint
layout(location = 4) in vec4 in_params;   // x: radius, y: width, z: height, w: blur
layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;
layout(location = 2) out vec4 v_color2;
layout(location = 3) out vec4 v_params;
void main() {
    vec2 ndc = (in_pos / pc.params.xy) * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, ndc.y, 0.0, 1.0); // Vulkan NDC: y=-1 is the top edge
    v_uv = in_uv;
    v_color = in_color;
    v_color2 = in_color2;
    v_params = in_params;
}
