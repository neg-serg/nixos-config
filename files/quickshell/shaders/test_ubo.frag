#version 440 core
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform qt_ubuf {
    vec4 params0;
    vec4 iColor;
};
void main() {
    fragColor = vec4(0.0, 1.0, 0.0, 0.7);
}
