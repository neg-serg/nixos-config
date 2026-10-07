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
float pThick;      // wall thickness of the envelope, px (0 = a shell, no glass)
float pMm;         // px per millimetre: the scale the drawing below is drawn at
float pRefract;    // how hard the envelope bends the picture behind it (1 = the glass's own)
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

// --- the envelope, from the drawing ------------------------------------
// Every number here is off Reflector's IN-12A/B data sheet (1988), in its own
// millimetres: the bulb is Ø19 and stands 28 from its foot to the top of the
// dome, the base is Ø21 and 7 deep, the pip the tube was sealed by is Ø3.5, and
// the whole lamp without its pins is 35 max. pMm turns those millimetres into
// pixels, so the shape below is the tube and not a decoration shaped like one.
// The drawing's box is 21 mm across and 35 mm tall (base included). The item
// the caller laid out is that box plus the pads, and it is the item that has to
// agree with the drawing, not a uniform: an item stretched by its parent would
// otherwise put the metre somewhere else than the millimetres. So the scale is
// the largest one that fits the box inside the item, and the box's centre is the
// item's centre — one frame for the glass, the stack, the mesh and the collar.
float boxW = 21.0, boxH = 35.0;
float mm = min((pSize.x - 2.0 * pInset) / boxW, (pSize.y - 2.0 * pInset) / boxH);
mm = max(mm, 0.01);
float bulbR = 9.5 * mm;                 // the glass, Ø19
float bulbH = 28.0 * mm;                // glass, foot to the top of the dome
// The collar is the sheet's 7 mm, full stop. pBase is only the caller saying
// whether this envelope has one at all (the colon has not), because a caller
// working in its own pixels must not be able to put the base somewhere the
// drawing does not.
float collarH = (pBase > 0.5) ? 7.0 * mm : 0.0;
float pipR = 1.75 * mm;                 // the seal's pip, Ø3.5

float boxMid = 0.5 * boxH * mm;         // the item's centre, and the box's
float pipTop = -boxMid;                 // the sheet's 35 mm is measured to the pip
float footY = boxMid - collarH;         // where the glass meets the collar
float apexY = footY - bulbH;            // the top of the dome
float capY = apexY + bulbR;             // the centre of the dome's cap

// The bulb: a cylinder closed by a hemispherical dome. The shoulder is the
// tangent between them, which is how the drawing's fillet reads at any size.
// y runs down: the dome is where p.y is above the cap's centre, so the flat side
// of the capsule (a cylinder) is below it and the sphere above. Getting this
// backwards puts the dome inside the base and draws the glass as a pane.
float sdBulb = length(vec2(p.x, min(p.y - capY, 0.0))) - bulbR;
float sdPip = length(p - vec2(0.0, pipTop + 0.5 * pipR)) - 0.5 * pipR;  // the nub on the dome
float sd = smin(sdBulb, sdPip, 0.55 * pipR);
float inside = 1.0 - smoothstep(-0.7, 0.7, sd);
float d = -sd;

float xr = clamp(p.x / max(bulbR, 1.0), -1.0, 1.0);
float u = asin(xr) / (PI * 0.5);
float v = clamp(-(p.y - capY) / max(bulbH - bulbR, 1.0), -1.0, 1.0);
float grazing = 1.0 - sqrt(max(0.0, 1.0 - xr * xr));

