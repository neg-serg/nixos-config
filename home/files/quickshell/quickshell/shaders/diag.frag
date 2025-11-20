#version 440 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform qt_ubuf {
    vec4 baseColor;
    vec4 accentColor;
    vec4 params0; // x=accentEnabled, y=accentOnRight, z=accentRatio, w=topInset
    vec4 params1; // x=bottomInset, y=tiltNorm, z=opacity
};

void main() {
    float accentEnabled = params0.x;
    float accentOnRight = params0.y;
    float accentRatio = params0.z;
    float topInset = params0.w;
    float bottomInset = params1.x;
    float tiltNorm = params1.y;
    float effectOpacity = params1.z;

    float y = clamp(qt_TexCoord0.y, 0.0, 1.0);
    float inset = clamp(mix(topInset, bottomInset, y), 0.0, 0.49);
    float innerWidth = max(1e-4, 1.0 - inset * 2.0);
    float centerShift = tiltNorm * (y - 0.5);
    float minX = clamp(0.5 - innerWidth * 0.5 + centerShift, 0.0, 1.0);
    float maxX = clamp(0.5 + innerWidth * 0.5 + centerShift, 0.0, 1.0);
    if (minX >= maxX) discard;
    float x = clamp(qt_TexCoord0.x, 0.0, 1.0);
    if (x < minX || x > maxX) discard;

    vec4 color = baseColor * effectOpacity;
    if (accentEnabled > 0.5 && accentRatio > 0.0) {
        float stripeWidth = clamp(accentRatio, 0.0, 1.0) * (maxX - minX);
        if (accentOnRight > 0.5) {
            if (x > maxX - stripeWidth) color = accentColor * effectOpacity;
        } else {
            if (x < minX + stripeWidth) color = accentColor * effectOpacity;
        }
    }
    fragColor = color;
}
