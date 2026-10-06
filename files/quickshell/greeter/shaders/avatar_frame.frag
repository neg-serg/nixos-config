#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;
float pRadius;
float pRingWidth;
vec4 pRingColour;
float pGlow;
};

// Frames the avatar photo: the image is cut to a rounded box here (radius 0 gives
// the hard, terminal-ish square), with a thin ring just inside the rim and a soft
// halo outside it — the same shape language as the sharp-cornered card.
float sdRoundBox(vec2 p, vec2 halfSize, float radius) {
vec2 q = abs(p) - halfSize + radius;
return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

void main() {
vec2 halfSize = vec2(0.5);
float sd = sdRoundBox(qt_TexCoord0 - 0.5, halfSize, clamp(pRadius, 0.0, 0.45));

float inside = 1.0 - smoothstep(-0.004, 0.004, sd); // ~2 px of edge AA
float ring = smoothstep(-pRingWidth - 0.02, -pRingWidth, sd) * inside;
float halo = (1.0 - inside) * (1.0 - smoothstep(0.0, 0.06, sd)) * pGlow;

vec3 photo = texture(source, qt_TexCoord0).rgb;
vec3 colour = mix(photo, pRingColour.rgb, ring * pRingColour.a);

fragColor = vec4(colour, max(inside, halo * pRingColour.a) * qt_Opacity);
}
