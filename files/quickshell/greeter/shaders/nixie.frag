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
// The lit cathode's temperature, in kelvin: a metal that hot is its own light,
// and blackbody() below turns it into the colour. It takes the vec4 slot the
// old core colour had, padded, because std140 rounds vec4s to 16 bytes and the
// workbench mirrors this block field by field.
// std140: the slot below is 16-byte aligned in the block (it was a vec4, and
// the workbench's struct still reserves the same room), so a bare float here
// would land one slot earlier and read the field before it.
float padCore0;
float pTempK;
float padCore2;
float padCore3;
vec4 pHalo;        // colour of the gas around it
vec4 pGlass;       // the envelope's own tint
vec4 pCathode;     // the unlit wire, seen through the glass
float pThick;      // wall thickness of the envelope, px (0 = a shell, no glass)
float pMm;         // px per millimetre: the scale the drawing below is drawn at
float pRefract;    // how hard the envelope bends the picture behind it (1 = the glass's own)
float pTime;       // seconds of session time: the tube is alive, but slowly
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
// once, and what it has is radii, not corners. The softened radius is the wire's
// own (0.03..0.04 of the glyph's height): an elbow of a bent wire is as thick as
// the wire, and a wider soften swells the joint into a bead.

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

// Which strand of a ribbon-shaped numeral the nearest piece of wire belongs to:
// +1 the one that passes over, -1 the one that goes under, 0 an ordinary piece.
// Only the 8 sets it, and only its own wire reads it.
float wirePass = 0.0;
// The wire's own radius in the numeral's space, filled in by main() from the
// nixieWire token: an elbow of bent wire is as thick as the wire (see digitWire).
float bendK = 0.0;

