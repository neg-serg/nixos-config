#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

// The glass layer of the tube sprite: what the envelope adds to the screen — its
// reflections, its rim, the light it bends. See NixieTube.qml.
layout(binding = 1) uniform sampler2D source;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;
float pStrength;
};

void main() {
vec3 light = texture(source, qt_TexCoord0).rgb * pStrength;
// Additive: the colour is written with zero alpha, so it lands on the screen
// and hides nothing. A reflection adds light — treating it as opacity is what
// made the tube read as metal.
fragColor = vec4(light * qt_Opacity, 0.0);
}