// --- the surface of the envelope, in 3D --------------------------------
// The tube is a cylinder with a spherical cap, and its axis lies in the plane
// of the screen: what a pixel sees of the wall is at z = 0, so the depth of
// every point on it follows from the radius alone. That is what makes the
// optics solvable here instead of raymarched — the normal is exact, and so is
// the distance a ray travels through the glass.
float R = max(bulbR, 1.0);
float capZ = sqrt(max(0.0, R * R - p.x * p.x - (p.y - capY) * (p.y - capY)));
vec3 Ncap = normalize(vec3(p.x, p.y - capY, -capZ));
vec3 Ncyl = normalize(vec3(p.x, 0.0, -sqrt(max(0.0, R * R - p.x * p.x))));
float blend = clamp(0.5 + 0.5 * (p.y - capY) / max(bulbH - bulbR, 1.0), 0.0, 1.0);
vec3 N3 = normalize(mix(Ncap, Ncyl, blend));
const vec3 VIEW = vec3(0.0, 0.0, -1.0);   // the eye looks along -z, orthographic
// --- the glass ---------------------------------------------------------
// Clear glass over a dark room shows almost nothing: the rim, where the wall is
// seen edge-on, the reflections it catches, the dome and the pip the tube was
// sealed by. Everything else is the picture behind it, bent — and that bend is
// not a painted squeeze but two refractions: the ray bends where it enters the
// wall, crosses the bore, bends again where it leaves the glass, and lands
// somewhere else in the room. What it loses on the way is Fresnel's share plus
// Beer's law through the glass, which is why a thick rim goes green and dark.
const float ETA = 1.0 / 1.52;             // air into glass
float wall = clamp(pThick, 0.4, 0.9 * R);
vec3 rayIn = reflect(VIEW, N3);
vec3 rayT = refract(VIEW, N3, ETA);
if (dot(rayT, rayT) < 1e-8) rayT = rayIn; // the wall at the critical angle
// leaving the glass, in the plane that holds the normal
vec3 exitN = (abs(rayT.y) > abs(rayT.x)) ? vec3(0.0, sign(rayT.y), 0.0)
                                         : vec3(sign(rayT.x), 0.0, 0.0);
float cosI = dot(rayT, exitN);
vec3 rayOut = refract(rayT, exitN, 1.0 / ETA);
float tir = (dot(rayOut, rayOut) < 1e-8) ? 1.0 : 0.0;
if (tir > 0.5) rayOut = reflect(rayT, exitN);  // trapped, and the wall goes bright
float fres = pow(1.0 - clamp(dot(-VIEW, N3), 0.0, 1.0), 5.0);
float F = fres + (1.0 - fres) * (tir + (1.0 - tir) * pow(1.0 - clamp(cosI, 0.0, 1.0), 5.0));
float pathIn = wall / max(max(abs(rayT.x), abs(rayT.y)), 0.02);
vec3 absorb = exp(-(1.0 - pGlass.rgb) * 1.20 * pathIn / R);

// The picture, as the ray for this pixel finds it on the wall behind the tube.
// The patch the caller lends us is the only picture we have, so the wall sits
// exactly one patch behind the glass: a ray that slides sideways by so much of
// the tube's radius lands on the same part of the room the eye would see bent
// there, and nothing has to be invented outside the patch. Two distances,
// because the room has depth and the wall does not.
// At the silhouette the surface turns away from the eye and -ray.z goes to
// zero, which would send the offset to infinity and smear the picture into a
// flat band. Capping it keeps the edge looking at the wall it can see.
float planeDist = 0.30 * pBackdrop.x;     // where the picture the glass bends hangs
float roomDist = 0.16 * pSize.x;          // where the reflections come from
vec2 plane = p - vec2(rayT.x, rayT.y) / max(-rayT.z, 0.06) * planeDist;
vec2 hv = vec2(rayOut.x, rayOut.y) / max(-rayOut.z, 0.06) * planeDist * 0.45 * pRefract;
vec2 off = plane * pRefract + hv;
off = clamp(off, vec2(-0.75 * R), vec2(0.75 * R));
vec2 uv = (px + pInset + off) / pBackdrop;
vec3 refract = texture(source, clamp(uv, vec2(0.001), vec2(0.999))).rgb * absorb * 1.08 + 0.004;

vec3 colour = vec3(0.0);
vec3 glassLight = vec3(0.0);
float alpha = inside * (0.07 + 0.26 * pow(grazing, 2.0));
// the body: cold, and a little darker than the picture behind it
colour += vec3(0.008, 0.012, 0.022) * inside * (0.35 + 0.65 * grazing);

// the wall edge-on: two surfaces with a dark gap between them
float rim = exp(-max(d, 0.0) / 0.35) * inside;   // the wall seen edge-on: a hairline
float rimInner = exp(-pow((d - 1.6) / 1.0, 2.0)) * inside;
glassLight += vec3(1.0) * rim * (0.10 + 0.55 * pow(grazing, 3.0));
alpha += rim * 0.22 + rimInner * 0.14;
colour += vec3(0.03, 0.04, 0.06) * (rimInner * 0.5);

