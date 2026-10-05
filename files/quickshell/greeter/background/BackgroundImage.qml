pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.lock as Lock

Item {
id: root
clip: true

required property ShellScreen screen;
property real slideAmount: 1.0 - Lock.Controller.bkgSlide
property alias asynchronous: image.asynchronous;
property string wallpaperPath: "file://" + (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/greeter-wallpaper";

readonly property real remainingSize: Math.max(0, image.height - root.height)

// Slow zoom-out on appearance, so the login screen settles instead of snapping.
property real entranceZoom: 1.045
Component.onCompleted: entranceZoom = 1.0
Behavior on entranceZoom {
NumberAnimation {
duration: 1200
easing.type: Easing.OutCubic
}
}

// Fallback when wallpaper is missing — black with a subtle dot grid
Canvas {
anchors.fill: parent

onPaint: {
const ctx = getContext("2d");
const w = width;
const h = height;

// Solid near-black base
ctx.fillStyle = "#0a0a0c";
ctx.fillRect(0, 0, w, h);

// Subtle dot grid
const spacing = 48;
const dotRadius = 1.5;
ctx.fillStyle = "#1a1a20";

for (let x = spacing / 2; x < w; x += spacing) {
for (let y = spacing / 2; y < h; y += spacing) {
ctx.beginPath();
ctx.arc(x, y, dotRadius, 0, Math.PI * 2);
ctx.fill();
}
}
}
}

// The four colours of the posterised wallpaper are picked from the wallpaper
// itself: k-means (weighted by saturation) in Oklab over a 32x32 sample, sorted
// darkest to lightest. That is the perceptual version of "tint the result with
// the image's own colour" — the palette follows the picture instead of a fixed
// ramp. A Canvas is the only pixel access QML gives us, and this runs once per
// wallpaper (greeter.posterizeTint, if set, overrides the whole palette).
property var ditherPalette: []
property color paletteTint: GreeterTheme.posterizeTint.length > 0 ? GreeterTheme.posterizeTint : GreeterTheme.accentColor
readonly property color palette0: root.ditherPalette.length > 0 ? root.ditherPalette[0] : Qt.darker(root.paletteTint, 4.5)
readonly property color palette1: root.ditherPalette.length > 0 ? root.ditherPalette[1] : Qt.darker(root.paletteTint, 1.9)
readonly property color palette2: root.ditherPalette.length > 0 ? root.ditherPalette[2] : root.paletteTint
readonly property color palette3: root.ditherPalette.length > 0 ? root.ditherPalette[3] : Qt.lighter(root.paletteTint, 2.2)

Canvas {
id: paletteProbe
width: 32
height: 32
visible: false

Component.onCompleted: {
const ctx = getContext("2d");
ctx.loadImage(root.wallpaperPath);
}

onImageLoaded: requestPaint()

function srgbToLinear(c) {
return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function linearToSrgb(c) {
return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1.0 / 2.4) - 0.055;
}

function srgbToOklab(r, g, b) {
const lr = srgbToLinear(r);
const lg = srgbToLinear(g);
const lb = srgbToLinear(b);
const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
return [
0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
];
}

function oklabToSrgb(L, A, B) {
const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
const clamp = value => Math.max(0, Math.min(1, value));
return [
clamp(linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
clamp(linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
clamp(linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
];
}

onPaint: {
const ctx = getContext("2d");
ctx.clearRect(0, 0, width, height);
ctx.drawImage(root.wallpaperPath, 0, 0, width, height);

let data;
try {
data = ctx.getImageData(0, 0, width, height).data;
} catch (e) {
return; // some builds taint file:// pixels; the accent fallback stays
}

const points = [];

for (let i = 0; i < data.length; i += 4) {
if (data[i + 3] < 8)
continue;
const r = data[i] / 255;
const g = data[i + 1] / 255;
const b = data[i + 2] / 255;
const max = Math.max(r, g, b);
const min = Math.min(r, g, b);
const saturation = max === 0 ? 0 : (max - min) / max;
const lab = srgbToOklab(r, g, b);
points.push({ L: lab[0], A: lab[1], B: lab[2], weight: 0.25 + saturation * 1.75 });
}

if (points.length < 8)
return;

// Seeds spread over the lightness range, then weighted k-means.
points.sort((p, q) => p.L - q.L);
const k = 4;
const centres = [];

for (let i = 0; i < k; i++) {
const seed = points[Math.floor(points.length * (i + 0.5) / k)];
centres.push({ L: seed.L, A: seed.A, B: seed.B });
}

for (let iteration = 0; iteration < 16; iteration++) {
const sums = [];

for (let i = 0; i < k; i++)
sums.push({ L: 0, A: 0, B: 0, w: 0 });

for (const point of points) {
let best = 0;
let bestDistance = Infinity;

for (let c = 0; c < k; c++) {
const dL = point.L - centres[c].L;
const dA = point.A - centres[c].A;
const dB = point.B - centres[c].B;
const distance = dL * dL + dA * dA + dB * dB;

if (distance < bestDistance) {
bestDistance = distance;
best = c;
}
}

sums[best].L += point.L * point.weight;
sums[best].A += point.A * point.weight;
sums[best].B += point.B * point.weight;
sums[best].w += point.weight;
}

for (let c = 0; c < k; c++) {
if (sums[c].w <= 0)
continue;
centres[c] = {
L: sums[c].L / sums[c].w,
A: sums[c].A / sums[c].w,
B: sums[c].B / sums[c].w
};
}
}

centres.sort((p, q) => p.L - q.L);

// A little extra chroma: k-means on a muted photo returns an almost grey
// ramp, and the screen reads better with the image's hue pushed a bit.
const chroma = GreeterTheme.posterizeChroma;
root.ditherPalette = centres.map(centre => {
const rgb = oklabToSrgb(centre.L, centre.A * chroma, centre.B * chroma);
return Qt.rgba(rgb[0], rgb[1], rgb[2], 1.0);
});
}
}

// Blue-noise thresholds: a void-and-cluster mask generated by
// scripts/gen_blue_noise.py (unique values, no low-frequency clumps), sampled
// one texel per device pixel and tiled by the shader.
Image {
id: noiseMask
source: Qt.resolvedUrl("../assets/blue_noise.png")
smooth: false
mipmap: false
}

ShaderEffectSource {
id: noiseTexture
sourceItem: noiseMask
hideSource: true
live: false
smooth: false
}

// Four colours, dithered, tinted — while posterizeEnabled is on the wallpaper
// never reaches the screen unfiltered (the source image is hidden behind the
// effect). The glass card samples this item, so it blurs the posterised result,
// and the CRT pass sits on top of all of it.
ShaderEffectSource {
id: posterisedSource
sourceItem: image
hideSource: GreeterTheme.posterizeEnabled
live: true
smooth: true
}

ShaderEffect {
id: posterised
anchors.fill: parent
visible: GreeterTheme.posterizeEnabled && image.status === Image.Ready
opacity: image.status === Image.Ready ? 1.0 : 0.0

property Item source: posterisedSource
property Item densityMask: noiseTexture
property vector2d pSize: Qt.vector2d(width, height)
property real pCell: GreeterTheme.posterizeCell
property real pDither: GreeterTheme.posterizeDither
property real pGamma: GreeterTheme.posterizeGamma
property real pMix: GreeterTheme.posterizeMix
property real pMode: GreeterTheme.posterizeModeValue
property real pDevicePixelRatio: root.screen ? root.screen.devicePixelRatio : 1.0
property real pMaskSize: 128
property real pMaskScale: GreeterTheme.posterizeMaskScale
property color pPalette0: root.palette0
property color pPalette1: root.palette1
property color pPalette2: root.palette2
property color pPalette3: root.palette3

fragmentShader: Qt.resolvedUrl("../shaders/posterize_dither.frag.qsb")

Behavior on opacity {
NumberAnimation {
duration: GreeterTheme.animMediumMs
easing.type: Easing.OutCubic
}
}
}

Image {
id: image
asynchronous: root.asynchronous
anchors.horizontalCenter: parent.horizontalCenter
source: root.wallpaperPath

// Cover the full screen while preserving aspect ratio, matching swayimg's
// default scale behaviour: what does not fit is cropped.
width: root.width
height: Math.max(root.height, root.width * (sourceSize.height / Math.max(sourceSize.width, 1)))
fillMode: Image.PreserveAspectCrop
scale: root.entranceZoom
transformOrigin: Item.Center

// Slide up when the password field is focused to reveal more of the bottom.
y: -(root.slideAmount * root.remainingSize)
}
}
