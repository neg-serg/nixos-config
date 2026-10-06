#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;
vec2 pOffset;
float pRadius;
float pStrength;
vec4 pColour;
vec2 pTexel;
};

// Halo for a rendered text layer: the layer's own alpha, blurred and tinted.
// Instantiated twice — once with the accent colour and no offset (the glow), once
// with a dark colour and a small downward offset (the shadow that keeps glyphs
// readable over a busy picture). The sharp layer is drawn on top by the caller.
void main() {
const float PI = 3.14159265;

vec2 texel = pTexel; // 1/texture size, passed in: ESSL 100 has no textureSize()
vec2 centre = qt_TexCoord0 - pOffset * texel;

// Twelve taps on two rings, weighted down for the outer one.
float coverage = texture(source, centre).a;
float wsum = 1.0;

for (int i = 0; i < 12; i++) {
float a = float(i) * (PI / 6.0);
float outer = mod(float(i), 2.0);
float radius = pRadius * (outer < 0.5 ? 0.5 : 1.0);
float w = outer < 0.5 ? 0.9 : 0.5;
vec2 offset = vec2(cos(a), sin(a)) * radius * texel;
coverage += texture(source, centre + offset).a * w;
wsum += w;
}

coverage /= wsum;
float alpha = clamp(coverage * pStrength * pColour.a, 0.0, 1.0);
fragColor = vec4(pColour.rgb, alpha) * qt_Opacity;
}