// what the glass reflects: the room along the mirror direction, weighted by
// Fresnel — the reason the middle of a tube is clear and its edges are not
float fade = clamp(1.0 - pow((v - 0.25) / 0.90, 2.0), 0.0, 1.0) * clamp((v + 0.95) / 0.45, 0.2, 1.0);
vec2 mir = vec2(rayIn.x, rayIn.y) / max(-rayIn.z, 0.06) * roomDist;
mir = clamp(mir, vec2(-0.20 * R), vec2(0.20 * R));
vec2 uvR = (px + pInset + mir) / pBackdrop;
vec3 room = texture(source, clamp(uvR, vec2(0.001), vec2(0.999))).rgb;
glassLight += (room * 0.90 + 0.002) * min(F, 0.55) * 0.16 * pHighlight;
// two narrow lights the tube always catches, and they stop before the collar
glassLight += vec3(0.82, 0.88, 1.0) * exp(-pow((abs(u) - 0.76) / 0.070, 2.0)) * inside * fade * 0.20 * pHighlight;
glassLight += vec3(0.75, 0.80, 0.95) * exp(-pow((abs(u) - 0.40) / 0.22, 2.0)) * inside * fade * 0.045 * pHighlight;

// The pip the tube was sealed by — the one mark every nixie has on top of its
// dome. The dome itself is carried by the rim, which follows its arc.
float tip = exp(-pow(length(p - vec2(0.0, pipTop + 0.5 * pipR)) / (0.30 * pipR), 2.0));
glassLight += vec3(0.90, 0.95, 1.0) * tip * 0.22;
alpha += tip * 0.06;


// --- what is inside -----------------------------------------------------
// The numerals' own space: y-up (the tube's y runs down the screen), the width
// of a numeral as the unit on both axes so a round wire stays round. The stack
// lives in the cylinder above the collar, which is where a nixie keeps it.
const float DIGIT_H = 18.0;   // the numerals, mm, off the sheet
const float DIGIT_W = 10.0;   // and across, mm
const float GLYPH_H = 2.04;   // how tall the glyphs in digitWire() are
const float GLYPH_W = 0.70;   // and how wide
// The numerals are 18 mm high on the sheet, and the glyphs in digitWire() run
// from -1.02 to +1.02, i.e. 2.04 units tall, so one unit is 18/2.04 mm. Across
// they run -0.35..+0.35, and an IN-12 numeral is about 10 mm wide, so the same
// unit is a little wider across the glyph than up it. The wire is a real
// cathode: 0.24 mm across.
float gy = (DIGIT_H / GLYPH_H) * mm;
float gx = (DIGIT_W / GLYPH_W) * mm;
float gm = sqrt(gx * gy);
float digitMid = 0.5 * (apexY + footY);   // the glass's middle
vec2 centre = vec2(0.0, digitMid);        // and the glyphs are centred on it
vec2 dp = vec2((p.x - centre.x) / gx, (centre.y - p.y) / gy);
float wirePx = 0.12 * mm;
float baseTop = footY;

// the two rods the stack is welded to
float rods = min(abs(abs(p.x) - 6.0 * mm), 1e5);      // the stack's rods, 6 mm off the axis
float rodMask = exp(-pow(rods / max(0.8, 0.10 * mm), 2.0)) * step(p.y, apexY + 0.22 * bulbH) * step(baseTop, p.y);
colour += vec3(0.05, 0.055, 0.07) * rodMask * 1.6;
alpha += rodMask * 0.42;

// the mica washers that hold the stack together: discs, seen edge-on
for (int w = 0; w < 2; w++) {
// The two mica washers clamp the stack, so they sit where the numerals end:
// 0.66 of the 18 mm box above and below its middle, which is inside the glass.
float wY = digitMid + ((w == 0) ? -0.66 : 0.66) * 9.0 * mm;
float line = exp(-pow((p.y - wY) / max(0.6, 0.05 * mm), 2.0)) * inside * step(abs(p.x), 0.84 * bulbR);
colour = mix(colour, vec3(0.26, 0.26, 0.29), line * 0.65);
alpha += line * 0.30;
glassLight += vec3(0.9, 0.92, 1.0) * exp(-pow((p.y - wY + 0.4) / max(0.5, 0.02 * mm), 2.0)) * inside * step(abs(p.x), 0.84 * bulbR) * 0.12;
}

