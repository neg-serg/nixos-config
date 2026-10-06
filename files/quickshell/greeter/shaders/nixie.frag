#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

// The wallpaper behind the tube, captured by the caller: it is what the glass
// refracts and what the glow lands on.
layout(binding = 1) uniform sampler2D source;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;

vec2 pSize;        // the item: the envelope plus the room the bloom needs
vec2 pBackdrop;    // the size of the sampled wallpaper patch
float pInset;      // how much of pSize is the bloom's room
float pRadius;     // corner radius of the envelope; half the width makes a disc
float pBase;       // height of the metal base band, px (0 = a plain envelope)
float pGlow;       // discharge strength (0 = the tube is on but shows nothing)
float pDigit;      // the lit cathode, 0..9; -1 = nothing is lit
float pBulb;       // 1 = the colon separator: one filled bulb, no numerals
float pWire;       // the cathode wire, as a fraction of the numeral's height
float pStack;      // how visible the unlit cathodes behind the lit one are
float pHighlight;  // light the glass catches
float pWarmth;     // how much of the discharge lands on the glass itself
float pFlicker;    // ignition progress, 1 = struck and steady
vec4 pCore;        // colour of the lit cathode
vec4 pHalo;        // colour of the gas around it
vec4 pGlass;       // the envelope's own tint
vec4 pCathode;     // the unlit wire, seen through the glass
};

// A nixie tube, drawn in one pass over the wallpaper patch behind it.
//
//   * The glass is physical, not painted. What the tube transmits is what it
//     covers with the wallpaper bent by the cylinder's lens; what it reflects
//     grows towards the silhouette with a Fresnel term. That is why the middle of
//     the tube is clear, the edges are bright, and a bright patch of the picture
//     shows up as a bright band inside the glass.
//   * The two reflections a cylinder always shows, the dome, the pinch-off pip
//     and the dense ring where the wall is seen edge-on sit on top of it.
//   * Every numeral is a distance field of the wire it is bent from — a real
//     cathode is a bent wire, not an inked glyph. The lit one glows: a hot core,
//     the gas around it, a violet fringe where it dies out and the light it
//     throws on the glass and on the wallpaper.
//   * Behind the lit cathode the other nine are stacked as the grey wires they
//     are, with the mica washers and the rods that hold the stack together.
//   * The envelope sits on a crimped metal base, which is what a nixie is
//     plugged in by.
//
// Units. The numeral lives in its own square space: x in -0.5..0.5 (its width)
// and y in -1.15..1.15 (its height — a nixie numeral is tall and narrow), both at
// the same scale, so a round wire stays round.
float sdRoundBox(vec2 p, vec2 halfSize, float radius) {
vec2 q = abs(p) - halfSize + radius;
return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
vec2 pa = p - a;
vec2 ba = b - a;
float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
return length(pa - ba * h);
}

// Distance to an arc of the circle c/r running counter-clockwise from a0 to a1.
float sdArc(vec2 p, vec2 c, float r, float a0, float a1) {
vec2 q = p - c;
float rel = mod(atan(q.y, q.x) - a0 + 18.8495559215, 6.28318530718);
if (rel <= a1 - a0) return abs(length(q) - r);
vec2 end0 = c + r * vec2(cos(a0), sin(a0));
vec2 end1 = c + r * vec2(cos(a1), sin(a1));
return min(length(p - end0), length(p - end1));
}

// Distance to an ellipse — the ring a bowl is bent into. Signed inside, so the
// caller takes the absolute value: a cathode is the wire, never the area it
// encloses.
float sdEllipse(vec2 p, vec2 c, vec2 rad) {
vec2 q = (p - c) / rad;
return abs((length(q) - 1.0) * min(rad.x, rad.y));
}

// Wire that was bent keeps a radius at the corner: the joints are rounded by
// about the thickness of the wire, never mitred.
float smin(float a, float b, float k) {
float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
return mix(b, a, h) - k * h * (1.0 - h);
}

