#version 440 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform qt_ubuf {
    vec4 baseColor;
    vec4 params0; // x=edgeBase, y=edgeSlope, z=tiltSign (-1 left, +1 right), w=opacity
};

void main() {
    float edgeBase = params0.x;
    float edgeSlope = params0.y;
    float tiltSign = params0.z;
    float effectOpacity = params0.w;
    float y = clamp(qt_TexCoord0.y, 0.0, 1.0);
    float edge = clamp(edgeBase + edgeSlope * y, 0.0, 1.0);
    float x = clamp(qt_TexCoord0.x, 0.0, 1.0);
    float mask = (tiltSign > 0.0) ? step(edge, x) : step(x, edge);
    float intensity = effectOpacity * mask;
    fragColor = baseColor * intensity;
}