// the unlit cathodes: nine wires in the stack, drawn as the grey metal they are
float stack = 0.0;
if (pBulb < 0.5) {
for (int i = 0; i < 10; i++) {
if (abs(float(i) - pDigit) < 0.5) continue;
float depth = float(i) - 4.5;
vec2 q = (dp - vec2(depth * 0.010, depth * -0.007)) / (1.0 - 0.012 * abs(depth));
stack = max(stack, (1.0 - smoothstep(-0.003, 0.003, digitWire(i, q) * gm - wirePx)) * (1.0 - 0.05 * abs(depth)));
}
stack *= pStack;
float stem = clamp(stack * 1.8, 0.0, 1.0);
colour = mix(colour, pCathode.rgb * 0.16, stem);
alpha = mix(alpha, 0.34, stem * 0.9);
// the lit edge of each wire: a cathode in a lamp is metal, and metal always
// catches some of the room, so the stack reads even over a dark picture
colour += vec3(0.62, 0.66, 0.76) * clamp(stack - 0.35, 0.0, 1.0) * 0.18;
}

// --- the anode: the wire-mesh cage around the stack ----------------------
// The one part of a nixie that is always visible: a fine mesh cylinder between
// the numerals and the glass. It glows where the discharge touches it.
float cageR = 8.0 * mm;                 // the anode mesh, Ø16 inside Ø19
float cageTop = apexY + 3.0 * mm;       // the mesh starts under the dome
float cageFade = 0.0;
float cageBottom = footY - 1.0 * mm;    // and stops above the glass's foot
vec3 cageGlow = vec3(0.0);
float grid = 0.0;
if (p.y > cageTop && p.y < cageBottom) {
float uu = asin(clamp(p.x / cageR, -0.999, 0.999)) / (PI * 0.5);
float wireV = exp(-pow(abs(fract(uu * 12.0) - 0.5) * 2.0 / 0.16, 2.0));
float wireH = exp(-pow(abs(fract(p.y / (1.0 * mm)) - 0.5) * 2.0 / 0.18, 2.0));
float rails = exp(-pow((abs(p.x) - cageR) / 1.0, 2.0));
grid = max(max(wireV, wireH * 0.65), rails);
grid *= step(abs(p.x), cageR);
// no seam where the cage ends: the wires fade over the last few px
cageFade = clamp((p.y - cageTop) / 8.0, 0.0, 1.0) * clamp((cageBottom - p.y) / 8.0, 0.0, 1.0)
		 * clamp((cageR - abs(p.x)) / 6.0, 0.0, 1.0);
grid *= cageFade;
// the discharge lives inside the cage: the mesh glows where it is touched
float near = exp(-max(digitWire(int(max(pDigit, 0.0) + 0.5), dp) * gm - wirePx, 0.0) / (2.0 * mm)) * step(-0.5, pDigit);
cageGlow = pHalo.rgb * near * pGlow * 0.55;
// Metal blocks the picture instead of adding to it: the mesh darkens what is
// behind it and catches one lit edge from the left.
colour = mix(colour, vec3(0.030, 0.034, 0.042) + cageGlow, grid * 0.55);
alpha = mix(alpha, 0.42, grid * 0.40);
colour += vec3(0.55, 0.58, 0.64) * clamp(grid - 0.45, 0.0, 1.0) * 0.10;
}