// The centre line of one numeral: 1 a mast with a flag, 2 a shoulder and a foot,
// 3 two bowls, 4 a diagonal over a bar, 5 a lid and a bowl, 6 and 9 a bowl and a
// sweep, 7 a lid and a leg, 8 two bowls, 0 an oval.
float digitWire(int digit, vec2 p) {
const float PI = 3.14159265;
if (digit == 0)
return sdEllipse(p, vec2(0.0), vec2(0.30, 0.88));
if (digit == 1)
return smin(sdSegment(p, vec2(0.0, -1.02), vec2(0.0, 1.02)),
            sdSegment(p, vec2(-0.24, 0.55), vec2(0.0, 1.02)), 0.10);
if (digit == 2)
return smin(smin(sdArc(p, vec2(0.0, 0.60), 0.31, 0.0, PI),
                 sdSegment(p, vec2(0.31, 0.60), vec2(-0.32, -1.00)), 0.10),
            sdSegment(p, vec2(-0.35, -1.02), vec2(0.35, -1.02)), 0.10);
if (digit == 3)
return smin(sdArc(p, vec2(0.0, 0.52), 0.52, -1.05, 2.53),
            sdArc(p, vec2(0.0, -0.52), 0.52, -2.09, 1.05), 0.12);
if (digit == 4)
return smin(smin(sdSegment(p, vec2(0.26, 0.95), vec2(-0.31, -0.10)),
                 sdSegment(p, vec2(-0.31, -0.10), vec2(0.32, -0.10)), 0.10),
            sdSegment(p, vec2(0.26, 0.95), vec2(0.26, -1.02)), 0.10);
if (digit == 5)
return smin(smin(sdSegment(p, vec2(-0.30, 1.02), vec2(0.30, 1.02)),
                 sdSegment(p, vec2(-0.30, 1.02), vec2(-0.27, 0.01)), 0.10),
            sdArc(p, vec2(0.0, -0.30), 0.41, -1.25, 2.28), 0.10);
if (digit == 6)
return smin(smin(sdArc(p, vec2(0.0, 0.50), 0.30, 0.0, PI),
                 sdSegment(p, vec2(-0.30, 0.50), vec2(-0.30, -0.52)), 0.10),
            sdEllipse(p, vec2(0.0, -0.52), vec2(0.30, 0.44)), 0.10);
if (digit == 7)
return smin(sdSegment(p, vec2(-0.32, 1.02), vec2(0.32, 1.02)),
            sdSegment(p, vec2(0.28, 1.02), vec2(-0.09, -1.02)), 0.10);
if (digit == 8)
return smin(sdEllipse(p, vec2(0.0, 0.50), vec2(0.27, 0.50)),
            sdEllipse(p, vec2(0.0, -0.50), vec2(0.30, 0.50)), 0.12);
return smin(sdEllipse(p, vec2(0.0, 0.54), vec2(0.30, 0.44)),
            sdSegment(p, vec2(0.30, 0.48), vec2(0.28, -1.02)), 0.10);
}

