#version 440 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform qt_ubuf {
    vec4 baseColor;
    vec4 params0; // x=topOpacity, y=opacitySlope
};

void main() {
    float y = clamp(qt_TexCoord0.y, 0.0, 1.0);
    float opacity = clamp(params0.x + params0.y * y, 0.0, 1.0);
    // Use the requested opacity directly, not multiplied by base alpha,
    // so the seam stays visible even when the panel background is transparent.
    fragColor = vec4(baseColor.rgb, opacity);
}