// --- the discharge --------------------------------------------------------
// The lit cathode is a wire: a thin, saturated, almost white-hot line, and the
// gas around it. Nothing else on the tube is this bright.
vec3 add = vec3(0.0);
float gasMap = 0.0;
if (pBulb > 0.5) {
float bulb = length(p - vec2(0.0, 0.0)) - 5.0 * mm;   // the colon, one round bulb
float lit = 1.0 - clamp((bulb + 0.4) / 0.8, 0.0, 1.0);
gasMap = exp(-max(bulb, 0.0) / (0.30 * 5.0 * mm)) * 0.60 + exp(-max(bulb, 0.0) / (1.4 * 5.0 * mm)) * 0.25;
add += pCore.rgb * lit * 1.20 * pGlow * pFlicker;
add += pHalo.rgb * gasMap * 0.60 * pGlow * pow(pFlicker, 1.4);
} else if (pDigit >= -0.5) {
float wireDist = digitWire(int(pDigit + 0.5), dp) * gm - wirePx;
float dist = max(wireDist, 0.0);
// The core is the metal itself: full where the wire's own axis is, nothing at
// its surface. It is a width in millimetres (the cathode is 0.24 mm across),
// not a fraction of a pixel, which is what a white-hot filament is.
float axis = digitWire(int(pDigit + 0.5), dp) * gm;
float core = 1.0 - clamp(axis / max(wirePx, 0.5), 0.0, 1.0);
// dense at the wire, tight around it, a faint wash inside the cage
float gas = exp(-dist / (0.35 * mm)) * 0.46 + exp(-dist / (1.10 * mm)) * 0.15;
gas *= 0.90 + 0.22 * hash(floor(px / 2.0));
float coreLit = pGlow * pow(pFlicker, 0.5);
float haloLit = pGlow * pow(pFlicker, 1.4);
vec3 wireColour = mix(pCore.rgb, vec3(1.0, 0.96, 0.88), pow(core, 8.0) * 0.25);
		add += wireColour * core * 3.00 * coreLit;

add += pHalo.rgb * gas * 0.48 * haloLit;
// the fringe where the discharge dies out drifts violet
add += vec3(0.78, 0.24, 0.72) * exp(-abs(dist - 0.17 * gm) / (0.09 * gm)) * 0.09 * step(0.06 * gm, dist) * haloLit;
// the far wall of the glass catches a squeezed, dim image of the wire
vec2 mp = vec2(-p.x * 0.86, p.y);
vec2 mirror = vec2((mp.x - centre.x) / gx, (centre.y - mp.y) / gy);
add += pHalo.rgb * exp(-max(digitWire(int(pDigit + 0.5), mirror) * gm - wirePx, 0.0) / (2.2 * mm)) * 0.10 * abs(xr) * haloLit;
gasMap = gas;
colour += cageGlow * 0.25;
}

// exposure: the gas never reaches white, the wire always does
add = vec3(1.0) - exp(-add * 1.55);
float spill = exp(-max(sd, 0.0) / (0.9 * bulbR)) * 0.55
            + exp(-max(sd, 0.0) / (3.0 * bulbR)) * 0.60
            + exp(-max(sd, 0.0) / (9.0 * bulbR)) * 0.30;
vec3 wash = mix(pHalo.rgb, pCore.rgb, 0.65);
colour += add * inside + wash * add * spill;
alpha += clamp(gasMap * pGlow * 0.10, 0.0, 0.30) * inside;

// --- the collar the tube is plugged in by ---------------------------------
if (collarH > 0.5) {
// The collar's own mask: a rounded box from the glass's foot down to the box's
// bottom, Ø21 as the drawing has it. It cannot use the bulb's mask — the bulb
// ends where the collar begins.
vec2 bc = vec2(0.0, footY + 0.5 * collarH);
float sdCollar = sdRoundBox(p - bc, vec2(10.5 * mm, 0.5 * collarH), 0.8 * mm);
float insideCollar = 1.0 - smoothstep(-0.8, 0.8, sdCollar);
float bm = insideCollar * clamp((p.y - (baseTop - 1.5)) / 3.0, 0.0, 1.0);
float side = clamp(p.x / max(10.5 * mm, 1.0), -1.0, 1.0);   // the collar, Ø21
float uu = asin(clamp(side, -0.999, 0.999)) / (PI * 0.5);
// crimped metal: flutes, lit from the left, its foot going dark
colour = mix(colour, vec3(0.055, 0.30, 0.42) * (0.55 + 0.45 * side), bm);
alpha = mix(alpha, 0.96, bm);
colour += exp(-pow(abs(fract(uu * 14.0) - 0.5) * 2.0 / 0.38, 2.0)) * bm * (0.030 + 0.055 * (0.5 + 0.5 * side));
float edge = exp(-pow((p.y - baseTop) / 1.1, 2.0)) * insideCollar;
colour += vec3(0.72, 0.74, 0.80) * edge * (0.40 + 0.60 * min(pGlow, 1.0));
alpha += edge * 0.35;
colour *= 1.0 - 0.35 * exp(-pow((p.y - (baseTop - 2.2)) / 1.6, 2.0)) * insideCollar;
colour += vec3(1.0) * exp(-pow((p.y - (boxMid + 0.5 * collarH) + 1.2) / 1.2, 2.0)) * insideCollar * 0.09;
}

// the glass lands on the front surface, in front of everything inside
colour += glassLight * (1.0 - clamp(max(add.r, max(add.g, add.b)) * 0.9, 0.0, 0.85));

fragColor = vec4(colour + add + refract * clamp(1.0 - alpha, 0.0, 1.0) * inside,
		clamp(alpha, 0.0, 0.98)) * qt_Opacity;
}
