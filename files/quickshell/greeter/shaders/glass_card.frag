#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;
vec2 pCardSize;
float pRadius;
float pBlur;
vec4 pTint;
float pHighlight;
float pRefract;
float pShadow;
float pGrain;
float pLens;
float pChroma;
float pSpecular;
float pPointerStrength;
vec2 pPointer;
};

// Frosted-glass card, drawn in one pass over a padded sample of the wallpaper.
// It paints both the pane and its soft drop shadow, so no second layer is needed:
//   * the backdrop is blurred with two rings of taps,
//   * "liquid glass": the sampling point is pushed along the rounded-box gradient
//     with the strength rising towards the rim, so the edge lenses the backdrop
//     like a thick slab — and the three colour channels are pushed by slightly
//     different amounts, which is what makes the rim read as glass and not as a
//     blurred copy,
//   * a rim specular (top-left light) plus a highlight that follows the pointer,
//   * a top-down sheen and grain over the tint, a soft inner shadow at the bottom,
//   * outside the pane the same SDF feeds a soft drop shadow.
float hash(vec2 p) {
return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float sdRoundBox(vec2 p, vec2 halfSize, float radius) {
vec2 q = abs(p) - halfSize + radius;
return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

void main() {
const float PI = 3.14159265;

vec2 pad = vec2(pBlur * 1.6 + 2.0);
vec2 texSize = pCardSize + pad * 2.0;
vec2 px = qt_TexCoord0 * texSize; // padded texture space, in pixels
vec2 p = px - texSize * 0.5; // origin at the card centre
vec2 halfSize = pCardSize * 0.5;

float sd = sdRoundBox(p, halfSize, pRadius);
float inside = 1.0 - smoothstep(-1.0, 1.0, sd);

// Surface normal from the SDF gradient: the glass bends what is behind it.
vec2 grad = vec2(
sdRoundBox(p + vec2(1.0, 0.0), halfSize, pRadius) - sd,
sdRoundBox(p + vec2(0.0, 1.0), halfSize, pRadius) - sd
);
vec2 normal = grad / max(length(grad), 1e-5);
float bend = pRefract * smoothstep(0.0, 20.0, sd);
vec2 samplePx = px + normal * bend;

// Blur: a centre tap plus two rings, weighted down for the outer ring.
vec3 acc = texture(source, samplePx / texSize).rgb;
float wsum = 1.0;

for (int i = 0; i < 12; i++) {
float a = float(i) * (PI / 6.0);
float outer = mod(float(i), 2.0);
float radius = pBlur * (outer < 0.5 ? 0.55 : 1.0);
float w = outer < 0.5 ? 0.9 : 0.55;
vec2 offset = vec2(cos(a), sin(a)) * radius;
acc += texture(source, (samplePx + offset) / texSize).rgb * w;
wsum += w;
}

vec3 blurred = acc / wsum;
// The pane is a plain, uniform darkening of what is behind it: no local tone
// mapping, nothing that could read as an inverted copy of the picture.
vec3 glass = mix(blurred, pTint.rgb, pTint.a);

// Sheen: light from above, only inside the pane.
float sheen = pHighlight * smoothstep(0.35, -0.55, p.y / max(halfSize.y, 1.0)) * inside;
glass += sheen;

// Rim specular on the lit (top-left) half, and a soft inner shadow where the
// slab ends at the bottom — the two edges that make the rim read as a bevel.
vec2 rimNormal = normalize(p / halfSize + vec2(1e-5));
float lit = clamp(0.5 - 0.5 * (rimNormal.x + rimNormal.y) * 0.7071, 0.0, 1.0);
float rim = smoothstep(-6.0, -0.5, sd) * smoothstep(-1.0, -0.2, sd);
glass += pSpecular * rim * lit * 2.0;
glass *= 1.0 - 0.25 * smoothstep(-1.0, -0.2, sd) * smoothstep(0.25, 0.75, (p.y / halfSize.y));

// Pointer highlight: a soft light that follows the cursor over the pane.
vec2 pointer = (pPointer - 0.5) * pCardSize;
float pointerFalloff = 1.0 - smoothstep(0.0, 0.55 * length(pCardSize), length(p - pointer));
glass += pPointerStrength * pointerFalloff * pointerFalloff;

// Grain: without it the tint reads as a flat rectangle over a photo.
glass += (hash(px * 0.5) - 0.5) * pGrain;

float shadow = (1.0 - inside) * (1.0 - smoothstep(0.0, max(pShadow, 0.001), sd)) * 0.55;
vec3 colour = mix(vec3(0.0), glass, inside);
fragColor = vec4(colour, max(inside, shadow) * qt_Opacity);
}
