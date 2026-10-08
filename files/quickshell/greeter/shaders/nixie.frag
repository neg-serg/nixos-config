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
// Distance to an arc of that ellipse, running counter-clockwise from a0 to a1
// (radians). A bowl of a numeral is a circle stretched to the numeral's own
// proportions, so the arc is measured in the stretched space and scaled back.
float sdEllipseArc(vec2 p, vec2 c, vec2 rad, float a0, float a1) {
vec2 q = (p - c) / rad;
return sdArc(q, vec2(0.0), 1.0, a0, a1) * min(rad.x, rad.y);
}

// Wire that was bent keeps a radius at the corner: the joints are rounded by
// about the thickness of the wire, never mitred.
float smin(float a, float b, float k) {
float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
return mix(b, a, h) - k * h * (1.0 - h);
}

// The centre line of one numeral, all of them bent wire: 1 a mast with a flag,
// 2 a shoulder and a foot, 3 two round bowls, 4 a diagonal over a bar, 5 a lid
// and a round bowl, 6 a hook and one closed loop, 7 a lid and a leg, 8 two
// loops, 9 a bowl and a leg, 0 an oval. The bowls are arcs of circles stretched
// to the numeral's proportions, and every joint is an smin — a cathode was bent
// once, and what it has is radii, not corners.

// The outline of a rectangle whose corners are bent by the radius r: the top,
// the right, the bottom and the left joined by four quadrants of a circle. A
// loop of wire in a drawing font is exactly that — straight sides and bends of
// one radius — and it is built from curves, not from a polyline whose corners
// were softened afterwards.
float sdBentRect(vec2 p, vec2 lo, vec2 hi, float r) {
float d = 1e5;
d = min(d, sdSegment(p, vec2(lo.x + r, hi.y), vec2(hi.x - r, hi.y)));
d = min(d, sdSegment(p, vec2(hi.x, hi.y - r), vec2(hi.x, lo.y + r)));
d = min(d, sdSegment(p, vec2(hi.x - r, lo.y), vec2(lo.x + r, lo.y)));
d = min(d, sdSegment(p, vec2(lo.x, lo.y + r), vec2(lo.x, hi.y - r)));
d = min(d, sdArc(p, vec2(hi.x - r, hi.y - r), r, 0.0, 1.5707963268));
d = min(d, sdArc(p, vec2(lo.x + r, hi.y - r), r, 1.5707963268, 3.1415926536));
d = min(d, sdArc(p, vec2(lo.x + r, lo.y + r), r, 3.1415926536, 4.7123889804));
d = min(d, sdArc(p, vec2(hi.x - r, lo.y + r), r, 4.7123889804, 6.2831853072));
return d;
}

