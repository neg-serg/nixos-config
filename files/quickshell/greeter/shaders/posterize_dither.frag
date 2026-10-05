#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D densityMask;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;
vec2 pSize;
float pCell;
float pDither;
float pGamma;
float pMix;
float pMode;
float pDevicePixelRatio;
float pMaskSize;
float pMaskScale;
vec4 pPalette0;
vec4 pPalette1;
vec4 pPalette2;
vec4 pPalette3;
};

// Wallpaper posterisation. Four colours (picked from the image itself, see
// background/BackgroundImage.qml) are distributed over the picture by one of
// three dithering strategies:
//
//   mode 0 — Bayer 4x4, computed arithmetically so the ES 1.00 target compiles
//   mode 1 — blue noise: the void-and-cluster mask in assets/blue_noise.png,
//            one texel per device pixel (see scripts/gen_blue_noise.py)
//   mode 2 — Yliluoma-style: every ordered pair of palette colours is mixed with
//            the mask value and the mix closest to the pixel wins. This is what
//            makes small palettes look like more colours than they contain.
//
// The Bayer offsets are computed instead of looked up, and the pair search uses
// loop indices, which GLSL ES 1.00 accepts as constant index expressions.
float bayerOffset(float x, float y) {
return x < 0.5 ? (y < 0.5 ? 0.0 : 3.0) : (y < 0.5 ? 2.0 : 1.0);
}

float bayer4(vec2 p) {
vec2 m = floor(mod(p, 4.0));
float low = bayerOffset(mod(m.x, 2.0), mod(m.y, 2.0));
float high = bayerOffset(floor(m.x / 2.0), floor(m.y / 2.0));
return (4.0 * low + high) / 16.0;
}

vec3 toLinear(vec3 c) {
return pow(c, vec3(2.2));
}

// Cheap perceptual distance: lightness first, then the two chroma axes of
// (r-g) / (g-b). The palette itself is chosen in Oklab on the CPU; paying for
// cbrt() twelve times per pixel here would not buy anything visible.
float perceptualError(vec3 a, vec3 b) {
vec3 d = a - b;
float dl = dot(d, vec3(0.2126, 0.7152, 0.0722));
float da = d.r - d.g;
float db = d.g - d.b;
return dl * dl * 1.6 + (da * da + db * db) * 0.35;
}

void main() {
vec4 texel = texture(source, qt_TexCoord0);
vec3 rgb = texel.rgb;

vec3 palette[4];
palette[0] = pPalette0.rgb;
palette[1] = pPalette1.rgb;
palette[2] = pPalette2.rgb;
palette[3] = pPalette3.rgb;

float lum = pow(clamp(dot(rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0), pGamma);

// One dither value per device pixel: the mask is sampled at pixel scale, so
// the pattern does not depend on the logical size of the surface.
vec2 devicePixel = qt_TexCoord0 * pSize * pDevicePixelRatio / max(pMaskScale, 0.05);
vec2 maskUv = fract(devicePixel / max(pMaskSize, 1.0));
float maskValue = texture(densityMask, maskUv).r;

vec3 colour;

if (pMode > 1.5) {
// Yliluoma: pick the two-colour mix that lands closest to the pixel.
vec3 target = toLinear(rgb);
vec3 linearPalette[4];
linearPalette[0] = toLinear(palette[0]);
linearPalette[1] = toLinear(palette[1]);
linearPalette[2] = toLinear(palette[2]);
linearPalette[3] = toLinear(palette[3]);

vec3 bestMix = linearPalette[0];
float bestError = 1.0e9;

for (int i = 0; i < 4; i++) {
for (int j = 0; j < 4; j++) {
if (i == j)
continue;
vec3 candidate = mix(linearPalette[i], linearPalette[j], maskValue);
float error = perceptualError(candidate, target);
if (error < bestError) {
bestError = error;
bestMix = candidate;
}
}
}
colour = pow(clamp(bestMix, 0.0, 1.0), vec3(1.0 / 2.2));
} else {
float threshold = pMode > 0.5 ? maskValue : bayer4(devicePixel / max(pCell, 1.0));
float steps = 3.0;
float level = clamp(floor((lum + (threshold - 0.5) * pDither * 1.6) * steps + 0.5), 0.0, steps) / steps;
colour = level < (1.0 / 6.0) ? palette[0]
: (level < 0.5 ? palette[1]
: (level < (5.0 / 6.0) ? palette[2] : palette[3]));
}

colour = mix(colour, mix(colour, rgb, 0.5), pMix);
fragColor = vec4(colour, texel.a) * qt_Opacity;
}