float digitWire(int digit, vec2 p) {
const float PI = 3.14159265;
const float DEG = 0.01745329252;
if (digit == 0)
return sdEllipse(p, vec2(0.0), vec2(0.30, 0.88));
if (digit == 1)
return smin(sdSegment(p, vec2(0.0, -1.02), vec2(0.0, 1.02)),
            sdSegment(p, vec2(-0.24, 0.55), vec2(0.0, 1.02)), bendK);
if (digit == 2)
return smin(smin(sdArc(p, vec2(0.0, 0.60), 0.31, 0.0, PI),
                 sdSegment(p, vec2(0.31, 0.60), vec2(-0.32, -1.00)), bendK),
            sdSegment(p, vec2(-0.35, -1.02), vec2(0.35, -1.02)), bendK);
if (digit == 3)
// Two round bowls, one over the other, meeting at the waist: the upper runs
// from its foot counter-clockwise over the right, the top and into the upper
// left, the lower one from the lower left over the right into its own top. Two
// circles pinched together are what a 3 of wire is; five straight strokes read
// as a digital font, which is what this was and what it must not be.
return smin(sdEllipseArc(p, vec2(0.0, 0.52), vec2(0.32, 0.50), 270.0 * DEG, 495.0 * DEG),
            sdEllipseArc(p, vec2(0.0, -0.52), vec2(0.32, 0.50), 225.0 * DEG, 450.0 * DEG), bendK);
if (digit == 4)
return smin(smin(sdSegment(p, vec2(0.26, 0.95), vec2(-0.31, -0.10)),
                 sdSegment(p, vec2(-0.31, -0.10), vec2(0.32, -0.10)), bendK),
            sdSegment(p, vec2(0.26, 0.95), vec2(0.26, -1.02)), bendK);
if (digit == 5)
// The user's own Iosevka (Iosevkaneg), measured off the glyph: the bar with
// its short stub at the right end, the stem that leans a little to the left
// down to the waist, and the bowl — open at its upper left — from the stem
// round the right, the bottom and up the left to its terminal below the waist.
// The numbers are the glyph's own: the bar at 0.835 from -0.20 to 0.22, the
// stub down to 0.58, the stem's foot at -0.225/0.19, and the bowl an ellipse
// centred on 0.0/-0.30 with radii 0.26/0.54, run from 205 to 483 degrees.
{
float d = sdSegment(p, vec2(0.22, 0.835), vec2(-0.20, 0.835));       // the bar
d = min(d, sdSegment(p, vec2(0.22, 0.835), vec2(0.22, 0.58)));       // its stub
d = min(d, sdSegment(p, vec2(-0.20, 0.835), vec2(-0.225, 0.19)));    // the stem
d = min(d, sdEllipseArc(p, vec2(0.0, -0.30), vec2(0.26, 0.54), 205.0 * DEG, 483.0 * DEG));
return d;
}
if (digit == 6)
// The 6 of Iosevka — the user's own cut of it, Iosevkaneg — measured off the
// glyph itself: a closed bowl, and a cap over it whose right-hand side stops
// short of the bowl. That gap in the right side is what makes it a 6 and not an
// 8, and every bend here is a quadrant of one radius, r = 0.24.
{
float bowl = sdBentRect(p, vec2(-0.330, -0.920), vec2(0.330, 0.100), 0.24);
float cap = sdSegment(p, vec2(-0.330, -0.140), vec2(-0.330, 0.680));
cap = min(cap, sdArc(p, vec2(-0.090, 0.680), 0.24, 1.5707963268, 3.1415926536));
cap = min(cap, sdSegment(p, vec2(-0.090, 0.920), vec2(0.090, 0.920)));
cap = min(cap, sdArc(p, vec2(0.090, 0.680), 0.24, 0.0, 1.5707963268));
cap = min(cap, sdSegment(p, vec2(0.330, 0.680), vec2(0.330, 0.550)));
return min(bowl, cap);
}
if (digit == 7)
// A lid and a leg and nothing else — a nixie's 7 is not a bowl with a side —
// with the one corner it has rounded off by a good part of the wire.
return smin(sdSegment(p, vec2(-0.30, 1.00), vec2(0.30, 1.00)),
            sdSegment(p, vec2(0.30, 1.00), vec2(-0.10, -1.02)), bendK);
if (digit == 8)
// The 8 as the sign of infinity stood on end: one curve, and the crossing is a
// single point — not two rings set one over the other. The wire goes round the
// top, through the middle and round the bottom, which is what a lemniscate is
// (Gerono's, and the numerals' own space makes it as tall and as narrow as the
// others). Sampled as chords: a hundred and sixty of them put the joints about
// half a millimetre apart, which is under the wire's own width even on the
// login screen at 1x, so nothing of the polygon survives the glow.
//
// The curve passes through the waist twice — once at t = pi/2, once at
// t = 3pi/2 — and a ribbon is what those two passes make. Which of them runs
// over the other is not in a flat drawing, so it is carried by the wire itself:
// the near strand is flagged here and runs a little hotter further down.
{
float d = 1e5;
float best = 0.0;
vec2 prev = vec2(0.0, 1.02);
for (int i = 1; i <= 160; i++) {
float t = float(i) / 160.0 * 6.2831853072;
vec2 q = vec2(0.420 * sin(2.0 * t), 1.020 * cos(t));
float piece = sdSegment(p, prev, q);
if (piece < d) {
d = piece;
best = float(i);
}
prev = q;
}
// 40 is t = pi/2, 120 is t = 3pi/2; the windows are wide enough to cover the
// crossing and smooth enough that the flag reads as a twist, not as a step.
wirePass = 1.0 - smoothstep(6.0, 30.0, abs(best - 40.0))
         - (1.0 - smoothstep(6.0, 30.0, abs(best - 120.0)));
return d;
}
if (digit == 9)
// The bowl rides on top and the leg under it is straight. A 9 is a 6 turned
// over, and what tells them apart is which end carries the loop.
return smin(sdEllipse(p, vec2(0.0, 0.52), vec2(0.30, 0.48)),
            sdSegment(p, vec2(0.30, 0.52), vec2(0.29, -0.98)), bendK);
return smin(sdEllipse(p, vec2(0.0, 0.52), vec2(0.30, 0.48)),
            sdSegment(p, vec2(0.30, 0.52), vec2(0.29, -0.98)), bendK);
}

// The wire's two ends, in the numeral's own space: where it leaves the figure
// for the stack's rods, which is where it is held, and so where heat conducts
// out of it. A closed loop carries its seam twice — that one point is both
// ends, and the wire is coldest there and hottest half a run away from it.
vec4 digitEnds(int digit) {
if (digit == 0) return vec4(0.0, -0.88, 0.0, -0.88);
if (digit == 1) return vec4(0.0, -1.02, -0.24, 0.55);
if (digit == 2) return vec4(-0.31, 0.60, 0.35, -1.02);
if (digit == 3) return vec4(-0.226, 0.874, -0.226, -0.874);
if (digit == 4) return vec4(0.32, -0.10, 0.26, -1.02);
if (digit == 5) return vec4(0.22, 0.58, -0.236, -0.50);
if (digit == 6) return vec4(-0.33, -0.14, 0.33, 0.55);
if (digit == 7) return vec4(-0.30, 1.00, -0.10, -1.02);
if (digit == 8) return vec4(0.0, 1.02, 0.0, 1.02);
if (digit == 9) return vec4(0.30, 0.52, 0.29, -0.98);
return vec4(0.0, 1.02, 0.0, -1.02);
}