float digitWire(int digit, vec2 p) {
const float PI = 3.14159265;
const float DEG = 0.01745329252;
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
// Two round bowls, one over the other, meeting at the waist: the upper runs
// from its foot counter-clockwise over the right, the top and into the upper
// left, the lower one from the lower left over the right into its own top. Two
// circles pinched together are what a 3 of wire is; five straight strokes read
// as a digital font, which is what this was and what it must not be.
return smin(sdEllipseArc(p, vec2(0.0, 0.52), vec2(0.32, 0.50), 270.0 * DEG, 495.0 * DEG),
            sdEllipseArc(p, vec2(0.0, -0.52), vec2(0.32, 0.50), 225.0 * DEG, 450.0 * DEG), 0.10);
if (digit == 4)
return smin(smin(sdSegment(p, vec2(0.26, 0.95), vec2(-0.31, -0.10)),
                 sdSegment(p, vec2(-0.31, -0.10), vec2(0.32, -0.10)), 0.10),
            sdSegment(p, vec2(0.26, 0.95), vec2(0.26, -1.02)), 0.10);
if (digit == 5)
// The drawing font's 5, bent from one wire: the bar across the top, the stem
// down its left end, the waist, the bowl's right side and the foot, with a
// quadrant of a circle at every turn — one radius, r = 0.20, which is the tenth
// of the numeral's height the reference turns its wire by.
{
float d = sdSegment(p, vec2(-0.159, 0.974), vec2(0.339, 0.974));
d = min(d, sdArc(p, vec2(-0.159, 0.774), 0.20, 1.5707963268, 3.1415926536));
d = min(d, sdSegment(p, vec2(-0.359, 0.774), vec2(-0.359, 0.315)));
d = min(d, sdArc(p, vec2(-0.159, 0.315), 0.20, 3.1415926536, 4.7123889804));
d = min(d, sdSegment(p, vec2(-0.159, 0.115), vec2(0.069, 0.115)));
d = min(d, sdArc(p, vec2(0.069, -0.085), 0.20, 0.0, 1.5707963268));
d = min(d, sdSegment(p, vec2(0.269, -0.085), vec2(0.269, -0.723)));
d = min(d, sdArc(p, vec2(0.069, -0.723), 0.20, 4.7123889804, 6.2831853072));
d = min(d, sdSegment(p, vec2(0.069, -0.923), vec2(-0.359, -0.923)));
return d;
}
if (digit == 6)
// The drawing font's 6: one straight stroke off the top, and the bowl a closed
// loop of four straight sides and four quadrant bends.
return min(sdBentRect(p, vec2(-0.359, -0.923), vec2(0.330, 0.107), 0.20),
           sdSegment(p, vec2(0.155, 0.990), vec2(-0.159, 0.107)));
if (digit == 7)
// A lid and a leg and nothing else — a nixie's 7 is not a bowl with a side —
// with the one corner it has rounded off by a good part of the wire.
return smin(sdSegment(p, vec2(-0.30, 1.00), vec2(0.30, 1.00)),
            sdSegment(p, vec2(0.30, 1.00), vec2(-0.10, -1.02)), 0.14);
if (digit == 8)
// The drawing font's 8: two closed loops of straight sides and quadrant bends,
// the lower one wider than the upper, meeting across the middle.
return min(sdBentRect(p, vec2(-0.290, 0.090), vec2(0.290, 0.996), 0.24),
           sdBentRect(p, vec2(-0.360, -0.996), vec2(0.360, 0.090), 0.24));
if (digit == 9)
// The bowl rides on top and the leg under it is straight. A 9 is a 6 turned
// over, and what tells them apart is which end carries the loop.
return smin(sdEllipse(p, vec2(0.0, 0.52), vec2(0.30, 0.48)),
            sdSegment(p, vec2(0.30, 0.52), vec2(0.29, -0.98)), 0.10);
return smin(sdEllipse(p, vec2(0.0, 0.52), vec2(0.30, 0.48)),
            sdSegment(p, vec2(0.30, 0.52), vec2(0.29, -0.98)), 0.10);
}

