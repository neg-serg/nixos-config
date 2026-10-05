#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;
float pRingWidth;
vec4 pRingColour;
float pGlow;
};

// Circular avatar: the photo is cut into a disc here (smooth edge, no aliasing),
// with a thin ring just inside the rim and a soft halo outside it.
void main() {
vec2 c = qt_TexCoord0 * 2.0 - 1.0;
float d = length(c);

float disc = 1.0 - smoothstep(0.985, 1.0, d);
float rim = smoothstep(1.0 - pRingWidth - 0.03, 1.0 - pRingWidth, d) * (1.0 - smoothstep(0.985, 1.0, d));
float halo = (1.0 - disc) * (1.0 - smoothstep(1.0, 1.18, d)) * pGlow;

vec4 photo = texture(source, qt_TexCoord0);
vec3 colour = mix(photo.rgb, pRingColour.rgb, rim * pRingColour.a);

fragColor = vec4(colour, max(disc, halo * pRingColour.a) * qt_Opacity);
}