// The wire cools towards its ends: how much of its temperature it loses where
// it is held, and over what distance (in the numeral's own units) it recovers.
const float HEAT_END_DROP = 550.0;
const float HEAT_FALLOFF = 0.30;

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
vec2 glass_offset(vec2 pt, vec3 t, vec3 o, float planeDist, float wallGain) {
vec2 plane = pt - vec2(t.x, t.y) / max(-t.z, 0.06) * planeDist;
vec2 bend = vec2(o.x, o.y) / max(-o.z, 0.06) * planeDist * 0.45 * pRefract * wallGain;
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
// The wall is thick now: a hand-blown envelope, not a laboratory bulb. Every
// optical term below is fed by it — a thicker wall absorbs more (Beer), bends
// the picture further (the lens), splits the colours wider (dispersion) and
// shows its two surfaces further apart (the rim), which is what makes the glass
// read as glass instead of as a tinted pane.
const float WALL_MM = 2.3;
float wall = clamp(pThick * (WALL_MM / 0.9), 0.4, 0.9 * R);
// Hand-blown glass is not a machined shell: the wall wanders by a few tenths of
// a millimetre from the shoulder to the foot, and the rim shows it as living
// streaks. Two sines of different periods, so no repeat is visible over the
// tube's height — the eye reads a hand, not a period.
float blown = 1.0 + 0.10 * (0.6 * sin(p.y / (3.1 * mm) + 0.7)
                          + 0.4 * sin(p.y / (1.3 * mm) + 2.4));
wall *= blown;
float wallGain = wall / max(pThick, 0.4);
// A thicker wall bends the picture further and folds its rim deeper, but not in
// full proportion: the square root of the gain keeps the room behind the tube
// recognisable instead of smearing it into the bore.
float wallLens = clamp(pow(wallGain, 0.7), 0.5, 2.2);
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
// Beer's law is per wavelength: the absorption coefficient of iron-bearing
// soda-lime glass climbs towards the red, so a long path loses red first and a
// thick wall reads green-turquoise. The weights are red, green and blue against
// the tube's own tint: red is absorbed 1.35 / 0.85 ~ 1.6x as fast as blue,
// green between them.
// The absorption edge of soda-lime glass proper: red goes first, blue last,
// and the spread between them is what a thick wall shows as a green-turquoise
// core with a warm outer edge.
const vec3 ABSORB_DISP = vec3(1.55, 1.00, 0.70);
vec3 absorb = exp(-(1.0 - pGlass.rgb) * ABSORB_DISP * 2.30 * pathIn / R);

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
vec2 off = glass_offset(p, rayT, rayOut, planeDist, wallLens);
vec2 offR = glass_offset(p, rayTr, rayOut, planeDist, wallLens);
vec2 offB = glass_offset(p, rayTb, rayOut, planeDist, wallLens);
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
// Real glass is never clean. It was wiped with something, it has settled dust,
// it carries a hairline scratch or two, and its walls are not a perfect
// cylinder. All of it is faint, and — invariant I1 — all of it is a hash of the
// pixel and not of the clock, so the login screen still draws the same still.
float smudge = hash(floor(p / (1.4 * mm)) + 17.0);
float dustFine = hash(floor(p / (0.55 * mm)) + 91.0);
// A scratch is one family of hairlines at a shallow angle; the hash decides
// where along them a scratch was actually left.
float scratchU = p.x * 0.28 + p.y;
float scratch = exp(-pow(fract(scratchU / (19.0 * mm)) - 0.5, 2.0) / 0.0007)
              * step(0.80, hash(vec2(floor(scratchU / (19.0 * mm)), 5.0)));
float dust = step(0.9968, dustFine);
// The wall wanders: what the glass shows of the room drifts a pixel with it.
vec2 wobble = vec2(smudge - 0.5, dustFine - 0.5) * 1.2;
off  += wobble;
offR += wobble;
offB += wobble;
// One channel per ray: that is the dispersion, and it costs two more taps.
vec3 disp;
disp.r = texture(source, clamp((px + pInset + offR) / pBackdrop, vec2(0.001), vec2(0.999))).r;
disp.g = texture(source, clamp((px + pInset + off)  / pBackdrop, vec2(0.001), vec2(0.999))).g;
disp.b = texture(source, clamp((px + pInset + offB) / pBackdrop, vec2(0.001), vec2(0.999))).b;
vec3 refract = disp * absorb;
// the smear keeps a little of the room to itself
refract *= 1.0 - 0.06 * smudge;
// A caustic rings the wall: where the glass turns edge-on the lens's mapping
// folds over instead of stretching further, and the picture returns to the eye
// inverted — a second, almost mirrored image along the rim. One more tap at the
// folded offset, carried by grazing so the middle of the tube is untouched.
float caustic = pow(grazing, 3.0) * pRefract * inside * wallLens;
vec2 offC = -off * 1.10;
vec3 causticImg = texture(source, clamp((px + pInset + offC) / pBackdrop, vec2(0.001), vec2(0.999))).rgb;
refract = mix(refract, causticImg * absorb, caustic * 0.70);

vec3 colour = vec3(0.0);
vec3 glassLight = vec3(0.0);
float alpha = inside * 0.18 * pow(grazing, 3.0);   // only the silhouette hides the picture
// the body: cold, and a little darker than the picture behind it
colour += vec3(0.003, 0.004, 0.008) * inside * grazing;   // the body is not a filter

// the wall edge-on: two surfaces with a dark gap between them
float rim = exp(-max(d, 0.0) / 0.35) * inside;   // the wall seen edge-on: a hairline
float rimInner = exp(-pow((d - wall) / max(0.8, 0.20 * wall), 2.0)) * inside;
// The body of the wall, seen edge-on: on a thick-walled tube the silhouette is
// not two hairlines but a band of glass, and that band is where Beer has the
// longest path — it is the green-teal depth of a real envelope.
float wallBody = smoothstep(0.0, 0.45, d) * (1.0 - smoothstep(wall - 0.45, wall, d)) * inside;
glassLight += vec3(1.0) * rim * (0.20 + 0.85 * pow(grazing, 3.0));
alpha += rim * 0.26 + rimInner * 0.16;
colour += vec3(0.02, 0.05, 0.06) * (rimInner * 0.6);
// the wall's own body: the glass colour, taken through its own absorption
colour = mix(colour, vec3(0.010, 0.030, 0.032) * (0.6 + 0.8 * pow(grazing, 2.0)), wallBody * 0.55);
alpha = max(alpha, wallBody * 0.36);

// what the glass reflects: the room along the mirror direction, weighted by
// Fresnel — the reason the middle of a tube is clear and its edges are not
float fade = clamp(1.0 - pow((v - 0.25) / 0.90, 2.0), 0.0, 1.0) * clamp((v + 0.95) / 0.45, 0.2, 1.0);
vec2 mir = vec2(rayIn.x, rayIn.y) / max(-rayIn.z, 0.06) * roomDist;
mir = clamp(mir, vec2(-0.20 * R), vec2(0.20 * R));
vec2 uvR = (px + pInset + mir) / pBackdrop;
vec3 room = blurred_room(uvR, vec2(0.035, 0.030) * pRefract);   // the room, smeared
glassLight += (room * 0.90 + 0.002) * min(F, 0.55) * 0.16 * pHighlight;
// The inner wall is the second mirror in the tube: light crosses the bore,
// reflects off the far wall and leaves through the near one, so the room the
// glass carries arrives twice, displaced by that extra crossing — the weak
// doubled echo a real tube throws beside its bright core. Only the lateral
// direction flips (the wall that reflects is the far side of the cylinder), and
// the second wall plus the longer path take their share through absorb2.
vec2 mir2 = vec2(-rayIn.x, rayIn.y) * 0.55 * roomDist / max(-rayIn.z, 0.06);
mir2 = clamp(mir2, vec2(-0.20 * R), vec2(0.20 * R));
vec3 room2 = blurred_room((px + pInset + mir2) / pBackdrop, vec2(0.050, 0.040) * pRefract);
vec3 absorb2 = exp(-(1.0 - pGlass.rgb) * ABSORB_DISP * 2.00 * 2.0 * pathIn / R);
glassLight += (room2 * 0.90 + 0.002) * min(F, 0.55) * 0.16 * pHighlight * absorb2 * 0.55;
// two narrow lights the tube always catches, and they stop before the collar
glassLight += vec3(0.82, 0.88, 1.0) * exp(-pow((abs(u) - 0.76) / 0.030, 2.0)) * inside * fade * 0.17 * pHighlight;
glassLight += vec3(0.75, 0.80, 0.95) * exp(-pow((abs(u) - 0.40) / 0.22, 2.0)) * inside * fade * 0.055 * pHighlight;
// what was wiped on the glass, what settled on it, and the scratches: each
// catches the light a little differently, which is all the eye needs to read a
// surface as a surface and not as a window
glassLight += vec3(0.90, 0.94, 1.00) * smudge * 0.014 * inside;
glassLight += vec3(1.00, 0.97, 0.88) * dust * 0.050 * inside;
glassLight += vec3(0.86, 0.90, 1.00) * scratch * 0.045 * inside;

// The pip the tube was sealed by — the one mark every nixie has on top of its
// dome. The dome itself is carried by the rim, which follows its arc.
float tip = exp(-pow(length(p - vec2(0.0, pipTop + 0.5 * pipR)) / (0.30 * pipR), 2.0));
glassLight += vec3(0.90, 0.95, 1.0) * tip * 0.22;
alpha += tip * 0.06;


// --- what is inside -----------------------------------------------------
// The numerals' own space: y-up (the tube's y runs down the screen), the width
// of a numeral as the unit on both axes so a round wire stays round. The stack
// lives in the cylinder above the collar, which is where a nixie keeps it.
const float DIGIT_H = 25.0;   // the numerals, mm: a margin at each end of the 35 mm bulb
const float DIGIT_W = 11.7;   // and across, in the sheet's own 18:10 proportions
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
// takes (nixieWire), and the numeral is 25 mm here — 0.036 of it is the 0.90 mm
// this is drawn at, so the wire is 1.80 mm across. A real cathode is
// 0.24 mm; this one is heavy on purpose, because what the eye reads at the
// login's size is the glowing filament, and a hairline reads as nothing.
float wirePx = pWire * DIGIT_H * mm;
bendK = wirePx / gm;   // the bend of a bent wire is its own radius
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

// The stack's own terminals: the two rods end in the eyes the cathode wires are
// welded to, and a lead runs from each eye down the side of the sleeve to the
// press in the glass's foot. A real lamp's whole stack hangs off these two
// joints, and below the mesh there is no other bright metal to read them by.
float leadY = footY - 5.0 * mm;
for (int e = 0; e < 2; e++) {
	// the rods run 7.4 mm either side of the axis, clear of the widest numeral
	float lx = (e == 0) ? -7.4 * mm : 7.4 * mm;
	vec2 lc = vec2(lx, leadY);
	// the eye is a squashed ring, open: the wire is welded through it
	float eyeRing = abs(length((p - lc) / vec2(1.0, 0.78)) - 0.72 * mm) - 0.26 * mm;
	float eyeMask = (1.0 - smoothstep(-0.5, 0.5, eyeRing)) * inside;
	// the lead, from the eye to the foot; inside cuts it where the glass tapers
	float eyeLead = exp(-pow((p.x - lx) / max(0.20 * mm, 0.5), 2.0))
	              * smoothstep(leadY - 0.5 * mm, leadY + 0.5 * mm, p.y) * step(p.y, footY) * inside;
	vec3 eyeMetal = metal_hit(px, Ncyl, VIEW, F0_RHODIUM, 0.24);
	colour = mix(colour, eyeMetal * 1.05, eyeMask + eyeLead * 0.65);
	alpha = mix(alpha, 0.62, eyeMask * 0.85 + eyeLead * 0.45);
	// lit from the left, as the rest of the metal in the tube is
	colour += vec3(0.15, 0.15, 0.16) * (eyeMask + eyeLead * 0.45) * ((e == 0) ? 1.0 : 0.35);
}

// --- what the years put on the glass -------------------------------------
// Two films, both thin and both uneven, because neither was painted on. The
// getter the tube was flashed with condenses on the inside of the dome as a
// silvery mirror; the cathode it has burnt off lands on the glass around the
// foot as a dark, warm film. There is no token for age, so the weights are
// constants here, and a coarse hash makes each film patchy. Both absorb first
// — the picture behind the glass dims through them — and reflect second:
// metal_hit() throws back the same room the rods and the collar reflect.
//
// The getter: a mirror over the top cap, thinning down the cylinder. The cap's
// own sphere is the natural mask; 0.62 is where the film is judged to stop, and
// 0.50 is how much of the picture it hides at its thickest. The sputter is the
// weaker film (0.38) and shorter (about 6.5 mm above the foot).
float domeT = clamp((-(p.y) - capOffset) / max(bulbR, 1.0), 0.0, 1.0);
float getterFilm = smoothstep(0.02, 0.62, domeT) * (0.52 + 0.48 * hash(floor(p / max(1.0, 1.7 * mm))));
float getter = getterFilm * inside;
// the sputter: heaviest in the last few millimetres above the foot, where the
// cathode's own metal lands, and thinning up the tube over about 6 mm
float footT = exp(-max(footY - p.y, 0.0) / (6.5 * mm));
float sputterFilm = footT * (0.45 + 0.55 * hash(floor(p / max(1.0, 1.1 * mm)) + 37.0));
float sputter = sputterFilm * inside;
// absorption and reflection of each film: the getter is cold silver, barium's
// own n and k, the sputter is nearly black and warm, as burnt tungsten is
refract *= 1.0 - clamp(0.50 * getter + 0.38 * sputter, 0.0, 0.90);
alpha = mix(alpha, 0.55, getter * 0.55);
alpha = mix(alpha, 0.45, sputter * 0.50);
colour += metal_hit(px, N3, VIEW, vec3(0.60, 0.61, 0.64), 0.30) * getter * 0.80;
colour += metal_hit(px, N3, VIEW, vec3(0.19, 0.17, 0.15), 0.55) * sputter * 0.35;

// --- the discharge --------------------------------------------------------
// The lit cathode is a wire: a thin, saturated, almost white-hot line, and the
// gas around it. Nothing else on the tube is this bright.
vec3 add = vec3(0.0);
float gasMap = 0.0;
// The wire's own radiance, kept apart from everything else the discharge adds:
// it is the only thing in the tube that goes past white, and the HDR headroom
// at the end of main() is built from it alone.
float wireRadiance = 0.0;
// The colour of the wire's own surface, kept with the radiance: the HDR excess
// at the end of main() is the light the wire itself throws, not a fixed tint.
vec3 wireGlowColour = vec3(0.0);
if (pBulb > 0.5) {
float bulb = length(p - vec2(0.0, 0.0)) - 5.0 * mm;   // the colon, one round bulb
float lit = 1.0 - clamp((bulb + 0.4) / 0.8, 0.0, 1.0);
gasMap = exp(-max(bulb, 0.0) / (0.30 * 5.0 * mm)) * 0.60 + exp(-max(bulb, 0.0) / (1.4 * 5.0 * mm)) * 0.25;
wireGlowColour = blackbody(pTempK);
wireRadiance = lit * 1.20 * pGlow * pFlicker * heat_power(pTempK, 1.0);
add += wireGlowColour * wireRadiance;
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
// The sheath around the wire: the gas hugs a hot filament and falls away fast.
// A thicker cathode carries more of it, so the sheath is wider and denser than
// the hairline one a thin wire would have.
float gas = exp(-dist / (0.23 * mm)) * 0.17 + exp(-dist / (0.56 * mm)) * 0.040;
gas *= 0.955 + 0.09 * hash(floor(px / 2.0));
// A discharge is never perfectly still: the glow wanders, the wire hums with
// the mains, and the eye reads that slow irregular drift as a lamp that is on.
// Two sines for the breathing (so its period never reads as a beat) and one
// for the hum; per cent, not per ten — a login screen that strobes is a bug.
float breathe = 1.0 + 0.035 * sin(pTime * 2.1 + p.y * 0.013) * sin(pTime * 0.7 + 1.3);
float hum = 1.0 + 0.015 * sin(pTime * 8.0 + dp.y * 2.0);
float coreLit = pGlow * pow(pFlicker, 0.5);
float haloLit = pGlow * pow(pFlicker, 1.4) * breathe;
// The wire is held at its two ends by the stack's rods, and heat conducts out
// through them: the run sits at pTempK where it is far from both ends and loses
// HEAT_END_DROP kelvin at the ends themselves. The distance to the nearer end
// is the cheap stand-in for the position along the run — exact along a straight
// stroke, an overestimate around a bend, which is enough for a glow.
vec4 ends = digitEnds(int(pDigit + 0.5));
float endDist = min(length(dp - ends.xy), length(dp - ends.zw));
float heatProfile = clamp(endDist / HEAT_FALLOFF, 0.0, 1.0);
float wireTemp = pTempK - HEAT_END_DROP * (1.0 - heatProfile);
wireGlowColour = blackbody(wireTemp);
// A wire that hot is its own light: Planck's colour for the colour, and
// Stefan-Boltzmann's fourth power for the power. heat_power() is measured
// against the 2550 K the theme is drawn at, so the knob at its default leaves
// the picture exactly where it was and turning it up makes the discharge hotter.
// The white core is what a wire at pTempK looks like; where the wire runs
// cooler the metal keeps its own blackbody colour instead of burning white.
vec3 wireColour = mix(wireGlowColour, vec3(1.0, 0.97, 0.92), pow(core, 6.0) * 0.55 * heatProfile);
float wireHeat = heat_power(wireTemp, 1.0);
// A real filament is not uniformly hot along its length either: a slow hash on
// the numeral's own millimetres keeps the run from reading as a drawn line.
float filament = 1.0 + 0.07 * hash(floor(dp * 22.0));
// The wire is metal, not a tube of light: the heat piles up on the axis and
// falls off towards the surface, so the stroke is a white-hot core inside a
// body that is merely hot — a glow with a gradient, not a flat rod. The ramp
// is linear in the metal's own radius, which is what a heated wire's cross
// section looks like, and nothing of it is drawn outside the wire.
wireRadiance = core * (0.55 + 0.80 * core) * coreLit * wireHeat * filament * hum * (1.0 + 0.11 * wirePass);
add += wireColour * wireRadiance;   // white-hot, and no wider than the wire itself

// The gas hugs the wire where it is hot, so the sheath thins towards the ends
// with the wire itself: a cooler stretch of cathode carries a dimmer glow.
float gasHeat = 0.60 + 0.40 * heatProfile;
// A hot run gives off more gas in places: the sheath breathes along the wire
// instead of being drawn at one width.
float sheath = 0.90 + 0.20 * hash(floor(dp * 6.0) + 41.0);
// Glass and a lens split a bright line, blue on one flank and red on the
// other. Two more taps of the numeral's own field, a pixel to either side,
// carry that fringe; the green channel keeps the undistorted sheath.
float axisR = digitWire(int(pDigit + 0.5), dp + vec2(1.4 / gm, 0.0)) * gm;
float axisB = digitWire(int(pDigit + 0.5), dp - vec2(1.4 / gm, 0.0)) * gm;
float distR = max(axisR - wirePx, 0.0);
float distB = max(axisB - wirePx, 0.0);
float gasR = exp(-distR / (0.23 * mm)) * 0.17 + exp(-distR / (0.56 * mm)) * 0.040;
float gasB = exp(-distB / (0.23 * mm)) * 0.17 + exp(-distB / (0.56 * mm)) * 0.040;
add += vec3(gasR * pHalo.r, gas * pHalo.g, gasB * pHalo.b) * gasHeat * sheath * 0.58 * haloLit;
add += pHalo.rgb * exp(-dist / (2.7 * mm)) * 0.08 * gasHeat * haloLit;   // the soft bloom a hot wire casts
// the fringe where the discharge dies out drifts violet
add += vec3(0.78, 0.24, 0.72) * exp(-abs(dist - 0.28 * mm) / (0.13 * mm)) * 0.032 * step(0.06 * mm, dist) * haloLit;
// The far wall of the glass does catch the wire, but it is a wall and not a
// mirror: the cylinder squeezes the image sideways, two Fresnel passes dim it,
// and the curvature of the far side defocuses it. A crisp flipped copy of the
// numeral inside the tube (which is what this used to be) reads as a second,
// broken digit — the reflection has to be soft enough to be a glow.
// The far wall is a mirror, and this second image is traced, not painted: the
// eye's own ray, after the first refraction, reflects off the cylinder and is
// asked where it would land on the cathode's plane. The reflection sits where
// the glass puts it — a fixed flip of the picture put a copy of the digit in
// the wrong place — and the wall's curvature softens what it finds.
vec3 A = vec3(p.x, p.y, sqrt(max(0.0, R * R - p.x * p.x)));
float tFar = -2.0 * (A.x * rayT.x + A.z * rayT.z) / max(dot(rayT.xz, rayT.xz), 1e-4);
vec3 Pw = A + tFar * rayT;
vec3 nFar = -normalize(vec3(Pw.x, 0.0, Pw.z));
vec3 rFar = reflect(rayT, nFar);
float tPlane = -Pw.z / max(rFar.z, 0.05);
vec2 Q = Pw.xy + tPlane * rFar.xy;
vec2 rMirror = vec2((Q.x - centre.x) / gx, (centre.y - Q.y) / gy);
float wallRefl = exp(-max(digitWire(int(pDigit + 0.5), rMirror) * gm - wirePx, 0.0) / (2.2 * mm));
// the light the wire throws on the far wall drifts with the gas itself
add += mix(pHalo.rgb, wireGlowColour, 0.5) * wallRefl * 0.075 * pow(abs(xr), 1.5) * inside * haloLit * breathe;
gasMap = gas;
colour += cageGlow * 0.25;
}

// Exposure: the gas never reaches white, the wire always does. What the wire's
// core has beyond the white point is kept apart as headroom for an HDR output:
// added to the final pixel, not to `add`, because `add` is also what the
// discharge's light on the glass is drawn from — folding the headroom into it
// lit the whole tube three times over.
add = vec3(1.0) - exp(-add * 1.55);
// The wire's own radiance above the white point: a real wire is far brighter
// than a screen's white, and the compositor passes HDR metadata through, so the
// excess is carried to the output instead of being flattened. It is taken from
// the wire alone — from `add` it would smear a halo around every bright pixel.
vec3 headroom = wireGlowColour * max(wireRadiance - 1.5, 0.0) * 0.12;
float spill = exp(-max(sd, 0.0) / (0.9 * bulbR)) * 0.90
            + exp(-max(sd, 0.0) / (3.0 * bulbR)) * 1.05
            + exp(-max(sd, 0.0) / (9.0 * bulbR)) * 0.55;
// The light the discharge throws: its own colour, and how much of it lands on
// the glass is the theme's nixieWarmth — 0.45 is the tube's own look, so the
// token multiplies it instead of repainting the picture.
vec3 wash = mix(pHalo.rgb, blackbody(pTempK), 0.65);
float warmth = clamp(pWarmth / 0.45, 0.0, 3.0);
// The discharge's light lands on the wallpaper (the spill) — and inside the
// glass it is the light itself, which the composite adds. Adding it here as well
// counted every ray of it twice, which is what fattened the white core to two
// and a half times the wire's own width. It is light, not the discharge: a
// twelfth of the wire's own radiance, spread wide, is what a hot wire throws.
colour += wash * add * spill * warmth * 0.12;
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

// The pins: Ø1 mm, twelve of them, on the sheet's 11.5 mm circle. They are what
// the lamp is plugged in by and nothing else, and a base that stops at its own
// rim reads as a cap. In this front view each pin projects to x = 5.75 mm times
// the cosine of its own angle, and they are the same nickel the rods are.
float collarBottom = footY + collarH;
float pinCircle = 5.75 * mm;      // the sheet's 11.5 mm circle, as a radius
float pinR = 0.5 * mm;            // Ø1 mm
float pinLen = 7.0 * mm;          // and 7 mm long, as the sheet has them
// the item's own edge cuts the pins: fade them instead of clipping them hard
float pinEdge = clamp((0.5 * pSize.y - p.y) / max(1.0, 0.75 * mm), 0.0, 1.0);
for (int i = 0; i < 12; i++) {
	float a = float(i) * 0.5235987756;   // twelve pins, 30 degrees apart
	float pinX = pinCircle * cos(a);     // the circle, seen from the front
	float shaft = exp(-pow((p.x - pinX) / max(pinR, 0.6), 2.0));
	float tip = 1.0 - smoothstep(collarBottom + 0.60 * pinLen, collarBottom + pinLen, p.y);
	float pinMask = shaft * tip * pinEdge * smoothstep(collarBottom - 0.5 * mm, collarBottom, p.y);
	vec3 pinMetal = metal_hit(px, Ncyl, VIEW, F0_NICKEL, 0.32);
	colour = mix(colour, pinMetal * 1.10, pinMask);
	alpha = mix(alpha, 0.95, pinMask);
	// the pin's own roundness catches the left light the rest of the metal gets
	colour += vec3(0.13, 0.13, 0.14) * pinMask * exp(-pow((p.x - pinX + 0.40 * pinR) / max(0.40 * pinR, 0.4), 2.0));
}

// The collar's own terminals: the two eyelets on its top face, where the glass's
// leads come through and are soldered. They are gold, like the collector ring,
// and they are what ties the base to the stack above it.
for (int e = 0; e < 2; e++) {
	float tx = (e == 0) ? -7.4 * mm : 7.4 * mm;
	vec2 tc = vec2(tx, footY + 0.9 * mm);
	float termRing = abs(length((p - tc) / vec2(1.0, 0.72)) - 0.68 * mm) - 0.26 * mm;
	float termMask = (1.0 - smoothstep(-0.5, 0.5, termRing)) * insideCollar;
	vec3 termMetal = metal_hit(px, Ncyl, VIEW, F0_GOLD, 0.26);
	colour = mix(colour, termMetal * 1.20, termMask);
	alpha = mix(alpha, 0.88, termMask * 0.85);
	colour += vec3(0.16, 0.14, 0.08) * termMask * ((e == 0) ? 1.0 : 0.40);
}
}

// the glass lands on the front surface, in front of everything inside
colour += glassLight * (1.0 - clamp(max(add.r, max(add.g, add.b)) * 0.9, 0.0, 0.85));
// Film grain: the tube is a photograph of a lamp in a photograph of a room.
// Static (invariant I1), faint, and masked to the glass — the frame's
// transparent pixels are the wallpaper's, and grain there would tint it.
colour += vec3(hash(px * 1.31 + 0.5) - 0.5) * 0.012 * inside;

fragColor = vec4(colour + add + headroom + refract * clamp(1.0 - alpha, 0.0, 1.0) * inside,
		clamp(alpha, 0.0, 0.98)) * qt_Opacity;
}