float hash(vec2 p) {
return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


// --- metal, with a real reflection -------------------------------------
// A metal is a mirror with a tint: what it looks like is the room it stands in,
// seen along the mirror direction and tinted by the metal's own F0. Nickel is
// (0.56, 0.55, 0.52), steel a shade cooler, and the roughness spreads the
// reflection out. This is what the mesh, the rods and the collar were faking
// with constant colours.
vec3 metal_hit(vec2 px, vec3 n, vec3 v, vec3 f0, float rough) {
vec3 r = reflect(-v, n);
// where that ray lands on the room behind the lamp
vec2 off = vec2(r.x, r.y) / max(-r.z, 0.05) * (0.55 * pSize.x);
vec2 uv = (px + pInset + off) / pBackdrop;
// A metal is a mirror, and a rough one smears the room it reflects. The radius
// below is the roughness's own, so the collar's polish and the mesh's wire do
// not reflect with the same sharpness: five taps in a cross, as the glass does.
vec2 blur = (0.0035 + 0.030 * rough) * vec2(1.0, 0.85);
vec3 env = texture(source, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
env += texture(source, clamp(uv + vec2(blur.x, 0.0), vec2(0.001), vec2(0.999))).rgb;
env += texture(source, clamp(uv - vec2(blur.x, 0.0), vec2(0.001), vec2(0.999))).rgb;
env += texture(source, clamp(uv + vec2(0.0, blur.y), vec2(0.001), vec2(0.999))).rgb;
env += texture(source, clamp(uv - vec2(0.0, blur.y), vec2(0.001), vec2(0.999))).rgb;
env *= 0.2;
// a metal darkens what it does not reflect, and Fresnel takes the edge
float c = clamp(dot(n, v), 0.0, 1.0);
vec3 f = f0 + (vec3(1.0) - f0) * pow(1.0 - c, 5.0);
return env * f;
}

// A reflection off glass or metal is never a mirror image: the surface scatters
// it, and the room behind a lamp is seen smeared. Five taps in a cross spread
// over the radius give that — a sharp single sample is what made the reflection
// read as a pasted image.
vec3 blurred_room(vec2 uv, vec2 radius) {
vec3 acc = texture(source, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
acc += texture(source, clamp(uv + vec2(radius.x, 0.0), vec2(0.001), vec2(0.999))).rgb;
acc += texture(source, clamp(uv - vec2(radius.x, 0.0), vec2(0.001), vec2(0.999))).rgb;
acc += texture(source, clamp(uv + vec2(0.0, radius.y), vec2(0.001), vec2(0.999))).rgb;
acc += texture(source, clamp(uv - vec2(0.0, radius.y), vec2(0.001), vec2(0.999))).rgb;
return acc * 0.2;
}

// Where a ray finds the picture behind the tube. The patch the caller lends is
// the only picture there is, so the wall sits exactly one patch behind the
// glass: a ray that slides sideways by so much of the tube's radius lands on
// the part of the room the eye would see bent there, and nothing has to be
// invented outside the patch. Two distances, because the room has depth and the
// wall does not. At the silhouette the surface turns away from the eye and
// -t.z goes to zero, which would send the offset to infinity and smear the
// picture into a flat band; capping it keeps the edge looking at what it sees.
vec2 glass_offset(vec2 pt, vec3 t, vec3 o, float planeDist) {
vec2 plane = pt - vec2(t.x, t.y) / max(-t.z, 0.06) * planeDist;
vec2 bend = vec2(o.x, o.y) / max(-o.z, 0.06) * planeDist * 0.45 * pRefract;
return plane * pRefract + bend;
}

// --- what the parts are made of ----------------------------------------
// A metal is a mirror tinted by its own F0, and F0 is not a taste: it falls out
// of the metal's n and k at the wavelength you look at it. The parts of a lamp
// that has to survive a discharge and still look like jewellery are plated:
//
//   gold (Au, 550 nm):  n 0.47, k 2.40  ->  F0 (1.00, 0.77, 0.34)
//   rhodium (Rh):       n 2.06, k 5.31  ->  F0 (0.79, 0.79, 0.80)
//   nickel (Ni):        n 1.90, k 3.90  ->  F0 (0.56, 0.55, 0.52)
//
// Rhodium is what a jeweller would put on the anode: it does not tarnish, it
// survives the gas, and it keeps the mesh's own colour neutral, so the only
// colour on it is the discharge. Gold goes where the eye looks for it — the
// collector ring the anode cage hangs from — and nickel stays underneath.
const vec3 F0_GOLD = vec3(1.00, 0.77, 0.34);
const vec3 F0_RHODIUM = vec3(0.79, 0.79, 0.80);
const vec3 F0_NICKEL = vec3(0.56, 0.55, 0.52);

// A hot metal is its own light: Planck's law for the colour, Stefan-Boltzmann
// for the power. Bartlett's fit is the colour of a blackbody in sRGB — close
// enough that a wire at 2550 K comes out at the theme's own #ffa04b, while the
// mesh the discharge heats sits at 900..1100 K and reads as dull red.
vec3 blackbody(float kelvin) {
float t = clamp(kelvin, 1000.0, 40000.0) / 100.0;
float r = (t <= 66.0) ? 255.0 : 329.698727446 * pow(t - 60.0, -0.1332047592);
float g = (t <= 66.0) ? 99.4708025861 * log(t) - 161.1195681661
                      : 288.1221695283 * pow(t - 60.0, -0.0755148492);
float b = (t >= 66.0) ? 255.0
        : (t <= 19.0) ? 0.0
        : 138.5177312231 * log(t - 10.0) - 305.0447927307;
return clamp(vec3(r, g, b) / 255.0, 0.0, 1.0);
}

// How much a surface at this temperature throws, against the temperature the
// tube is drawn at (2550 K, the wire). The fourth power is the physics; the cap
// is exposure — a knob turned all the way up must not blow the frame out.
float heat_power(float kelvin, float gain) {
return min(pow(clamp(kelvin, 300.0, 6000.0) / 2550.0, 4.0) * gain, 6.0);
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
// the bulb is a cylinder with a hemisphere at each end, both bulging outward
const float BULB_R_MM = 9.5;    // the glass, Ø19 as on the sheet; the cylinder is 16 mm
const float BULB_H_MM = 35.0;   // the whole height
const float COLLAR_H_MM = 0.0;  // there is no base on this lamp
float mm = min((pSize.x - 2.0 * pInset) / boxW, (pSize.y - 2.0 * pInset) / boxH);
mm = max(mm, 0.01);
float bulbR = BULB_R_MM * mm;           // the glass is as wide as the box, Ø21
float bulbH = BULB_H_MM * mm;           // and as tall: cylinder + two hemispheres
// The collar is the sheet's 7 mm, full stop. pBase is only the caller saying
// whether this envelope has one at all (the colon has not), because a caller
// working in its own pixels must not be able to put the base somewhere the
// drawing does not.
float collarH = COLLAR_H_MM * mm;     // no base: the bulb is the whole lamp
float pipR = 1.75 * mm;                 // the seal's pip, Ø3.5 (unused now)
float sdPipUnused = 1e5;

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
// A capsule: hemispheres at both ends, so the top and the bottom of the glass
// are the same shape. That is what a symmetric bulb is.
// p.y = 0 is the middle of the item, and the box is centred on it, so the glass
// is centred on 0. Centring it on boxMid (the box's half height) dropped the
// glass half a box below the numerals, which is what the picture showed.
// The capsule: a rectangle closed by two semicircles. The max(..., 0) is what
// makes the middle a straight-sided body — without it the profile pinches in
// and the lamp reads as two spheres with a waist between them.
float sdBulb = length(vec2(p.x, max(abs(p.y) - (0.5 * bulbH - bulbR), 0.0))) - bulbR;
float sdPip = sdPipUnused;   // no pip on a symmetric bulb
float sd = sdBulb;
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
// The envelope in profile is a rectangle closed by two semicircles, so the
// surface below has TWO caps, one at each end, and the cylinder between them.
// Normals taken from a single cap turned the two hemispheres into two spheres,
// which is what the picture showed.
float capOffset = max(0.5 * bulbH - bulbR, 0.0);          // the cylinder's half length
float capCentre = sign(p.y) * capOffset;                  // the nearest cap's centre
float capDist = max(abs(p.y) - capOffset, 0.0);           // how far into that cap
float capZ = sqrt(max(0.0, R * R - p.x * p.x - capDist * capDist));
vec3 Ncap = normalize(vec3(p.x, capDist * sign(p.y), -capZ));
vec3 Ncyl = normalize(vec3(p.x, 0.0, -sqrt(max(0.0, R * R - p.x * p.x))));
float blend = clamp(capDist / max(0.5 * mm, 1.0), 0.0, 1.0);   // 0 in the cylinder, 1 in a cap
vec3 N3 = normalize(mix(Ncyl, Ncap, blend));
const vec3 VIEW = vec3(0.0, 0.0, -1.0);   // the eye looks along -z, orthographic
// --- the glass ---------------------------------------------------------
// Clear glass over a dark room shows almost nothing: the rim, where the wall is
// seen edge-on, the reflections it catches, the dome and the pip the tube was
// sealed by. Everything else is the picture behind it, bent — and that bend is
// not a painted squeeze but two refractions: the ray bends where it enters the
// wall, crosses the bore, bends again where it leaves the glass, and lands
// somewhere else in the room. What it loses on the way is Fresnel's share plus
// Beer's law through the glass, which is why a thick rim goes green and dark.
// Glass disperses: its index is not one number. Blue bends harder than red by
// about a part in seventy for soda-lime, which is what puts a chromatic fringe
// on the wall of a real tube and a colour on the edge of a thick lens. Three
// rays, one per channel, and the sampling below keeps only the channel its own
// ray carried.
const vec3 GLASS_N = vec3(1.5155, 1.5200, 1.5280);   // red, green, blue
float wall = clamp(pThick, 0.4, 0.9 * R);
vec3 rayIn = reflect(VIEW, N3);
vec3 rayTr = refract(VIEW, N3, 1.0 / GLASS_N.r);
vec3 rayTg = refract(VIEW, N3, 1.0 / GLASS_N.g);
vec3 rayTb = refract(VIEW, N3, 1.0 / GLASS_N.b);
if (dot(rayTr, rayTr) < 1e-8) rayTr = rayIn;   // the wall at the critical angle
if (dot(rayTg, rayTg) < 1e-8) rayTg = rayIn;
if (dot(rayTb, rayTb) < 1e-8) rayTb = rayIn;
vec3 rayT = rayTg;                             // the green ray carries the geometry
// Out of the far wall: it is flat along the axis, so its normal is the axis's
// own, and what leaves is one more refraction — or a total internal reflection,
// which is what makes the wall go bright where the glass is edge-on.
vec3 exitN = (abs(rayT.y) > abs(rayT.x)) ? vec3(0.0, sign(rayT.y), 0.0)
                                         : vec3(sign(rayT.x), 0.0, 0.0);
float cosI = dot(rayT, exitN);
vec3 rayOut = refract(rayT, exitN, GLASS_N.g);
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
vec2 off = glass_offset(p, rayT, rayOut, planeDist);
vec2 offR = glass_offset(p, rayTr, rayOut, planeDist);
vec2 offB = glass_offset(p, rayTb, rayOut, planeDist);
// A cylinder of glass is a lens, not a window: it has power across its axis and
// none along it, so the picture inside is magnified sideways — most of all on
// the axis, and not at all at the wall, where the glass is edge-on. That is the
// magnifying-glass bend, and it is why a nixie's numerals read taller in the
// middle of the tube than they measure on the bench.
float lensK = 1.0 - 0.30 * pRefract * (1.0 - pow(clamp(abs(u), 0.0, 1.0), 2.0));
off  = vec2(off.x  * lensK, off.y);
offR = vec2(offR.x * lensK, offR.y);
offB = vec2(offB.x * lensK, offB.y);
off  = clamp(off,  vec2(-0.75 * R), vec2(0.75 * R));
offR = clamp(offR, vec2(-0.75 * R), vec2(0.75 * R));
offB = clamp(offB, vec2(-0.75 * R), vec2(0.75 * R));
// One channel per ray: that is the dispersion, and it costs two more taps.
vec3 disp;
disp.r = texture(source, clamp((px + pInset + offR) / pBackdrop, vec2(0.001), vec2(0.999))).r;
disp.g = texture(source, clamp((px + pInset + off)  / pBackdrop, vec2(0.001), vec2(0.999))).g;
disp.b = texture(source, clamp((px + pInset + offB) / pBackdrop, vec2(0.001), vec2(0.999))).b;
vec3 refract = disp * absorb;

vec3 colour = vec3(0.0);
vec3 glassLight = vec3(0.0);
float alpha = inside * 0.22 * pow(grazing, 3.0);   // only the silhouette hides the picture
// the body: cold, and a little darker than the picture behind it
colour += vec3(0.003, 0.004, 0.008) * inside * grazing;   // the body is not a filter

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
vec3 room = blurred_room(uvR, vec2(0.035, 0.030) * pRefract);   // the room, smeared
glassLight += (room * 0.90 + 0.002) * min(F, 0.55) * 0.16 * pHighlight;
// two narrow lights the tube always catches, and they stop before the collar
glassLight += vec3(0.82, 0.88, 1.0) * exp(-pow((abs(u) - 0.76) / 0.030, 2.0)) * inside * fade * 0.14 * pHighlight;
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
const float DIGIT_H = 30.0;   // the numerals, mm: almost the whole bulb, as asked
const float DIGIT_W = 14.0;   // and across: the bore is Ø17.2, so this nearly fills it
const float GLYPH_H = 2.04;   // how tall the glyphs in digitWire() are
const float GLYPH_W = 0.85;   // and how wide the box a numeral is drawn in is
// The numerals are 18 mm high on the sheet, and the glyphs in digitWire() run
// from -1.02 to +1.02, i.e. 2.04 units tall, so one unit is 18/2.04 mm. The box
// across is 0.85 units, and the numerals inside it run to about ±0.33, which is
// the 10 mm an IN-12's numeral measures. The wire is a real cathode, and a fat
// one: 0.38 mm to its edge, so 0.76 mm across.
float gy = (DIGIT_H / GLYPH_H) * mm;
float gx = (DIGIT_W / GLYPH_W) * mm;
float gm = sqrt(gx * gy);
float digitMid = 0.5 * (apexY + footY);   // the glass's middle
vec2 centre = vec2(0.0, digitMid);        // and the glyphs are centred on it
vec2 dp = vec2((p.x - centre.x) / gx, (centre.y - p.y) / gy);
// The cathode's radius: the theme says what share of a numeral's height it
// takes (nixieWire), and the numeral is 30 mm on the sheet — 0.0127 of it is
// the 0.38 mm this is drawn at. A real cathode is 0.24 mm; this one is fat on
// purpose, because a stroke that thin reads as a hairline at the login's size.
float wirePx = pWire * DIGIT_H * mm;
float baseTop = footY;

// the two rods the stack is welded to
float rods = min(abs(abs(p.x) - 7.4 * mm), 1e5);      // the stack's rods, clear of the wider numerals
float rodMask = exp(-pow(rods / max(0.8, 0.10 * mm), 2.0)) * step(p.y, apexY + 0.22 * bulbH) * step(baseTop, p.y);
vec3 rodMetal = metal_hit(px, Ncyl, VIEW, vec3(0.56, 0.55, 0.52), 0.25);
colour += rodMetal * rodMask * 1.6;
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
colour += metal_hit(px, Ncyl, VIEW, vec3(0.50, 0.50, 0.53), 0.40) * clamp(stack - 0.35, 0.0, 1.0) * 0.75;
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
float near = exp(-max(digitWire(int(pDigit + 0.5), dp) * gm - wirePx, 0.0) / (1.3 * mm)) * step(-0.5, pDigit);
cageGlow = pHalo.rgb * near * pGlow * 0.60;
// The mesh is a wire in the discharge, so it is hot: 320 K where the gas is
// cold, up to ~1100 K where the arc touches it. At that temperature it is not
// reflecting the room any more, it is making its own light — dull red, and
// strongest right where the numeral it surrounds is lit.
float meshTemp = 320.0 + 780.0 * near * pGlow;
vec3 meshEmit = blackbody(meshTemp) * heat_power(meshTemp, 3.4) * (0.12 + 0.88 * near);
// Metal blocks the picture instead of adding to it: the mesh darkens what is
// behind it and catches one lit edge from the left.
colour = mix(colour, vec3(0.030, 0.034, 0.042) + cageGlow, grid * 0.72);
alpha = mix(alpha, 0.55, grid * 0.55);
// the far half of the same mesh, seen through the tube behind the numeral
float gridBack = max(exp(-pow(abs(fract(uu * 12.0 + 0.5) - 0.5) * 2.0 / 0.16, 2.0)),
                     exp(-pow(abs(fract(p.y / (1.0 * mm) + 0.5) - 0.5) * 2.0 / 0.18, 2.0)) * 0.65);
gridBack *= step(abs(p.x), cageR) * cageFade;
colour = mix(colour, vec3(0.020, 0.022, 0.028), gridBack * 0.34);
alpha = mix(alpha, 0.34, gridBack * 0.30);
colour += metal_hit(px, Ncyl, VIEW, F0_RHODIUM, 0.35) * clamp(grid - 0.45, 0.0, 1.0) * 0.60;
// the mesh's own emission: it lands on the wires and on the gas around them
colour += meshEmit * grid * (0.55 + 0.45 * min(pGlow, 1.0));

// --- the metal insert ---------------------------------------------------
// Two pieces of plated metal that a real lamp has and a drawing does not: the
// ring the anode cage hangs from at the top, and the sleeve the stack is
// welded into at the foot. Both are inside the glass, both are machined, and
// they are what the eye reads as "this thing was made", not printed.
float ringY = cageTop - 0.6 * mm;
float ringMask = exp(-pow((p.y - ringY) / max(0.5, 0.45 * mm), 2.0))
               * step(abs(p.x), cageR + 0.9 * mm) * inside;
if (ringMask > 0.002) {
// a torus seen edge-on: the tube of the ring itself, lit along its own axis
float ringTube = exp(-pow((abs(abs(p.x) - cageR) - 0.0) / max(0.5, 0.45 * mm), 2.0));
vec3 ringMetal = metal_hit(px, Ncyl, VIEW, F0_GOLD, 0.22);
colour = mix(colour, ringMetal * 1.25, ringMask * (0.35 + 0.65 * ringTube));
alpha = mix(alpha, 0.68, ringMask * 0.55);
glassLight += ringMetal * ringMask * ringTube * 0.35 * pHighlight;
colour += blackbody(360.0 + 240.0 * pGlow) * heat_power(360.0 + 240.0 * pGlow, 2.0) * ringMask * 0.12;
}
float sleeveTop = footY + 2.6 * mm;
float sleeve = exp(-pow((p.y - sleeveTop) / max(0.6, 0.5 * mm), 2.0))
             * step(abs(p.x), 5.6 * mm) * inside;
if (sleeve > 0.002) {
// the sleeve is a rhodium-plated cylinder around the stem, and it is the one
// part of the inside that the numerals never cover
float sleeveSide = exp(-pow((abs(p.x) - 5.6 * mm) / max(0.5, 0.45 * mm), 2.0));
vec3 sleeveMetal = metal_hit(px, Ncyl, VIEW, F0_RHODIUM, 0.30);
colour = mix(colour, sleeveMetal * 0.95, sleeve * (0.40 + 0.60 * sleeveSide));
alpha = mix(alpha, 0.72, sleeve * 0.5);
colour += sleeveMetal * sleeve * sleeveSide * min(pGlow, 1.0) * 0.25;
}
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
float gas = exp(-dist / (0.11 * mm)) * 0.14 + exp(-dist / (0.30 * mm)) * 0.02;   // a filament, not a gas tube
gas *= 0.955 + 0.09 * hash(floor(px / 2.0));
float coreLit = pGlow * pow(pFlicker, 0.5);
float haloLit = pGlow * pow(pFlicker, 1.4);
vec3 wireColour = mix(pCore.rgb, vec3(1.0, 0.97, 0.92), pow(core, 4.0) * 0.60);   // directly heated: the metal is the light
		add += wireColour * core * 5.60 * coreLit;   // white-hot, and no wider than the wire itself

add += pHalo.rgb * gas * 0.58 * haloLit;
add += pHalo.rgb * exp(-dist / (2.4 * mm)) * 0.10 * haloLit;   // the soft bloom a hot wire casts
// the fringe where the discharge dies out drifts violet
add += vec3(0.78, 0.24, 0.72) * exp(-abs(dist - 0.35 * mm) / (0.18 * mm)) * 0.045 * step(0.08 * mm, dist) * haloLit;
// The far wall of the glass does catch the wire, but it is a wall and not a
// mirror: the cylinder squeezes the image sideways, two Fresnel passes dim it,
// and the curvature of the far side defocuses it. A crisp flipped copy of the
// numeral inside the tube (which is what this used to be) reads as a second,
// broken digit — the reflection has to be soft enough to be a glow.
vec2 mp = vec2(-p.x * 0.86, p.y);
vec2 mirror = vec2((mp.x - centre.x) / gx, (centre.y - mp.y) / gy);
float wallRefl = exp(-max(digitWire(int(pDigit + 0.5), mirror) * gm - wirePx, 0.0) / (2.7 * mm));
add += pHalo.rgb * wallRefl * 0.055 * pow(abs(xr), 1.5) * inside * haloLit;
gasMap = gas;
colour += cageGlow * 0.25;
}

// exposure: the gas never reaches white, the wire always does
add = vec3(1.0) - exp(-add * 1.55);
float spill = exp(-max(sd, 0.0) / (0.9 * bulbR)) * 0.90
            + exp(-max(sd, 0.0) / (3.0 * bulbR)) * 1.05
            + exp(-max(sd, 0.0) / (9.0 * bulbR)) * 0.55;
vec3 wash = mix(pHalo.rgb, pCore.rgb, 0.65);
// The discharge's light lands on the wallpaper (the spill) — and inside the
// glass it is the light itself, which the composite adds. Adding it here as well
// counted every ray of it twice, which is what fattened the white core to two
// and a half times the wire's own width.
colour += wash * add * spill;
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
vec3 ceramic = vec3(0.032, 0.031, 0.033) * (0.30 + 0.70 * sqrt(max(0.0, 1.0 - side * side)));
ceramic += metal_hit(px, Ncyl, VIEW, vec3(0.29, 0.30, 0.33), 0.45) * 0.55;   // steel: the room, dimmed
ceramic *= 1.0 - 0.20 * exp(-pow((fract(uu * 14.0) - 0.5) * 2.0 / 0.55, 2.0)); // the moulding's crimps
ceramic += vec3(0.045) * exp(-pow((fract(uu * 14.0) - 0.5) * 2.0 / 0.30 + 1.2, 2.0)) * max(0.0, side + 0.4);
colour = mix(colour, ceramic, bm);
alpha = mix(alpha, 0.96, bm);
colour += vec3(0.030) * exp(-pow(abs(fract(uu * 14.0) - 0.5) * 2.0 / 0.30, 2.0)) * bm * (0.5 + 0.5 * side);
float edge = exp(-pow((p.y - baseTop) / 1.1, 2.0)) * insideCollar;
colour += vec3(0.20, 0.20, 0.21) * edge * (0.35 + 0.65 * min(pGlow, 1.0));   // the flange, moulded and matte
alpha += edge * 0.35;
colour *= 1.0 - 0.35 * exp(-pow((p.y - (baseTop - 2.2)) / 1.6, 2.0)) * insideCollar;
colour += vec3(1.0) * exp(-pow((p.y - (boxMid + 0.5 * collarH) + 1.2) / 1.2, 2.0)) * insideCollar * 0.09;
}

// the glass lands on the front surface, in front of everything inside
colour += glassLight * (1.0 - clamp(max(add.r, max(add.g, add.b)) * 0.9, 0.0, 0.85));

fragColor = vec4(colour + add + refract * clamp(1.0 - alpha, 0.0, 1.0) * inside,
		clamp(alpha, 0.0, 0.98)) * qt_Opacity;
}