float hash(vec2 p) {
return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
const float PI = 3.14159265;

vec2 px = qt_TexCoord0 * pSize;
vec2 hs = pSize * 0.5 - vec2(pInset);
vec2 p = px - pSize * 0.5;

	// ==== SECTION GEOMETRY (L1) ====
// --- the envelope's shape ---------------------------------------------
// A cylinder, a shoulder with a fillet and a dome, as one SDF — the glass of a
// nixie is a straight tube with a rounded top, nothing more.
float shoulder = -hs.y + 1.25 * hs.x;
vec2 bodyC = vec2(0.0, (hs.y + shoulder) * 0.5);
float bodyHalfY = (hs.y - shoulder) * 0.5;
float sdBody = sdRoundBox(p - bodyC, vec2(hs.x, bodyHalfY), 2.5);
float sdDome = length(p - vec2(0.0, -hs.y + hs.x)) - hs.x;
float blend = clamp(0.5 + 0.5 * (sdDome - sdBody) / 10.0, 0.0, 1.0);
float sd = mix(sdBody, sdDome, blend) - 10.0 * blend * (1.0 - blend);
float inside = 1.0 - smoothstep(-0.8, 0.8, sd);
float d = -sd;

float xr = clamp(p.x / max(hs.x, 1.0), -1.0, 1.0);
float u = asin(xr) / (PI * 0.5);
float v = clamp(-p.y / max(hs.y, 1.0), -1.0, 1.0);
float grazing = 1.0 - sqrt(max(0.0, 1.0 - xr * xr));

	// ==== END SECTION GEOMETRY (L1) | SECTION GLASS-OPTICS (L2) ====
// --- the picture behind the tube ---------------------------------------
// A thick-walled cylinder is a lens: the picture is squeezed towards the axis,
// and near the silhouette it is pulled hard enough to nearly invert.
float lens = 0.34 * xr / (1.0 - 0.72 * xr * xr);
vec2 uv = (px + pInset + vec2(lens * hs.x, 0.0)) / pBackdrop;
vec3 refract = texture(source, clamp(uv, vec2(0.001), vec2(0.999))).rgb * 0.95 + 0.004;

// --- the glass: as little as it takes ----------------------------------
// Clear glass over a dark room shows almost nothing: the rim, where the wall is
// seen edge-on, two narrow reflections of whatever light there is, the dome and
// the pip the tube was sealed by. Everything else is the picture behind it.
vec3 colour = vec3(0.0);
vec3 glassLight = vec3(0.0);
float alpha = inside * (0.02 + 0.10 * pow(grazing, 2.0));
	// the room: enough of it that the vessel reads as glass over a dark picture
	colour += vec3(0.55, 0.62, 0.78) * inside * (0.010 + 0.075 * pow(grazing, 1.5));

// the wall edge-on: two surfaces with a dark gap between them
float rim = exp(-max(d, 0.0) / 0.8) * inside;
float rimInner = exp(-pow((d - 1.6) / 1.0, 2.0)) * inside;
glassLight += vec3(1.0) * rim * (0.30 + 0.70 * pow(grazing, 2.0));
alpha += rim * 0.22 + rimInner * 0.14;
colour += vec3(0.03, 0.04, 0.06) * (rimInner * 0.5);

// two narrow reflections, and they stop before the dome and the collar
float fade = clamp(1.0 - pow((v - 0.25) / 0.90, 2.0), 0.0, 1.0) * clamp((v + 0.95) / 0.45, 0.2, 1.0);
glassLight += vec3(0.82, 0.88, 1.0) * exp(-pow((abs(u) - 0.76) / 0.11, 2.0)) * inside * fade * 0.55;
glassLight += vec3(0.75, 0.80, 0.95) * exp(-pow((abs(u) - 0.40) / 0.26, 2.0)) * inside * fade * 0.12;

// the dome, and the pip on top of it
float dome = exp(-pow(length((p - vec2(0.0, -hs.y + 0.62 * hs.x)) * vec2(1.0, 1.35)) / (0.62 * hs.x), 2.0));
dome *= clamp(-p.y / hs.y - 0.42, 0.0, 1.0);
glassLight += vec3(0.86, 0.92, 1.0) * dome * 0.30;
alpha += dome * 0.05;
float tip = exp(-pow(length(p - vec2(0.0, -hs.y + 0.09 * hs.x)) / (0.11 * hs.x), 2.0));
glassLight += vec3(0.90, 0.95, 1.0) * tip * 0.25;
alpha += tip * 0.07;

	// ==== END SECTION GLASS-OPTICS (L2) | SECTION INTERNALS (L3) ====
// --- what is inside -----------------------------------------------------
// The numerals' own space: y-up (the tube's y runs down the screen), the width
// of a numeral as the unit on both axes so a round wire stays round. The stack
// lives in the cylinder above the collar, which is where a nixie keeps it.
float unit = 0.46 * hs.y;
vec2 centre = vec2(0.0, -0.075 * hs.y * 2.0);
vec2 dp = vec2(p.x - centre.x, centre.y - p.y) / unit;
float wireR = pWire;
float baseTop = hs.y - pBase;

// the two rods the stack is welded to
float rods = min(abs(abs(p.x) - 0.46 * hs.x), 1e5);
float rodMask = exp(-pow(rods / 1.1, 2.0)) * step(p.y, -0.50 * hs.y) * step(baseTop, p.y);
colour += vec3(0.05, 0.055, 0.07) * rodMask * 1.6;
alpha += rodMask * 0.42;

// the mica washers that hold the stack together: discs, seen edge-on
for (int w = 0; w < 2; w++) {
float wv = (w == 0) ? 0.60 : -0.66;
float line = exp(-pow((v - wv) / 0.022, 2.0)) * inside * step(abs(xr), 0.80);
colour = mix(colour, vec3(0.26, 0.26, 0.29), line * 0.65);
alpha += line * 0.30;
glassLight += vec3(0.9, 0.92, 1.0) * exp(-pow((v - wv + 0.020) / 0.010, 2.0)) * inside * step(abs(xr), 0.80) * 0.12;
}

// the unlit cathodes: nine wires in the stack, drawn as the grey metal they are
float stack = 0.0;
if (pBulb < 0.5) {
for (int i = 0; i < 10; i++) {
if (abs(float(i) - pDigit) < 0.5) continue;
float depth = float(i) - 4.5;
vec2 q = (dp - vec2(depth * 0.010, depth * -0.007)) / (1.0 - 0.012 * abs(depth));
stack = max(stack, (1.0 - smoothstep(-0.003, 0.003, digitWire(i, q) - wireR)) * (1.0 - 0.05 * abs(depth)));
}
stack *= pStack;
float stem = clamp(stack * 1.8, 0.0, 1.0);
colour = mix(colour, pCathode.rgb * 0.16, stem);
alpha = mix(alpha, 0.34, stem * 0.9);
// the lit edge of each wire: a cathode in a lamp is metal, and metal always
// catches some of the room, so the stack reads even over a dark picture
colour += vec3(0.62, 0.66, 0.76) * clamp(stack - 0.35, 0.0, 1.0) * 0.18;
}

	// ==== END SECTION INTERNALS (L3) | SECTION DISCHARGE (L4) ====
// --- the anode: the wire-mesh cage around the stack ----------------------
// The one part of a nixie that is always visible: a fine mesh cylinder between
// the numerals and the glass. It glows where the discharge touches it.
float cageR = 0.74 * hs.x;
float cageTop = -0.52 * hs.y;
float cageBottom = baseTop - 0.9 * hs.x;
vec3 cageGlow = vec3(0.0);
float grid = 0.0;
if (p.y > cageTop && p.y < cageBottom) {
float uu = asin(clamp(p.x / cageR, -0.999, 0.999)) / (PI * 0.5);
float wireV = exp(-pow(abs(fract(uu * 13.0) - 0.5) * 2.0 / 0.26, 2.0));
float wireH = exp(-pow(abs(fract(p.y / 4.0) - 0.5) * 2.0 / 0.28, 2.0));
float rails = exp(-pow((abs(p.x) - cageR) / 1.0, 2.0));
grid = max(max(wireV, wireH * 0.65), rails);
grid *= step(abs(p.x), cageR);
// the discharge lives inside the cage: the mesh glows where it is touched
float near = exp(-max(digitWire(int(max(pDigit, 0.0) + 0.5), dp) - wireR, 0.0) / 0.08) * step(-0.5, pDigit);
cageGlow = pHalo.rgb * near * pGlow * 0.30;
// Metal blocks the picture instead of adding to it: the mesh darkens what is
// behind it and catches one lit edge from the left.
colour = mix(colour, vec3(0.020, 0.022, 0.030) + cageGlow, grid * 0.45);
alpha = mix(alpha, 0.45, grid * 0.45);
colour += vec3(0.60, 0.64, 0.72) * clamp(grid - 0.45, 0.0, 1.0) * 0.16;
}

	// ==== END SECTION (cage is L3 too) | SECTION DISCHARGE (L4) ====
// --- the discharge --------------------------------------------------------
// The lit cathode is a wire: a thin, saturated, almost white-hot line, and the
// gas around it. Nothing else on the tube is this bright.
vec3 add = vec3(0.0);
float gasMap = 0.0;
if (pBulb > 0.5) {
float bulb = length(p) - 0.23 * hs.x;
float lit = 1.0 - clamp((bulb + 0.4) / 0.8, 0.0, 1.0);
gasMap = exp(-max(bulb, 0.0) / (0.30 * hs.x)) * 0.60 + exp(-max(bulb, 0.0) / (1.4 * hs.x)) * 0.25;
add += pCore.rgb * lit * 1.20 * pGlow * pFlicker;
add += pHalo.rgb * gasMap * 0.60 * pGlow * pow(pFlicker, 1.4);
} else if (pDigit >= -0.5) {
float wireDist = digitWire(int(pDigit + 0.5), dp) - wireR;
float dist = max(wireDist, 0.0);
float core = 1.0 - clamp((wireDist + 0.0022) / 0.0044, 0.0, 1.0);
// dense at the wire, tight around it, a faint wash inside the cage
float gas = exp(-dist / 0.014) * 1.00 + exp(-dist / 0.038) * 0.26 + exp(-dist / 0.10) * 0.030;
gas *= 0.90 + 0.22 * hash(floor(px / 2.0));
float coreLit = pGlow * pow(pFlicker, 0.5);
float haloLit = pGlow * pow(pFlicker, 1.4);
add += pCore.rgb * core * 1.10 * coreLit;
add += vec3(1.0, 0.96, 0.88) * pow(core, 8.0) * 0.26 * coreLit;
add += pHalo.rgb * gas * 1.10 * haloLit;
// the fringe where the discharge dies out drifts violet
add += vec3(0.78, 0.24, 0.72) * exp(-abs(dist - 0.17) / 0.09) * 0.10 * step(0.06, dist) * haloLit;
// the far wall of the glass catches a squeezed, dim image of the wire
vec2 mp = vec2(-p.x * 0.86, p.y);
vec2 mirror = vec2(mp.x - centre.x, centre.y - mp.y) / unit;
add += pHalo.rgb * exp(-max(digitWire(int(pDigit + 0.5), mirror) - wireR, 0.0) / 0.22) * 0.10 * abs(xr) * haloLit;
gasMap = gas;
colour += cageGlow * 0.25;
}

// exposure: the gas never reaches white, the wire always does
add = vec3(1.0) - exp(-add * 1.25);
float spill = exp(-max(sd, 0.0) / (0.9 * hs.x)) * 0.22 + exp(-max(sd, 0.0) / (3.5 * hs.x)) * 0.04;
colour += add * (inside + spill);
alpha += clamp(gasMap * pGlow * 0.10, 0.0, 0.30) * inside;

	// ==== END SECTION DISCHARGE (L4) | SECTION COLLAR (L5) ====
// --- the collar the tube is plugged in by ---------------------------------
if (pBase > 0.5) {
float bm = inside * clamp((p.y - (baseTop - 1.5)) / 3.0, 0.0, 1.0);
float side = clamp(p.x / max(hs.x, 1.0), -1.0, 1.0);
float uu = asin(clamp(side, -0.999, 0.999)) / (PI * 0.5);
// crimped metal: flutes, lit from the left, its foot going dark
colour = mix(colour, vec3(0.052, 0.055, 0.062) * (1.0 + 0.5 * side), bm);
alpha = mix(alpha, 0.96, bm);
colour += exp(-pow(abs(fract(uu * 14.0) - 0.5) * 2.0 / 0.38, 2.0)) * bm * (0.030 + 0.055 * (0.5 + 0.5 * side));
float edge = exp(-pow((p.y - baseTop) / 1.1, 2.0)) * inside;
colour += vec3(0.72, 0.74, 0.80) * edge * (0.40 + 0.60 * min(pGlow, 1.0));
alpha += edge * 0.35;
colour *= 1.0 - 0.35 * exp(-pow((p.y - (baseTop - 2.2)) / 1.6, 2.0)) * inside;
colour += vec3(1.0) * exp(-pow((p.y - hs.y + 1.2) / 1.2, 2.0)) * inside * 0.09;
}

	// ==== END SECTION COLLAR (L5) | SECTION COMPOSITE (L6) ====
// the glass lights land on the front surface, in front of everything inside
colour += glassLight;

fragColor = vec4(colour + add + refract * clamp(1.0 - alpha, 0.0, 1.0), clamp(alpha, 0.0, 0.98)) * qt_Opacity;
}
// ==== END SECTION COMPOSITE (L6) ====
