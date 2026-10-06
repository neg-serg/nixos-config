#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;
float pScanCount;
float pScanStrength;
float pMaskStrength;
float pAberration;
float pBarrel;
float pBloom;
float pVignette;
float pRollOffset;
float pRollStrength;
float pFlicker;
float pLinesOnly;
};

// Full-screen CRT pass over the rendered login screen: the tube's barrel curve,
// chromatic aberration growing towards the edges, phosphor scanlines and mask,
// a soft bloom, the brightness sweep and a vignette. Everything is scaled from
// the theme, so the effect can be dialled down to "monitor" or up to "arcade".
void main() {
const float PI = 3.14159265;

vec2 uv = qt_TexCoord0;

// pLinesOnly: the pass drawn over the UI. Scanlines, grille, sweep and
// vignette still apply, but nothing is warped and nothing is bloomed, so text
// keeps its shapes. Lines darken, the sweep brightens, and the sign decides
// which of the two this pixel is.
if (pLinesOnly > 0.5) {
float uiScan = 0.5 - 0.5 * sin(uv.y * pScanCount * PI);
float uiGrille = 0.5 - 0.5 * sin(uv.x * pScanCount * PI * 0.85);
float uiLines = clamp(pScanStrength * uiScan + pMaskStrength * uiGrille, 0.0, 1.0);
float uiBand = pRollStrength * exp(-pow(fract(uv.y + pRollOffset) - 0.5, 2.0) * 160.0);
vec2 uiCentre = uv * 2.0 - 1.0;
float uiVignette = pVignette * smoothstep(0.5, 1.35, length(uiCentre));

float luminance = uiBand - uiLines - uiVignette * 0.35;
float alpha = clamp(abs(luminance) * pFlicker, 0.0, 1.0);
vec3 colour = luminance > 0.0 ? vec3(1.0) : vec3(0.0);
fragColor = vec4(colour, alpha * qt_Opacity);
return;
}

// Barrel distortion, with the tube's black border where the surface ends.
vec2 c = uv * 2.0 - 1.0;
c *= 1.0 + pBarrel * dot(c, c);
vec2 suv = c * 0.5 + 0.5;

if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
fragColor = vec4(0.0, 0.0, 0.0, qt_Opacity);
return;
}

// Chromatic aberration: the three guns do not land on the same spot.
float r2 = dot(c, c);
vec2 shift = normalize(c + 1e-5) * pAberration * 0.0025 * (0.35 + r2);
vec3 col = vec3(
texture(source, suv + shift).r,
texture(source, suv).g,
texture(source, suv - shift).b
);

// Bloom: six taps around the pixel, only the bright part contributes.
vec3 glow = vec3(0.0);

for (int i = 0; i < 6; i++) {
float a = float(i) * (PI / 3.0);
vec2 offset = vec2(cos(a), sin(a)) * vec2(0.009, 0.005);
glow += max(texture(source, suv + offset).rgb - 0.72, vec3(0.0));
}

col += glow * pBloom;

// Scanlines and the aperture grille.
float scan = 0.5 - 0.5 * sin(suv.y * pScanCount * PI);
col *= 1.0 - pScanStrength * scan;
float grille = 0.5 - 0.5 * sin(suv.x * pScanCount * PI * 0.85);
col *= 1.0 - pMaskStrength * grille;

// Brightness sweep, vignette and flicker.
float bandPos = fract(suv.y + pRollOffset) - 0.5;
col += pRollStrength * exp(-bandPos * bandPos * 160.0);
col *= 1.0 - pVignette * smoothstep(0.4, 1.3, length(c));
col *= pFlicker;

float alpha = texture(source, suv).a;
fragColor = vec4(col, alpha * qt_Opacity);
}
