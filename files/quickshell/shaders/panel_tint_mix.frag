#version 440 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D sourceSampler;

layout(std140, binding = 0) uniform qt_ubuf {
    vec4 tintColor;
    vec4 params0; // x=strength, y=featherTop, z=featherBottom, w=unused
};

float featherMix(float feather, float coord) {
    if (feather <= 0.0001) {
        return 1.0;
    }
    return smoothstep(0.0, clamp(feather, 0.0001, 1.0), coord);
}

void main() {
    vec4 base = texture(sourceSampler, qt_TexCoord0);
    float strength = clamp(params0.x, 0.0, 2.0);
    float y = clamp(qt_TexCoord0.y, 0.0, 1.0);
    float fadeTop = featherMix(params0.y, y);
    float fadeBottom = featherMix(params0.z, 1.0 - y);
    float feather = min(fadeTop, fadeBottom);

    float overlay = clamp(tintColor.a * strength * feather, 0.0, 1.0);
    vec3 tinted = mix(base.rgb, tintColor.rgb, overlay);
    // Important: do NOT inherit alpha from the base when the panel is transparent.
    // Ensure the tint contributes visible alpha so it shows on transparent panels.
    float outA = max(base.a, overlay);
    fragColor = vec4(tinted, outA);
}
