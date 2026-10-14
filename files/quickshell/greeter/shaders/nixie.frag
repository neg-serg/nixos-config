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
float pRadius;     // unused: the QML mirror declares it and the drawing shapes the envelope
float pBase;       // unused: the base's height is the drawing's own 7 mm; pBaseOn says if it is drawn
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
// old core colour had, padded, because std140 base-aligns a vec4 to 16 bytes
// and the workbench mirrors this block field by field.
// padCore0 and padCore3 keep pTempK and pExposure where the workbench's
// struct has them; neither pad is read. The four knobs at the end of the
// block are appended after pView so every offset above them is unchanged.
float padCore0;
float pTempK;
float pExposure;   // stops above white the discharge is exposed at
float padCore3;
vec4 pHalo;        // colour of the gas around it
vec4 pGlass;       // the envelope's own tint
vec4 pCathode;     // the unlit wire, seen through the glass
float pThick;      // wall thickness of the envelope, px (0 = a shell, no glass)
float pMm;         // unused: the millimetres come from pTile in nixie_tube, not from the caller
float pRefract;    // how hard the envelope bends the picture behind it (1 = the glass's own)
float pTime;       // seconds of session time: the tube is alive, but slowly
// The row: the login clock draws its four tubes in one pass, because a tube's
// item is finite and its light is not — four passes put four rectangles of
// lamp-lit wallpaper around the clock. pTile.w says whether this item is a row
// (1) or a single tube (0, which is what the workbench and the tube lab draw);
// a single tube then reads its own size and margin from pSize and pInset.
vec4 pRowX;        // the four tubes' centres, px from the item's centre
vec4 pRowDigit;    // the four digits, -1 for a tube with nothing to light
vec4 pRowFlicker;  // the four ignitions: a nixie's tubes never strike together
vec4 pTile;        // the tube's own item (width, height, margin), and the mode
vec4 pTint;        // the colour of coloured glass: hue in rgb, strength in a
vec4 pWallpaper;   // x: tint the lamp with the wallpaper's own accent instead
vec4 pView;        // the camera: x is its yaw off the tube's axis in degrees,
                   // y how far it stands in tube widths (0: the default) and
                   // z its pitch. The three build one pinhole; nothing here is
                   // a screen-space shift of a flat drawing.

// The quality tier. 0 draws today's picture; 1 shares one metal environment,
// drops the inner-wall echo and cuts the 8's chord loop; 2 also drops the two
// dispersion rays, the caustic and the second noise scale, samples every
// other unlit cathode and stops sampling the room for metal at all.
float pQuality;
// The breathing and the mains hum, as a fraction: 1 is today's shimmer, 0
// freezes the discharge while the wire stays lit and the gas stays lit.
float pShimmer;
// Multiplier on the getter and sputter films: 1 is today's patina, 0 a tube
// that has just been made.
float pAge;
// 1 draws the sheet's 7 mm metal base (nixieBase); 0 keeps today's
// base-off look.
float pBaseOn;
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
if (k <= 1e-5) return min(a, b);   // a straight wire: pWire = 0 must not divide by zero
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
// Only the 8 sets it; every path that reads it first clears it, because the
// last 8 the stack sampled is not the strand a lit wire belongs to.
float wirePass = 0.0;
// The wire's own radius in the numeral's space, filled in by main() from the
// nixieWire token: an elbow of bent wire is as thick as the wire (see digitWire).
float bendK = 0.0;

float digit_shape(int digit, vec2 p) {
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
// The user's own Iosevka (Iosevkaneg), measured off the glyph. The bar carries
// a short stub at its right end; the stem leans a little to the left and its
// foot turns straight into the waist; the bowl is a rounded rectangle half a
// unit wide whose corners are quarters of a 0.25 circle — that is what the
// glyph's own bends measure — run from the waist round the right, the bottom
// and up the left to the terminal below the waist. The numbers are the glyph's
// own: bar at 0.835 (x -0.20..0.22), stub to 0.58, stem foot -0.225/0.19,
// waist to 0.0/0.23, bowl sides at x = +-0.25 between -0.58 and -0.02, bottom
// at -0.83, terminal at -0.50.
{
float d = sdSegment(p, vec2(0.22, 0.835), vec2(-0.20, 0.835));       // the bar
d = min(d, sdSegment(p, vec2(0.22, 0.835), vec2(0.22, 0.58)));       // its stub
d = min(d, sdSegment(p, vec2(-0.20, 0.835), vec2(-0.225, 0.19)));    // the stem
d = smin(d, sdSegment(p, vec2(-0.225, 0.19), vec2(0.0, 0.23)), bendK);  // its foot turns into the waist
d = min(d, sdArc(p, vec2(0.0, -0.02), 0.25, 0.0, 1.5707963268));        // the bowl's top right
d = min(d, sdSegment(p, vec2(0.25, -0.02), vec2(0.25, -0.58)));         // its right side
d = min(d, sdArc(p, vec2(0.0, -0.58), 0.25, 4.7123889804, 6.2831853072));  // bottom right
d = min(d, sdArc(p, vec2(0.0, -0.58), 0.25, 3.1415926536, 4.7123889804));  // bottom left
d = min(d, sdSegment(p, vec2(-0.25, -0.58), vec2(-0.25, -0.50)));       // left side, to the terminal
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
// login screen at 1x, so nothing of the polygon survives the glow. Balanced
// and lite cut the loop to 48 chords — joints about 1.7 mm apart, still under
// the 2.2 mm the wire is drawn at, and a third of the work.
//
// The curve passes through the waist twice — once at t = pi/2, once at
// t = 3pi/2 — and a ribbon is what those two passes make. Which of them runs
// over the other is not in a flat drawing, so it is carried by the wire itself:
// the near strand is flagged here and runs a little hotter further down.
{
float d = 1e5;
float best = 0.0;
vec2 prev = vec2(0.0, 1.02);
if (pQuality >= 0.5) {
for (int i = 1; i <= 48; i++) {
float t = float(i) / 48.0 * 6.2831853072;
vec2 q = vec2(0.420 * sin(2.0 * t), 1.020 * cos(t));
float piece = sdSegment(p, prev, q);
if (piece < d) {
d = piece;
best = float(i);
}
prev = q;
}
// 12 is t = pi/2, 36 is t = 3pi/2; the windows scale with the chord count.
wirePass = 1.0 - smoothstep(1.8, 9.0, abs(best - 12.0))
         - (1.0 - smoothstep(1.8, 9.0, abs(best - 36.0)));
} else {
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
}
return d;
}
if (digit == 9)
// The bowl rides on top and the leg under it is straight. A 9 is a 6 turned
// over, and what tells them apart is which end carries the loop.
return smin(sdEllipse(p, vec2(0.0, 0.52), vec2(0.30, 0.48)),
            sdSegment(p, vec2(0.30, 0.52), vec2(0.29, -0.98)), bendK);
}

// The wire's two ends, in the numeral's own space: where it leaves the figure
// for the stack's rods, which is where it is held, and so where heat conducts
// out of it. A closed loop carries its seam twice — that one point is both
// ends, and the wire is coldest there and hottest half a run away from it.
// How much a numeral is scaled about the centre of the glyph's space. The five
// is the one the user measured off his own Iosevka, and its centreline reaches
// +-0.835 there, so its ink reaches +-0.904 once the wire's own radius is on it.
// Every other figure is brought to that same height: a font's figures share one
// cap height, and four tubes only read as one clock if their digits do too.
// These are those heights, divided one into the other — the numbers are the
// shapes' own extents (0.88 for the ellipse of the nought, 1.02 for the strokes
// that fill the space, 0.92 and 1.00 for the six and the nine).
float glyph_scale(int digit) {
if (digit == 0) return 0.949;
if (digit == 1) return 0.819;
if (digit == 2) return 0.819;
if (digit == 3) return 0.819;
if (digit == 4) return 0.819;
if (digit == 5) return 1.000;
if (digit == 6) return 0.908;
if (digit == 7) return 0.819;
if (digit == 8) return 0.819;
if (digit == 9) return 0.835;
return 1.0;
}

// The wire's path, at the height the row's other digits are drawn at. Uniform in
// both directions on purpose: the wire's thickness is a screen-space radius that
// is taken off after this, so a scale that stretched only y would leave the
// stroke fatter where it runs across than where it runs down.
float digitWire(int digit, vec2 p) {
float k = glyph_scale(digit);
return digit_shape(digit, p / k) * k;
}

vec4 digitEnds(int digit) {
float k = glyph_scale(digit);
if (digit == 0) return k * vec4(0.0, -0.88, 0.0, -0.88);
if (digit == 1) return k * vec4(0.0, -1.02, -0.24, 0.55);
if (digit == 2) return k * vec4(-0.31, 0.60, 0.35, -1.02);
if (digit == 3) return k * vec4(-0.226, 0.874, -0.226, -0.874);
if (digit == 4) return k * vec4(0.32, -0.10, 0.26, -1.02);
if (digit == 5) return k * vec4(0.22, 0.58, -0.25, -0.50);
if (digit == 6) return k * vec4(-0.33, -0.14, 0.33, 0.55);
if (digit == 7) return k * vec4(-0.30, 1.00, -0.10, -1.02);
if (digit == 8) return k * vec4(0.0, 1.02, 0.0, 1.02);
if (digit == 9) return k * vec4(0.30, 0.52, 0.29, -0.98);
return k * vec4(0.0, 1.02, 0.0, -1.02);
}

// The wire cools towards its ends: how much of its temperature it loses where
// it is held, and over what distance (in the numeral's own units) it recovers.
// The drop is small because incandescence is steep: the visible band runs as
// T^11 near 2000 K, so the 550 K this used to lose where the rods hold the wire
// would have put the ends out thirty times over. 150 K leaves the ends at about
// half the run's light, which is what a photograph of a heated wire shows.
const float HEAT_END_DROP = 150.0;
const float HEAT_FALLOFF = 0.30;

float hash(vec2 p) {
return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise: a hash on the lattice, smoothed between its corners.
// The glass below is worked by hand, and a hand leaves ripples and bubbles;
// the noise is what its wall has instead of being a machined cylinder.
float vnoise(vec2 q) {
vec2 i = floor(q);
vec2 f = fract(q);
vec2 s = f * f * (3.0 - 2.0 * f);
float a = hash(i);
float b = hash(i + vec2(1.0, 0.0));
float c = hash(i + vec2(0.0, 1.0));
float d = hash(i + vec2(1.0, 1.0));
return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}


// --- metal, with a real reflection -------------------------------------
// A metal is a mirror with a tint: what it looks like is the room it stands in,
// seen along the mirror direction and tinted by the metal's own F0. Nickel is
// (0.56, 0.55, 0.52), steel a shade cooler, and the roughness spreads the
// reflection out. This is what the mesh, the rods and the collar were faking
// with constant colours.
vec3 metal_env(vec2 px, vec3 n, vec3 v, float rough) {
vec3 r = reflect(-v, n);
// where that ray lands on the room behind the lamp
vec2 off = vec2(r.x, r.y) / max(-r.z, 0.05) * (0.55 * pTile.x);
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
return env * 0.2;
}

// A metal darkens what it does not reflect, and Fresnel takes the edge.
vec3 metal_shade(vec3 env, vec3 n, vec3 v, vec3 f0) {
float c = clamp(dot(n, v), 0.0, 1.0);
vec3 f = f0 + (vec3(1.0) - f0) * pow(1.0 - c, 5.0);
return env * f;
}

vec3 metal_hit(vec2 px, vec3 n, vec3 v, vec3 f0, float rough) {
return metal_shade(metal_env(px, n, v, rough), n, v, f0);
}

// The tier's view of it: full reflects once per part, balanced reflects once
// for the whole tube and gives every part its own Fresnel, lite stops sampling
// the room at all and shades the metal from one dim constant.
vec3 metal_for(vec2 px, vec3 n, vec3 v, vec3 f0, float rough, vec3 sharedEnv, float quality) {
if (quality >= 1.5) return metal_shade(vec3(0.22), n, v, f0);
if (quality >= 0.5) return metal_shade(sharedEnv, n, v, f0);
return metal_hit(px, n, v, f0, rough);
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
// The metal's own colour, in linear light with red at one. Fitted from a
// spectral path trace of the Planck spectrum itself (Mitsuba, D65 white) over
// 1600..5200 K: the previous fit was a code-value approximation of the
// Planckian locus, and at 2400 K it read (1, 0.33, 0.05) where the physics
// says (1, 0.41, 0.09) — half the blue, a visibly redder wire.
float x = 1000.0 / clamp(kelvin, 1000.0, 20000.0);
float g = (((-1.302702 * x - 0.156449) * x + 3.789388) * x - 4.019890) * x + 1.473130;
float b = (((52.731460 * x - 108.810925) * x + 86.086908) * x - 31.418177) * x + 4.514340;
return vec3(1.0, max(g, 0.0), max(b, 0.0));
}

// How much a surface at this temperature throws where the eye can see it,
// against the temperature the tube is drawn at (2550 K, the wire). Stefan-
// Boltzmann's fourth power is the *bolometric* power: a camera sees the visible
// band, and as the Planck peak walks into it that band's share grows fast —
// measured off the same spectral renders, the local exponent is 11 near 2000 K
// and 9 near 3000 K, so a wire's cooler ends fall away far harder than T^4
// ever did. The quartic is that measurement (0.1% over 1600..3600 K); the cap
// is exposure — a knob turned all the way up must not blow the frame out.
float heat_power(float kelvin, float gain) {
float u = log(clamp(kelvin, 1000.0, 12000.0) / 2550.0);
float l = (((-0.291099 * u + 1.519672) * u - 4.580079) * u + 9.070077) * u - 0.012245;
return min(exp(l) * gain, 30.0);
}

// The exposure itself is the theme's nixieExposure (pExposure): the wire stands
// that many times above a white surface, and the curve below is what turns that
// into a white core. The old pipeline hid this number in three places at once —
// a gain, an exposure constant and a "headroom" term — and then clipped it.

// The tone map: Khronos' PBR-neutral curve, built for exactly this job — an
// object whose colour has to stay true while its highlights roll off. It takes
// light in linear units and returns display units: the shoulder turns a wire
// several times brighter than white into a warm white core instead of clipping
// it into cardboard, and only the very top of it desaturates.
// A tube with coloured glass, the theme's nixieTint: the light it makes takes
// the tint's hue at the brightness it already had, so a cyan envelope reads as a
// cyan lamp rather than an orange one behind a filter — an orange light through
// cyan glass would simply be dark, which is physics and not what the knob is
// for. The alpha is the strength: a transparent tint leaves the metal's own
// Planck colour alone, which is the default.
vec3 tinted(vec3 c, vec4 tint) {
// Peak for peak, not luminance for luminance: a cyan whose luminance matched a
// hot wire's would be a washed pale thing, and the knob is for a lamp that is
// plainly cyan. Keeping the brightest channel where it was keeps the exposure
// meaning the same thing whatever the hue.
float peak = max(c.r, max(c.g, c.b));
float tintPeak = max(tint.r, max(tint.g, tint.b));
return mix(c, tint.rgb * (peak / max(tintPeak, 1e-3)), tint.a);
}

// The room's own colour, read from the picture the glass already samples: a
// fixed grid over the patch behind the lamp, and the most saturated of those
// readings kept. Fixed, so every tube and every pixel of them takes the same
// colour — a lamp under a wallpaper is lit by the wallpaper, not by the square
// millimetre under one of its pixels.
vec3 wallpaper_accent() {
vec3 best = vec3(0.0);
float bestSat = 0.0;
for (int iy = 0; iy < 3; iy++) {
for (int ix = 0; ix < 4; ix++) {
vec2 uv = vec2(0.20 + 0.20 * float(ix), 0.25 + 0.25 * float(iy));
vec3 c = texture(source, uv).rgb;
float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
if (sat > bestSat) {
bestSat = sat;
best = c;
}
}
}
// A grey room has no accent to take: leave the metal its own colour. What is
// taken is the hue with its saturation pushed up a little — a wallpaper's own
// colour is mostly room, and a lamp lit by it should read as that colour rather
// than as a slightly tinted grey.
if (bestSat <= 0.008)
return vec3(0.0);
float l = dot(best, vec3(0.2126, 0.7152, 0.0722));
return clamp(mix(vec3(l), best, 1.45), 0.0, 1.0);
}

// The tint the tube's light actually takes: the theme's own colour, or the
// wallpaper's own when the theme asks for that (nixieTintWallpaper).
vec4 effective_tint(vec3 accent) {
if (pWallpaper.x <= 0.0)
return pTint;
if (dot(accent, accent) < 1e-5)
return pTint;
return vec4(accent, pWallpaper.x);
}

vec3 tone_map(vec3 c) {
const float startCompression = 0.8 - 0.04;
const float desaturation = 0.15;
float x = min(c.r, min(c.g, c.b));
float offset = (x < 0.08) ? x - 6.25 * x * x : 0.04;
c -= offset;
float peak = max(c.r, max(c.g, c.b));
if (peak < startCompression) return c;
float d = 1.0 - startCompression;
float newPeak = 1.0 - d * d / (peak + d - startCompression);
c *= newPeak / peak;
float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
return mix(c, newPeak * vec3(1.0), g);
}

// --- the camera, and the geometry a ray meets ------------------------------
// A real one: a pinhole standing pView.y tube widths in front of the tube's
// centre plane, turned by the theme's yaw (pView.x) and pitch (pView.z). The
// caller builds the basis in main() and hands every pixel its own ray, in a
// frame whose unit is the tube's own drawing pixel. The drawing is exactly the
// picture that camera takes from dead ahead, so at yaw = pitch = 0 nothing
// below moves a pixel; at any other angle the outline, the rims and everything
// inside the glass follow the geometry instead of shifting on the screen.
vec2 plane_hit(vec3 o, vec3 d, float z) {
    return o.xy + (z - o.z) / min(d.z, -1e-4) * d.xy;
}

// The outer wall of the glass: the cylinder between +-h closed by two
// hemispheres. The nearest front-facing hit is the surface this pixel sees
// (t < 0: the ray misses the glass). The normal comes back with z negated,
// which is the sign the optics below were written with.
vec4 capsule_hit(vec3 o, vec3 d, float ra, float h) {
    float t = -1.0;
    float a = dot(d.xz, d.xz);
    float b = dot(o.xz, d.xz);
    float c = dot(o.xz, o.xz) - ra * ra;
    float disc = b * b - a * c;
    if (a > 1e-8 && disc > 0.0) {
        float tc = (-b - sqrt(disc)) / a;
        if (tc > 0.0 && abs(o.y + tc * d.y) <= h) t = tc;
    }
    for (int s = 0; s < 2; s++) {
        float sy = (s == 0) ? -h : h;
        vec3 os = o - vec3(0.0, sy, 0.0);
        float tb = dot(os, d);
        float td = tb * tb - dot(os, os) + ra * ra;
        if (td > 0.0) {
            float ts = -tb - sqrt(td);
            float y = o.y + ts * d.y;
            if (ts > 0.0 && ((s == 0 && y <= -h) || (s == 1 && y >= h))) {
                if (t < 0.0 || ts < t) t = ts;
            }
        }
    }
    if (t < 0.0) return vec4(-1.0, 0.0, 0.0, -1.0);
    vec3 q = o + t * d;
    if (q.z <= 0.0) return vec4(-1.0, 0.0, 0.0, -1.0);   // only the near wall is the glass
    return vec4(t, normalize(vec3(q.x, q.y - clamp(q.y, -h, h), -q.z)));
}

// Where a point of the drawing lands on the film: the frame's camera, the
// tube's centre at the origin, the film through it. Used by the small parts
// that are placed directly — the pip and the pins.
vec2 cam_project(vec3 w, vec3 camO, mat3 camB, float near) {
    float t = near / dot(w - camO, camB[2]);
    vec3 q = camO + t * (w - camO);
    return vec2(dot(q, camB[0]), dot(q, camB[1]));
}

vec4 nixie_tube(vec2 px, vec2 p, vec3 rayO, vec3 rayD, mat3 camB, float camNear,
                vec2 tile, float pad, vec3 accent,
                float digit, float flicker, float bulb, float edgeFade) {
const float PI = 3.14159265;
// The tier this call is drawn at, and the knobs clamped once so a hostile
// theme value cannot poison every term below.
float quality = clamp(pQuality, 0.0, 2.0);
float glow = max(pGlow, 0.0);
float shimmer = clamp(pShimmer, 0.0, 1.0);
float age = max(pAge, 0.0);
wirePass = 0.0;   // the previous tube's ribbon flag must not modulate this one

// --- the envelope, from the drawing ------------------------------------
// Every number here is off Reflector's IN-12A/B data sheet (1988), in its own
// millimetres: the bulb is Ø19 and stands 28 from its foot to the top of the
// dome, the base is Ø21 and 7 deep, the pip the tube was sealed by is Ø3.5, and
// the whole lamp without its pins is 35 max. pTile turns those millimetres into
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
const float BULB_H_MM = 28.0;   // the glass, when the sheet's base is drawn
const float COLLAR_H_MM = 7.0;  // and the base: 28 + 7 = the 35 mm lamp
float mm = min((tile.x - 2.0 * pad) / boxW, (tile.y - 2.0 * pad) / boxH);
mm = max(mm, 0.01);
float bulbR = BULB_R_MM * mm;           // the glass is as wide as the box, Ø21
// Where the numerals sit inside: a cathode stands in front of the axis, and
// the cathode plane below is where every glyph is read from, so the numerals
// have a depth of their own and the camera's angle moves them.
const float CATHODE_Z = 0.72;   // where the numerals sit, in bulb radii in front of the axis
// The collar is the sheet's 7 mm, full stop. pBaseOn is only the caller saying
// whether this envelope has one at all (the colon has not), because a caller
// working in its own pixels must not be able to put the base somewhere the
// drawing does not. 0 keeps today's base-off look — the whole 35 mm is glass;
// with the base on, the sheet's 28 mm bulb stands on its 7 mm collar and the
// two still add up to the box.
float baseOn = (pBaseOn > 0.5) ? 1.0 : 0.0;
float collarH = COLLAR_H_MM * baseOn * mm;
float bulbH = (BULB_H_MM + COLLAR_H_MM * (1.0 - baseOn)) * mm; // the glass: cylinder + two caps
float pipR = 1.75 * mm;                 // the seal's pip, Ø3.5

float boxMid = 0.5 * boxH * mm;         // the item's centre, and the box's
float pipTop = -boxMid;                 // the sheet's 35 mm is measured to the pip
float footY = boxMid - collarH;         // where the glass meets the collar
float apexY = footY - bulbH;            // the top of the dome
float capY = apexY + bulbR;             // the centre of the dome's cap

// A capsule: hemispheres at both ends, so the top and the bottom of the glass
// are the same shape. That is what a symmetric bulb is. p.y = 0 is the middle
// of the item and the glass is centred on it, so the drawing and the ray
// measure from the same place.
// The capsule: a rectangle closed by two semicircles. The max(..., 0) is what
// makes the middle a straight-sided body — without it the profile pinches in
// and the lamp reads as two spheres with a waist between them.
float R = max(bulbR, 1.0);
float capOffset = max(0.5 * bulbH - bulbR, 0.0);          // the cylinder's half length

// What the glass hides, in the image plane: the capsule the bulb is, as this
// camera draws it. Pitch compresses its straight run by the cosine of the
// angle between the tube's axis and the film; yaw cannot change a cylinder's
// width, and should not. sd is the signed distance to that silhouette in the
// tube's own pixels, and every rim, hairline and spill below is measured from
// it exactly as the drawing measured it before.
float axisCos = clamp(camB[1].y, 0.0, 1.0);              // the axis, as the film sees it
float capProj = capOffset * axisCos;
float sd = length(vec2(p.x, max(abs(p.y) - capProj, 0.0))) - R;
float inside = 1.0 - smoothstep(-0.7, 0.7, sd);
float d = -sd;

// --- the wall, where the ray meets it -------------------------------------
// The ray is tested against the real capsule: the cylinder between the
// shoulders and the two hemispheres, and the nearest front-facing hit is the
// surface this pixel sees. Everything the glass does — the Fresnel at its
// walls, the bend of the picture behind it, the room it reflects — is fed by
// that point and its normal, so the envelope answers the camera as one solid
// object. A ray that misses keeps the drawing's own normal; every surface
// term below is masked by inside anyway. The test is analytic, not marched:
// two quadratics and a square root, run only for the pixels the silhouette
// keeps.
vec4 hit = vec4(-1.0);
if (inside > 0.001) hit = capsule_hit(rayO, rayD, R, capOffset);
float hitOK = (hit.x > 0.0) ? 1.0 : 0.0;
vec3 P1 = (hitOK > 0.5) ? (rayO + hit.x * rayD) : vec3(p, 0.0);
vec3 N3 = (hitOK > 0.5) ? hit.yzw
                        : normalize(vec3(p.x, 0.0, -sqrt(max(R * R - p.x * p.x, 1e-4))));
vec3 Ncyl = normalize(vec3(P1.x, 0.0, -sqrt(max(R * R - P1.x * P1.x, 1e-4))));
float xr = clamp(P1.x / R, -1.0, 1.0);
float u = asin(xr) / (PI * 0.5);
float v = clamp(-(P1.y - capY) / max(bulbH - bulbR, 1.0), -1.0, 1.0);
float grazing = 1.0 - sqrt(max(0.0, 1.0 - xr * xr));

// Bubbles in the glass and the ripple the blower left: two scales of noise,
// each taken as its own gradient, added to the wall's normal. A few degrees of
// tilt is all it is — enough that the room the wall reflects breaks into
// glints and the picture it passes ripples a little, which is what glass that
// was worked by a hand does and a cylinder does not.
float wStep = 1.0 / (0.55 * mm);
float w0 = vnoise(p * wStep);
float wu = vnoise(p * wStep + vec2(1.0, 0.0));
float wv = vnoise(p * wStep + vec2(0.0, 1.0));
float bStep = 1.0 / (0.18 * mm);
vec2 bq = p * bStep + vec2(31.7, 11.3);
float b0 = vnoise(bq);
float bu = vnoise(bq + vec2(1.0, 0.0));
float bv = vnoise(bq + vec2(0.0, 1.0));
vec3 bump = vec3((wu - w0) * 0.05 + (bu - b0) * 0.13,
                 (wv - w0) * 0.05 + (bv - b0) * 0.13, 0.0);
N3 = normalize(N3 + bump);
// The direction this pixel looks along: the camera's own ray, so the
// refraction into the glass, the room it reflects and the Fresnel at its
// walls all follow the real camera instead of one global yaw.
vec3 VIEW = rayD;
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
float planeDist = 0.30 * tile.x;          // where the picture the glass bends hangs
float roomDist = 0.16 * tile.x;           // where the reflections come from
vec2 off = glass_offset(p, rayT, rayOut, planeDist, wallLens);
// The two dispersion rays are the lite tier's first cut: lite lets the green
// ray carry all three channels, so their offsets are only computed when they
// are sampled.
vec2 offR = vec2(0.0);
vec2 offB = vec2(0.0);
if (quality < 1.5) {
offR = glass_offset(p, rayTr, rayOut, planeDist, wallLens);
offB = glass_offset(p, rayTb, rayOut, planeDist, wallLens);
}
// A cylinder of glass is a lens, not a window: it has power across its axis and
// none along it, so the picture inside is magnified sideways — most of all on
// the axis, and not at all at the wall, where the glass is edge-on. That is the
// magnifying-glass bend, and it is why a nixie's numerals read taller in the
// middle of the tube than they measure on the bench.
float uAbs = clamp(abs(u), 0.0, 1.0);
float lensK = 1.0 - 0.30 * pRefract * (1.0 - uAbs * uAbs);
off  = vec2(off.x  * lensK, off.y);
off  = clamp(off,  vec2(-0.75 * R), vec2(0.75 * R));
if (quality < 1.5) {
offR = clamp(vec2(offR.x * lensK, offR.y), vec2(-0.75 * R), vec2(0.75 * R));
offB = clamp(vec2(offB.x * lensK, offB.y), vec2(-0.75 * R), vec2(0.75 * R));
}
// Real glass is never clean. It was wiped with something, it has settled dust,
// it carries a hairline scratch or two, and its walls are not a perfect
// cylinder. All of it is faint, and — invariant I1 — all of it is a hash of the
// pixel and not of the clock, so the login screen still draws the same still.
float smudge = hash(floor(p / (1.4 * mm)) + 17.0);
float dustFine = hash(floor(p / (0.55 * mm)) + 91.0);
// A scratch is one family of hairlines at a shallow angle; the hash decides
// where along them a scratch was actually left.
float scratchU = p.x * 0.28 + p.y;
float scratchT = scratchU / (19.0 * mm);
float scratchD = fract(scratchT) - 0.5;
float scratch = exp(-scratchD * scratchD / 0.0007)
              * step(0.80, hash(vec2(floor(scratchT), 5.0)));
float dust = step(0.9968, dustFine);
// The wall wanders: what the glass shows of the room drifts a pixel with it.
vec2 wobble = vec2(smudge - 0.5, dustFine - 0.5) * 1.2;
off  += wobble;
if (quality < 1.5) {
offR += wobble;
offB += wobble;
}
// One channel per ray at full — that is the dispersion, and it costs two more
// taps. Lite takes the green ray for all three channels instead: no fringe,
// and one tap.
vec3 disp;
if (quality >= 1.5) {
disp = texture(source, clamp((px + pInset + off) / pBackdrop, vec2(0.001), vec2(0.999))).rgb;
} else {
disp.r = texture(source, clamp((px + pInset + offR) / pBackdrop, vec2(0.001), vec2(0.999))).r;
disp.g = texture(source, clamp((px + pInset + off)  / pBackdrop, vec2(0.001), vec2(0.999))).g;
disp.b = texture(source, clamp((px + pInset + offB) / pBackdrop, vec2(0.001), vec2(0.999))).b;
}
vec3 refract = disp * absorb;
// the smear keeps a little of the room to itself
refract *= 1.0 - 0.06 * smudge;
// A caustic rings the wall: where the glass turns edge-on the lens's mapping
// folds over instead of stretching further, and the picture returns to the eye
// inverted — a second, almost mirrored image along the rim. One more tap at the
// folded offset, carried by grazing so the middle of the tube is untouched.
// Lite drops it: the rim keeps its two hairlines and loses the folded image.
if (quality < 1.5) {
float caustic = pow(grazing, 3.0) * pRefract * inside * wallLens;
vec2 offC = -off * 1.10;
vec3 causticImg = texture(source, clamp((px + pInset + offC) / pBackdrop, vec2(0.001), vec2(0.999))).rgb;
refract = mix(refract, causticImg * absorb, caustic * 0.70);
}

vec3 colour = vec3(0.0);
vec3 glassLight = vec3(0.0);
// What of the tube's body stands in front of the wallpaper. The wall itself
// covers the picture behind it — that is the whole difference between a glass
// tube and a hole in the picture — and the metal inside it covers more; the
// number only grows from here.
float alpha = inside * 0.18 * pow(grazing, 3.0);
// the body: cold, and a little darker than the picture behind it
colour += vec3(0.003, 0.004, 0.008) * inside * grazing;   // the body is not a filter

// the wall edge-on: two surfaces with a dark gap between them
float rim = exp(-max(d, 0.0) / 0.35) * inside;   // the wall seen edge-on: a hairline
float rimRel = (d - wall) / max(0.8, 0.20 * wall);
float rimInner = exp(-rimRel * rimRel) * inside;
// The body of the wall, seen edge-on: on a thick-walled tube the silhouette is
// not two hairlines but a band of glass, and that band is where Beer has the
// longest path — it is the green-teal depth of a real envelope.
float wallBody = smoothstep(0.0, 0.45, d) * (1.0 - smoothstep(wall - 0.45, wall, d)) * inside;
glassLight += vec3(1.0) * rim * (0.20 + 0.85 * pow(grazing, 3.0));
alpha += rim * 0.26 + rimInner * 0.16;
colour += vec3(0.02, 0.05, 0.06) * (rimInner * 0.6);
// the wall's own body: the glass colour, taken through its own absorption
colour = mix(colour, vec3(0.010, 0.030, 0.032) * (0.6 + 0.8 * grazing * grazing), wallBody * 0.55);
alpha = max(alpha, wallBody * 0.36);

// what the glass reflects: the room along the mirror direction, weighted by
// Fresnel — the reason the middle of a tube is clear and its edges are not
float fadeV = (v - 0.25) / 0.90;
float fade = clamp(1.0 - fadeV * fadeV, 0.0, 1.0) * clamp((v + 0.95) / 0.45, 0.2, 1.0);
vec2 mir = vec2(rayIn.x, rayIn.y) / max(-rayIn.z, 0.06) * roomDist;
mir = clamp(mir, vec2(-0.20 * R), vec2(0.20 * R));
vec2 uvR = (px + pInset + mir) / pBackdrop;
vec3 room = blurred_room(uvR, vec2(0.035, 0.030) * pRefract);   // the room, smeared
// Masked by the glass: outside the envelope there is no front surface to
// reflect the room, and the terms below used to be summed over the whole item —
// which is what put a lit rectangle of wallpaper around every tube.
glassLight += (room * 0.90 + 0.002) * min(F, 0.55) * 0.16 * pHighlight * inside;
// The inner wall is the second mirror in the tube: light crosses the bore,
// reflects off the far wall and leaves through the near one, so the room the
// glass carries arrives twice, displaced by that extra crossing — the weak
// doubled echo a real tube throws beside its bright core. Only the lateral
// direction flips (the wall that reflects is the far side of the cylinder), and
// the second wall plus the longer path take their share through absorb2.
// Balanced and lite drop it: the weight is at most a twentieth of the front
// reflection, and it costs five taps.
if (quality < 0.5) {
vec2 mir2 = vec2(-rayIn.x, rayIn.y) * 0.55 * roomDist / max(-rayIn.z, 0.06);
mir2 = clamp(mir2, vec2(-0.20 * R), vec2(0.20 * R));
vec3 room2 = blurred_room((px + pInset + mir2) / pBackdrop, vec2(0.050, 0.040) * pRefract);
vec3 absorb2 = exp(-(1.0 - pGlass.rgb) * ABSORB_DISP * 2.00 * 2.0 * pathIn / R);
glassLight += (room2 * 0.90 + 0.002) * min(F, 0.55) * 0.16 * pHighlight * absorb2 * 0.55 * inside;
}
// two narrow lights the tube always catches, and they stop before the collar
// where the wall is uneven the reflection is not one clean line: the noise
// breaks the two highlights the tube always catches into soft dashes
float broke = 0.80 + 0.40 * w0;
float dash1 = (abs(u) - 0.76) / 0.030;
float dash2 = (abs(u) - 0.40) / 0.22;
glassLight += vec3(0.82, 0.88, 1.0) * exp(-dash1 * dash1) * inside * fade * 0.17 * pHighlight * broke;
glassLight += vec3(0.75, 0.80, 0.95) * exp(-dash2 * dash2) * inside * fade * 0.055 * pHighlight * broke;
// what was wiped on the glass, what settled on it, and the scratches: each
// catches the light a little differently, which is all the eye needs to read a
// surface as a surface and not as a window
glassLight += vec3(0.90, 0.94, 1.00) * smudge * 0.014 * inside;
glassLight += vec3(1.00, 0.97, 0.88) * dust * 0.050 * inside;
glassLight += vec3(0.86, 0.90, 1.00) * scratch * 0.045 * inside;

// The pip the tube was sealed by — the one mark every nixie has on top of its
// dome. The dome itself is carried by the rim, which follows its arc. The pip
// stands on the axis, so pitch and the camera's distance place it: it drops
// with the dome and slides with the tube's own perspective.
vec2 pipP = cam_project(vec3(0.0, pipTop + 0.5 * pipR, 0.0), rayO, camB, camNear);
float tipD = length(p - pipP) / (0.30 * pipR);
float tip = exp(-tipD * tipD);
glassLight += vec3(0.90, 0.95, 1.0) * tip * 0.22;
alpha += tip * 0.06;


// --- what is inside -----------------------------------------------------
// The numerals' own space: y-up (the tube's y runs down the screen), the width
// of a numeral as the unit on both axes so a round wire stays round. The stack
// lives in the cylinder above the collar, which is where a nixie keeps it.
const float DIGIT_H = 25.0;   // the numerals, mm: a margin at each end of the 35 mm bulb
const float DIGIT_W = 14.0;   // and across: the ink now keeps Iosevka's own aspect, 0.51
const float GLYPH_H = 2.04;   // how tall the glyphs in digitWire() are
const float GLYPH_W = 0.85;   // and how wide the box a numeral is drawn in is
// The numerals are 25 mm high here, and the glyphs in digitWire() run from
// -1.02 to +1.02, i.e. 2.04 units tall, so one unit is 25/2.04 mm. The box
// across is 0.85 units, and the numerals inside it run to about ±0.33, which is
// the 10 mm an IN-12's numeral measures. The wire is a real cathode, and a fat
// one: 0.38 mm to its edge, so 0.76 mm across.
float gy = (DIGIT_H / GLYPH_H) * mm;
float gx = (DIGIT_W / GLYPH_W) * mm;
float gm = sqrt(gx * gy);
float digitMid = 0.5 * (apexY + footY);   // the glass's middle
vec2 centre = vec2(0.0, digitMid);        // and the glyphs are centred on it

// Where the camera's ray crosses the cathode's plane: the numerals stand on a
// real plane in front of the axis, so which part of a numeral a pixel sees
// depends on the camera's angle — that is the parallax, and it is the plane
// that moves, not the glyph. sp is that crossing in the drawing's own pixels;
// kc undoes the plane's dead-ahead magnification, so the numerals keep the
// size the drawing gives them and only their position answers the camera.
float Zc = CATHODE_Z * R;
float kc = max(1.0 - Zc / max(camNear, 1.0), 0.2);
vec2 sp = plane_hit(rayO, rayD, Zc) / kc;
vec2 dp = vec2((sp.x - centre.x) / gx, (centre.y - sp.y) / gy);
// The cathode's radius: the theme says what share of a numeral's height it
// takes (nixieWire), and the numeral is 25 mm here — 0.044 of it is the 1.10 mm
// this is drawn at, so the wire is 2.20 mm across. A real cathode is
// 0.24 mm; this one is heavy on purpose, because what the eye reads at the
// login's size is the glowing filament, and a hairline reads as nothing.
float wirePx = pWire * DIGIT_H * mm;
bendK = wirePx / gm;   // the bend of a bent wire is its own radius
float baseTop = footY;

// the two rods the stack is welded to: they stand with the stack, on its
// plane, so the camera moves them with the numerals. The workbench reads the
// drawing's rod offset out of this file by the marker
//   float rods = min(abs(abs(p.x) - 7.4 * mm), 1e5);
// which is why that line is kept here as the comment you are reading — the
// rods themselves are measured on the stack's plane, not on the screen.
// Balanced and lite sample the room once for the whole tube instead of once
// per part: the parts keep their own tint and Fresnel, and that is what still
// tells them apart; the roughness blur is quantised to one radius.
vec3 sharedMetalEnv = vec3(0.0);
if (quality >= 0.5 && quality < 1.5) sharedMetalEnv = metal_env(px, Ncyl, VIEW, 0.35);
float rodRel = min(abs(abs(sp.x) - 7.4 * mm), 1e5) / max(0.8, 0.10 * mm);
float rodMask = exp(-rodRel * rodRel) * step(sp.y, apexY + 0.22 * bulbH) * step(baseTop, sp.y);
vec3 rodMetal = metal_for(px, Ncyl, VIEW, vec3(0.56, 0.55, 0.52), 0.25, sharedMetalEnv, quality);
colour += rodMetal * rodMask * 1.6;
alpha += rodMask * 0.42;

// the mica washers that hold the stack together: discs, seen edge-on
for (int w = 0; w < 2; w++) {
// The two mica washers clamp the stack, so they sit where the numerals end:
// 0.66 of the box above and below its middle, which is inside the glass.
float wY = digitMid + ((w == 0) ? -0.66 : 0.66) * 9.0 * mm;
float lineRel = (sp.y - wY) / max(0.6, 0.05 * mm);
float line = exp(-lineRel * lineRel) * inside * step(abs(sp.x), 0.84 * bulbR);
colour = mix(colour, vec3(0.26, 0.26, 0.29), line * 0.65);
alpha += line * 0.30;
float micaRel = (sp.y - wY + 0.4) / max(0.5, 0.02 * mm);
glassLight += vec3(0.9, 0.92, 1.0) * exp(-micaRel * micaRel) * inside * step(abs(sp.x), 0.84 * bulbR) * 0.12;
}

// the unlit cathodes: nine wires in the stack, drawn as the grey metal they are
float stack = 0.0;
if (bulb < 0.5) {
for (int i = 0; i < 10; i++) {
if (abs(float(i) - digit) < 0.5) continue;
// Lite draws every other unlit cathode: five wires instead of nine, and the
// stack is mixed at a sixth of the cathode colour, so the ones left out are
// the dimmest part of an already dim bundle.
if (quality >= 1.5 && mod(float(i), 2.0) > 0.5) continue;
// The nine unlit cathodes stand behind the lit one, each on its own plane a
// third of a millimetre further back: the camera reads every one of them from
// its own angle, so the stack has real depth. The fan of the drawing — each
// lead bends a little differently — is kept as a lateral offset of the wire
// in its own plane, so dead ahead the picture is the drawing's.
float depth = float(i) - 4.5;
float zi = Zc - depth * 0.35 * mm;
vec2 qi = plane_hit(rayO, rayD, zi) / max(1.0 - zi / max(camNear, 1.0), 0.2);
vec2 q = (vec2((qi.x - centre.x) / gx, (centre.y - qi.y) / gy)
          - vec2(depth * 0.010, depth * -0.007)) / (1.0 - 0.012 * abs(depth));
stack = max(stack, (1.0 - smoothstep(-0.003, 0.003, digitWire(i, q) * gm - wirePx)) * (1.0 - 0.05 * abs(depth)));
}
stack *= pStack;
float stem = clamp(stack * 1.8, 0.0, 1.0);
colour = mix(colour, pCathode.rgb * 0.16, stem);
alpha = mix(alpha, 0.34, stem * 0.9);
// the lit edge of each wire: a cathode in a lamp is metal, and metal always
// catches some of the room, so the stack reads even over a dark picture
colour += metal_for(px, Ncyl, VIEW, vec3(0.50, 0.50, 0.53), 0.40, sharedMetalEnv, quality) * clamp(stack - 0.35, 0.0, 1.0) * 0.75;
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
// The cage is a real cylinder around the stack: the ray meets its near side
// and its far side, and each meets it at its own azimuth and height. The mesh
// then turns with the camera — its wires run around a real surface — and when
// the camera looks down, the far half rides up behind the near one.
float tCageF = -1.0;
float tCageB = -1.0;
{
    float ca = dot(rayD.xz, rayD.xz);
    float cb = dot(rayO.xz, rayD.xz);
    float cc = dot(rayO.xz, rayO.xz) - cageR * cageR;
    float cdisc = cb * cb - ca * cc;
    if (ca > 1e-8 && cdisc > 0.0) {
        float csq = sqrt(cdisc);
        tCageF = (-cb - csq) / ca;
        tCageB = (-cb + csq) / ca;
    }
}
vec3 Pf = (tCageF > 0.0) ? (rayO + tCageF * rayD) : vec3(0.0);
vec3 Pb = (tCageB > 0.0) ? (rayO + tCageB * rayD) : vec3(0.0);
vec2 spf = Pf.xy / max(1.0 - Pf.z / max(camNear, 1.0), 0.2);
vec2 spb = Pb.xy / max(1.0 - Pb.z / max(camNear, 1.0), 0.2);
if (tCageF > 0.0 && spf.y > cageTop && spf.y < cageBottom) {
    // The wires stand on the cage's own generators: the azimuth comes from
    // where the camera puts the surface, so the mesh turns with it — and at
    // dead ahead that is the drawing's asin(x/r) exactly.
    float uu = asin(clamp(spf.x / cageR, -0.999, 0.999)) / (PI * 0.5);
    float cageV = abs(fract(uu * 12.0) - 0.5) * 2.0 / 0.16;
    float cageH = abs(fract(spf.y / (1.0 * mm)) - 0.5) * 2.0 / 0.18;
    float wireV = exp(-cageV * cageV);
    float wireH = exp(-cageH * cageH);
    float railsRel = abs(p.x) - cageR;
    float rails = exp(-railsRel * railsRel);
    grid = max(max(wireV, wireH * 0.65), rails);
    grid *= step(abs(Pf.x), cageR);
    // no seam where the cage ends: the wires fade over the last few px
    cageFade = clamp((spf.y - cageTop) / 8.0, 0.0, 1.0) * clamp((cageBottom - spf.y) / 8.0, 0.0, 1.0)
             * clamp((cageR - abs(spf.x)) / 6.0, 0.0, 1.0);
    grid *= cageFade;
}
// the discharge lives inside the cage: the mesh glows where it is touched.
// A dark tube has no discharge to glow from, so the field is only measured
// when there is a digit under the mesh at all.
float near = 0.0;
if (digit >= -0.5) near = exp(-max(digitWire(int(digit + 0.5), dp) * gm - wirePx, 0.0) / (1.3 * mm));
cageGlow = pHalo.rgb * near * glow * 0.60;
// The mesh is a wire in the discharge, so it is hot: 320 K where the gas is
// cold, up to ~1100 K where the arc touches it. At that temperature it is not
// reflecting the room any more, it is making its own light — dull red, and
// strongest right where the numeral it surrounds is lit.
float meshTemp = 320.0 + 780.0 * near * glow;
vec3 meshEmit = blackbody(meshTemp) * heat_power(meshTemp, 3.4) * (0.12 + 0.88 * near);
// Metal blocks the picture instead of adding to it: the mesh darkens what is
// behind it and catches one lit edge from the left.
colour = mix(colour, vec3(0.030, 0.034, 0.042) + cageGlow, grid * 0.72);
alpha = mix(alpha, 0.55, grid * 0.55);
// the far half of the same mesh, seen through the tube behind the numeral
float gridBack = 0.0;
if (tCageB > 0.0 && spb.y > cageTop && spb.y < cageBottom) {
    float uub = 2.0 - asin(clamp(spb.x / cageR, -0.999, 0.999)) / (PI * 0.5);
    float backV = abs(fract(uub * 12.0 + 0.5) - 0.5) * 2.0 / 0.16;
    float backH = abs(fract(spb.y / (1.0 * mm) + 0.5) - 0.5) * 2.0 / 0.18;
    gridBack = max(exp(-backV * backV), exp(-backH * backH) * 0.65);
    gridBack *= step(abs(Pb.x), cageR) * cageFade;
}
colour = mix(colour, vec3(0.020, 0.022, 0.028), gridBack * 0.34);
alpha = mix(alpha, 0.34, gridBack * 0.30);
colour += metal_for(px, Ncyl, VIEW, F0_RHODIUM, 0.35, sharedMetalEnv, quality) * clamp(grid - 0.45, 0.0, 1.0) * 0.60;
// the mesh's own emission: it lands on the wires and on the gas around them
colour += meshEmit * grid * (0.55 + 0.45 * min(glow, 1.0));

// --- the metal insert ---------------------------------------------------
// The ring and the sleeve stand inside the cage's own window, which is the
// block they have always been drawn through.
if (p.y > cageTop && p.y < cageBottom) {
// Two pieces of plated metal that a real lamp has and a drawing does not: the
// ring the anode cage hangs from at the top, and the sleeve the stack is
// welded into at the foot. Both are inside the glass, both are machined, and
// they are what the eye reads as "this thing was made", not printed.
float ringY = cageTop - 0.6 * mm;
float ringRel = (sp.y - ringY) / max(0.5, 0.45 * mm);
float ringMask = exp(-ringRel * ringRel)
               * step(abs(sp.x), cageR + 0.9 * mm) * inside;
if (ringMask > 0.002) {
// a torus seen edge-on: the tube of the ring itself, lit along its own axis
float ringTubeRel = (abs(abs(sp.x) - cageR) - 0.0) / max(0.5, 0.45 * mm);
float ringTube = exp(-ringTubeRel * ringTubeRel);
vec3 ringMetal = metal_for(px, Ncyl, VIEW, F0_GOLD, 0.22, sharedMetalEnv, quality);
colour = mix(colour, ringMetal * 1.25, ringMask * (0.35 + 0.65 * ringTube));
alpha = mix(alpha, 0.68, ringMask * 0.55);
glassLight += ringMetal * ringMask * ringTube * 0.35 * pHighlight;
// the ring is a metal in the discharge: one temperature, one blackbody call
float ringTemp = 360.0 + 240.0 * glow;
colour += blackbody(ringTemp) * heat_power(ringTemp, 2.0) * ringMask * 0.12;
}
float sleeveTop = footY + 2.6 * mm;
float sleeveRel = (sp.y - sleeveTop) / max(0.6, 0.5 * mm);
float sleeve = exp(-sleeveRel * sleeveRel)
             * step(abs(sp.x), 5.6 * mm) * inside;
if (sleeve > 0.002) {
// the sleeve is a rhodium-plated cylinder around the stem, and it is the one
// part of the inside that the numerals never cover
float sleeveSideRel = (abs(sp.x) - 5.6 * mm) / max(0.5, 0.45 * mm);
float sleeveSide = exp(-sleeveSideRel * sleeveSideRel);
vec3 sleeveMetal = metal_for(px, Ncyl, VIEW, F0_RHODIUM, 0.30, sharedMetalEnv, quality);
colour = mix(colour, sleeveMetal * 0.95, sleeve * (0.40 + 0.60 * sleeveSide));
alpha = mix(alpha, 0.72, sleeve * 0.5);
colour += sleeveMetal * sleeve * sleeveSide * min(glow, 1.0) * 0.25;
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
	float eyeRing = abs(length((sp - lc) / vec2(1.0, 0.78)) - 0.72 * mm) - 0.26 * mm;
	float eyeMask = (1.0 - smoothstep(-0.5, 0.5, eyeRing)) * inside;
	// the lead, from the eye to the foot; inside cuts it where the glass tapers
	float eyeLeadRel = (sp.x - lx) / max(0.20 * mm, 0.5);
	float eyeLead = exp(-eyeLeadRel * eyeLeadRel)
	              * smoothstep(leadY - 0.5 * mm, leadY + 0.5 * mm, sp.y) * step(sp.y, footY) * inside;
	vec3 eyeMetal = metal_for(px, Ncyl, VIEW, F0_RHODIUM, 0.24, sharedMetalEnv, quality);
	colour = mix(colour, eyeMetal * 1.05, eyeMask + eyeLead * 0.65);
	alpha = mix(alpha, 0.62, eyeMask * 0.85 + eyeLead * 0.45);
	// lit from the left, as the rest of the metal in the tube is
	colour += vec3(0.15, 0.15, 0.16) * (eyeMask + eyeLead * 0.45) * ((e == 0) ? 1.0 : 0.35);
}

// --- what the years put on the glass -------------------------------------
// Two films, both thin and both uneven, because neither was painted on. The
// getter the tube was flashed with condenses on the inside of the dome as a
// silvery mirror; the cathode it has burnt off lands on the glass around the
// foot as a dark, warm film. The weights below are the film at its thickest:
// pAge multiplies them — 1 is today's patina, 0 a tube that has just been
// made — and a coarse hash makes each film patchy. Both absorb first — the
// picture behind the glass dims through them — and reflect second: metal_for()
// throws back the room the rods and the collar reflect.
//
// The getter: a mirror over the top cap, thinning down the cylinder. The cap's
// own sphere is the natural mask; 0.62 is where the film is judged to stop, and
// 0.50 is how much of the picture it hides at its thickest. The sputter is the
// weaker film (0.38) and shorter (about 6.5 mm above the foot).
float domeT = clamp((-(P1.y) - capOffset) / max(bulbR, 1.0), 0.0, 1.0);
float getterFilm = smoothstep(0.02, 0.62, domeT) * (0.52 + 0.48 * hash(floor(p / max(1.0, 1.7 * mm))));
float getter = getterFilm * inside * age;
// the sputter: heaviest in the last few millimetres above the foot, where the
// cathode's own metal lands, and thinning up the tube over about 6 mm
float footT = exp(-max(footY - P1.y, 0.0) / (6.5 * mm));
float sputterFilm = footT * (0.45 + 0.55 * hash(floor(p / max(1.0, 1.1 * mm)) + 37.0));
float sputter = sputterFilm * inside * age;
// absorption and reflection of each film: the getter is cold silver, barium's
// own n and k, the sputter is nearly black and warm, as burnt tungsten is.
// The masks are zero over most of the tube, so the film's own reflection is
// only sampled where there is film to reflect.
refract *= 1.0 - clamp(0.50 * getter + 0.38 * sputter, 0.0, 0.90);
alpha = mix(alpha, 0.55, getter * 0.55);
alpha = mix(alpha, 0.45, sputter * 0.50);
if (getter > 0.0) {
colour += metal_for(px, N3, VIEW, vec3(0.60, 0.61, 0.64), 0.30, sharedMetalEnv, quality) * getter * 0.80;
}
if (sputter > 0.0) {
colour += metal_for(px, N3, VIEW, vec3(0.19, 0.17, 0.15), 0.55, sharedMetalEnv, quality) * sputter * 0.35;
}

// --- the discharge --------------------------------------------------------
// The lit cathode is a wire with a gas sheath around it, and nothing else on
// the tube is anywhere near this bright: the metal's own radiance is a black
// body's at its temperature, and the exposure below is what makes its core
// read as white.
vec3 add = vec3(0.0);
// The theme hands the gas colour as a display value; the discharge is summed as
// light, so it is linearised once here rather than carried as a code value.
// The hue the tube's own light takes: the theme's coloured glass, or the
// wallpaper's accent when the theme asks for that. One reading per tube, so the
// whole discharge of a numeral is one colour.
vec4 tint = effective_tint(accent);
vec3 gasColour = tinted(pow(pHalo.rgb, vec3(2.2)), tint);
float gasMap = 0.0;
// The wire's own radiance, kept apart from everything else the discharge adds:
// it is the only thing in the tube that stands above white, and it is what the
// exposure at the end of main() is scaled for.
float wireRadiance = 0.0;
// The colour of the wire's own surface, kept with the radiance: it is Planck's
// for the metal's temperature, not a fixed tint.
vec3 wireGlowColour = vec3(0.0);
if (bulb > 0.5) {
float bulbD = length(p - vec2(0.0, 0.0)) - 5.0 * mm;   // the colon, one round bulb
float lit = 1.0 - clamp((bulbD + 0.4) / 0.8, 0.0, 1.0);
gasMap = exp(-max(bulbD, 0.0) / (0.30 * 5.0 * mm)) * 0.60 + exp(-max(bulbD, 0.0) / (1.4 * 5.0 * mm)) * 0.25;
wireGlowColour = tinted(blackbody(pTempK), tint);
wireRadiance = lit * 1.20 * glow * flicker * heat_power(pTempK, 1.0);
add += wireGlowColour * wireRadiance;
add += gasColour * gasMap * 0.15 * glow * pow(flicker, 1.4);
} else if (digit >= -0.5) {
// The strand the ribbon flag speaks about is this digit's own: clear what the
// stack's cathodes left behind before the lit wire is measured.
wirePass = 0.0;
float wireField = digitWire(int(digit + 0.5), dp) * gm;   // the field, measured once
float wireDist = wireField - wirePx;
float dist = max(wireDist, 0.0);
// The core is the metal itself: full where the wire's own axis is, nothing at
// its surface. It is a width in millimetres (the cathode is 0.24 mm across),
// not a fraction of a pixel, which is what a white-hot filament is.
float axis = wireField;
// A heated wire is a surface, and a surface at one temperature has one
// radiance: the section is flat, not a ramp. What makes a real filament read
// as a bright core is exposure — it stands several times above white, so the
// tone curve whitens it — and the optics, which soften its two edges. The soft
// edge below is that: about a pixel of defocus, not a painted gradient.
float core = 1.0 - smoothstep(wirePx - 0.5, wirePx + 0.5, axis);
// dense at the wire, tight around it, a faint wash inside the cage
// The sheath around the wire: the gas hugs a hot filament and falls away fast.
// A thicker cathode carries more of it, so the sheath is wider and denser than
// the hairline one a thin wire would have.
float gas = exp(-dist / (0.27 * mm)) * 0.070 + exp(-dist / (0.66 * mm)) * 0.016;
gas *= 0.955 + 0.09 * hash(floor(px / 2.0));
// A discharge is never perfectly still: the glow wanders, the wire hums with
// the mains, and the eye reads that slow irregular drift as a lamp that is on.
// Two sines for the breathing (so its period never reads as a beat) and one
// for the hum; per cent, not per ten — a login screen that strobes is a bug.
// pShimmer scales those two amplitudes only: 0 leaves the wire and the gas
// just as lit as ever, with no periodic motion.
float breathe = 1.0 + shimmer * 0.035 * sin(pTime * 2.1 + p.y * 0.013) * sin(pTime * 0.7 + 1.3);
float hum = 1.0 + shimmer * 0.015 * sin(pTime * 8.0 + dp.y * 2.0);
float coreLit = glow * pow(flicker, 0.5);
float haloLit = glow * pow(flicker, 1.4) * breathe;
// The wire is held at its two ends by the stack's rods, and heat conducts out
// through them: the run sits at pTempK where it is far from both ends and loses
// HEAT_END_DROP kelvin at the ends themselves. The distance to the nearer end
// is the cheap stand-in for the position along the run — exact along a straight
// stroke, an overestimate around a bend, which is enough for a glow.
vec4 ends = digitEnds(int(digit + 0.5));
float endDist = min(length(dp - ends.xy), length(dp - ends.zw));
float heatProfile = clamp(endDist / HEAT_FALLOFF, 0.0, 1.0);
float wireTemp = pTempK - HEAT_END_DROP * (1.0 - heatProfile);
wireGlowColour = tinted(blackbody(wireTemp), tint);
// A wire that hot is its own light: Planck's colour for the colour, and
// Stefan-Boltzmann's fourth power for the power. heat_power() is measured
// against the 2550 K the theme is drawn at, so the knob at its default leaves
// the picture exactly where it was and turning it up makes the discharge hotter.
// The white core is what a wire at pTempK looks like; where the wire runs
// cooler the metal keeps its own blackbody colour instead of burning white.
vec3 wireColour = wireGlowColour;   // the metal's own colour, everywhere on the wire
float wireHeat = heat_power(wireTemp, 1.0);
// A real filament is not uniformly hot along its length either: a slow hash on
// the numeral's own millimetres keeps the run from reading as a drawn line.
float filament = 1.0 + 0.07 * hash(floor(dp * 22.0));
// Emission of the metal itself: emissivity times Stefan-Boltzmann, and a metal
// cylinder is darker towards its limbs — Kirchhoff's law again: the emissivity
// at a grazing angle is one minus a reflectance that is rising there. The
// cosine below is the surface's own angle to the eye across the wire, so the
// stroke keeps a soft edge without a painted ramp.
float cosvBase = clamp(axis / max(wirePx, 0.5), 0.0, 1.0);
float cosv = sqrt(max(0.0, 1.0 - cosvBase * cosvBase));
float limb = 1.0 - 0.55 * (1.0 - cosv) * (1.0 - cosv);
wireRadiance = core * limb * coreLit * wireHeat * filament * hum * (1.0 + 0.11 * wirePass);
add += wireColour * wireRadiance;   // the metal itself, and no wider than the wire
// The wire's own light scattered in the gas right at its surface: a thin warm
// skin, no wider than half a millimetre. Without it the unlit cathodes of the
// stack — which are cool metal, and the theme's bluish cathode colour — showed
// through as a blue rim around every lit stroke.
add += wireGlowColour * exp(-max(axis - wirePx, 0.0) / (0.35 * mm)) * 0.05 * coreLit * wireHeat;

// The gas hugs the wire where it is hot, so the sheath thins towards the ends
// with the wire itself: a cooler stretch of cathode carries a dimmer glow.
float gasHeat = 0.60 + 0.40 * heatProfile;
// A hot run gives off more gas in places: the sheath breathes along the wire
// instead of being drawn at one width.
float sheath = 0.90 + 0.20 * hash(floor(dp * 6.0) + 41.0);
// Glass and a lens split a bright line, blue on one flank and red on the
// other. Two more taps of the numeral's own field, a pixel to either side,
// carry that fringe; the green channel keeps the undistorted sheath.
float axisR = digitWire(int(digit + 0.5), dp + vec2(1.4 / gm, 0.0)) * gm;
float axisB = digitWire(int(digit + 0.5), dp - vec2(1.4 / gm, 0.0)) * gm;
float distR = max(axisR - wirePx, 0.0);
float distB = max(axisB - wirePx, 0.0);
float gasR = exp(-distR / (0.23 * mm)) * 0.17 + exp(-distR / (0.56 * mm)) * 0.040;
float gasB = exp(-distB / (0.23 * mm)) * 0.17 + exp(-distB / (0.56 * mm)) * 0.040;
add += vec3(gasR * gasColour.r, gas * gasColour.g, gasB * gasColour.b) * gasHeat * sheath * 0.20 * haloLit;
add += gasColour * exp(-dist / (3.1 * mm)) * 0.025 * gasHeat * haloLit;   // the soft bloom a hot wire casts
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
float wallRefl = exp(-max(digitWire(int(digit + 0.5), rMirror) * gm - wirePx, 0.0) / (2.2 * mm));
// the light the wire throws on the far wall drifts with the gas itself
add += mix(gasColour, wireGlowColour, 0.5) * wallRefl * 0.025 * pow(abs(xr), 1.5) * inside * haloLit * breathe;
gasMap = gas;
colour += cageGlow * 0.25;
}

// Exposure and tone mapping. The discharge is summed as light — the wire's
// colour comes from the measured Planck fit, the gas's is linearised above —
// and mapped once, at the end: the curve rolls the top off and the result is
// encoded back into the display values the rest of the pass (and the
// compositor) work in.
//
// What the old code did: mapped `add` with 1-exp(-1.55x), a saturation curve
// with no shoulder, which cannot express "brighter than white" at all — and
// then added a "headroom" of the wire's excess on top of the *display* value,
// where an 8-bit sRGB surface simply clips it. The excess was a fixed 0.10 of
// a number that already had a gain and an exposure folded into it.
add = pow(tone_map(add * clamp(pExposure, 0.0, 30.0)), vec3(0.4545));
float spill = exp(-max(sd, 0.0) / (0.9 * bulbR)) * 0.90
            + exp(-max(sd, 0.0) / (3.0 * bulbR)) * 1.05
            + exp(-max(sd, 0.0) / (9.0 * bulbR)) * 0.55;
// The light the discharge throws: its own colour, and how much of it lands on
// the glass is the theme's nixieWarmth — 0.45 is the tube's own look, so the
// token multiplies it instead of repainting the picture.
vec3 wash = mix(pHalo.rgb, pow(tinted(blackbody(pTempK), tint), vec3(0.4545)), 0.65);
float warmth = clamp(pWarmth / 0.45, 0.0, 3.0);
// The discharge's light lands on the wallpaper (the spill) — and inside the
// glass it is the light itself, which the composite adds. Adding it here as well
// counted every ray of it twice, which is what fattened the white core to two
// and a half times the wire's own width. It is light, not the discharge: a
// twelfth of the wire's own radiance, spread wide, is what a hot wire throws.
//
// The spill is the one thing here that reaches past the glass, and the item it
// is drawn in is finite: at its border the light used to stop dead, which put a
// rectangle of lamp-lit wallpaper around every tube — plain to see once the
// tubes sit against each other. `edge` is the distance to that border, and the
// spill fades to nothing over the last two margins of it, so the lamp lights the
// desk without drawing its own box.
colour += wash * add * spill * warmth * 0.12 * edgeFade;
alpha += clamp(gasMap * glow * 0.10, 0.0, 0.30) * inside;

// --- the collar the tube is plugged in by ---------------------------------
if (collarH > 0.5) {
// The collar's own mask: a rounded box from the glass's foot down to the box's
// bottom, Ø21 as the drawing has it. It cannot use the bulb's mask — the bulb
// ends where the collar begins.
// The base is a body of revolution like the bulb: pitch tips its top face
// towards the camera — the disc the glass stands in becomes visible, which is
// the one cue a base gives that its own front cannot — and shortens the
// crimps; yaw leaves its width alone. ellV is how far the near edge of that
// face sits below its far edge on the film.
float sinP = camB[2].y;                        // the pitch, signed
float ellV = 10.5 * mm * sinP;
vec2 pc = vec2(p.x, (p.y - ellV) / max(axisCos, 0.2));
vec2 bc = vec2(0.0, footY + 0.5 * collarH);
float sdCollar = sdRoundBox(pc - bc, vec2(10.5 * mm, 0.5 * collarH), 0.8 * mm);
float insideCollar = 1.0 - smoothstep(-0.8, 0.8, sdCollar);
float bm = insideCollar * clamp((pc.y - (baseTop - 1.5)) / 3.0, 0.0, 1.0);
float side = clamp(pc.x / max(10.5 * mm, 1.0), -1.0, 1.0);   // the collar, Ø21
float uu = asin(clamp(side, -0.999, 0.999)) / (PI * 0.5);
// crimped metal: flutes, lit from the left, its foot going dark
vec3 ceramic = vec3(0.032, 0.031, 0.033) * (0.30 + 0.70 * sqrt(max(0.0, 1.0 - side * side)));
ceramic += metal_for(px, Ncyl, VIEW, vec3(0.29, 0.30, 0.33), 0.45, sharedMetalEnv, quality) * 0.55;   // steel: the room, dimmed
float crimp = fract(uu * 14.0) - 0.5;
float crimpRel = crimp * 2.0 / 0.55;
ceramic *= 1.0 - 0.20 * exp(-crimpRel * crimpRel); // the moulding's crimps
float beadRel = crimp * 2.0 / 0.30 + 1.2;
ceramic += vec3(0.045) * exp(-beadRel * beadRel) * max(0.0, side + 0.4);
colour = mix(colour, ceramic, bm);
alpha = mix(alpha, 0.96, bm);
float ridgeRel = abs(crimp) * 2.0 / 0.30;
colour += vec3(0.030) * exp(-ridgeRel * ridgeRel) * bm * (0.5 + 0.5 * side);
float baseRel = (pc.y - baseTop) / 1.1;
float edge = exp(-baseRel * baseRel) * insideCollar;
colour += vec3(0.20, 0.20, 0.21) * edge * (0.35 + 0.65 * min(glow, 1.0));   // the flange, moulded and matte
alpha += edge * 0.35;
// The face of the base: the disc the glass stands in, seen because the camera
// is above the lamp. Its far rim is the ellipse's top edge and the flange above
// is its near rim; the glass covers the middle of it.
if (abs(ellV) > 0.5) {
	float facePlot = length(vec2(pc.x, p.y - footY * axisCos) / vec2(10.5 * mm, max(abs(ellV), 0.5)));
	float faceMask = (1.0 - smoothstep(0.96, 1.04, facePlot)) * (1.0 - inside);
	vec3 faceMetal = metal_for(px, Ncyl, VIEW, vec3(0.30, 0.30, 0.33), 0.45, sharedMetalEnv, quality);
	colour = mix(colour, faceMetal * 0.85, faceMask * 0.90);
	alpha = max(alpha, faceMask * 0.90);
}
float footDarkRel = (pc.y - (baseTop - 2.2)) / 1.6;
colour *= 1.0 - 0.35 * exp(-footDarkRel * footDarkRel) * insideCollar;
float footLightRel = (pc.y - (boxMid + 0.5 * collarH) + 1.2) / 1.2;
colour += vec3(1.0) * exp(-footLightRel * footLightRel) * insideCollar * 0.09;

// The pins: Ø1 mm, twelve of them, on the sheet's 11.5 mm circle. They are what
// the lamp is plugged in by and nothing else, and a base that stops at its own
// rim reads as a cap. They stand on a real circle below the collar, so the
// camera moves each one by its own depth: yaw walks them around the circle and
// pitch drops the front ones and raises the back.
float collarBottom = footY + collarH;
float pinCircle = 5.75 * mm;      // the sheet's 11.5 mm circle, as a radius
float pinR = 0.5 * mm;            // Ø1 mm
float pinLen = 7.0 * mm;          // and 7 mm long, as the sheet has them
// the item's own edge cuts the pins: fade them instead of clipping them hard
float pinEdge = clamp((0.5 * tile.y - p.y) / max(1.0, 0.75 * mm), 0.0, 1.0);
for (int i = 0; i < 12; i++) {
	float a = float(i) * 0.5235987756;   // twelve pins, 30 degrees apart
	vec3 pinRoot = vec3(pinCircle * cos(a), collarBottom, pinCircle * sin(a));
	vec2 pinA = cam_project(pinRoot, rayO, camB, camNear);
	vec2 pinB = cam_project(pinRoot + vec3(0.0, pinLen, 0.0), rayO, camB, camNear);
	float shaftRel = (p.x - pinA.x) / max(pinR, 0.6);
	float shaft = exp(-shaftRel * shaftRel);
	float tip = 1.0 - smoothstep(pinA.y + 0.60 * (pinB.y - pinA.y), pinB.y, p.y);
	float pinMask = shaft * tip * pinEdge * smoothstep(pinA.y - 0.5 * mm, pinA.y, p.y);
	vec3 pinMetal = metal_for(px, Ncyl, VIEW, F0_NICKEL, 0.32, sharedMetalEnv, quality);
	colour = mix(colour, pinMetal * 1.10, pinMask);
	alpha = mix(alpha, 0.95, pinMask);
	// the pin's own roundness catches the left light the rest of the metal gets
	float pinLightRel = (p.x - pinA.x + 0.40 * pinR) / max(0.40 * pinR, 0.4);
	colour += vec3(0.13, 0.13, 0.14) * pinMask * exp(-pinLightRel * pinLightRel);
}

// The collar's own terminals: the two eyelets on its top face, where the glass's
// leads come through and are soldered. They are gold, like the collector ring,
// and they are what ties the base to the stack above it.
for (int e = 0; e < 2; e++) {
	float tx = (e == 0) ? -7.4 * mm : 7.4 * mm;
	vec2 tc = cam_project(vec3(tx, footY + 0.9 * mm, 0.0), rayO, camB, camNear);
	float termRing = abs(length((p - tc) / vec2(1.0, 0.72)) - 0.68 * mm) - 0.26 * mm;
	float termMask = (1.0 - smoothstep(-0.5, 0.5, termRing)) * insideCollar;
	vec3 termMetal = metal_for(px, Ncyl, VIEW, F0_GOLD, 0.26, sharedMetalEnv, quality);
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

// The glass passes the picture it bends (refract, absorbed, and thinned where
// the metal inside it stands), the tube's own light and the discharge add on top
// of it, and the cover is what the body hides: the wallpaper the compositor drew
// under this item is hidden wherever the tube stands in front of it. Before the
// clock was one item the patch was never handed in, so the cover only mattered
// at the silhouette and the wallpaper showed straight through the glass.
return vec4(colour + add + refract * clamp(1.0 - alpha, 0.0, 1.0) * inside,
		clamp(max(alpha, inside), 0.0, 0.98));
}

void main() {
const float PI = 3.14159265;

vec2 px = qt_TexCoord0 * pSize;
// the item's own border, and the fade the lamp's light dies by towards it
float edge = min(pSize.x * 0.5 - abs(px.x - pSize.x * 0.5),
                 pSize.y * 0.5 - abs(px.y - pSize.y * 0.5));
float edgeFade = smoothstep(0.0, 1.0, clamp(edge / max(2.0 * pInset, 1.0), 0.0, 1.0));
// Read once for the whole item: one lamp, one room, one colour.
vec3 accent = (pWallpaper.x > 0.0) ? wallpaper_accent() : vec3(0.0);
vec4 out_colour;
// The camera the whole item is photographed by: a pinhole pView.y tube widths
// in front of the item's centre plane, its film turned by the theme's yaw
// (pView.x) and pitch (pView.z) off that plane's normal. The basis is right,
// down (the drawing's own y) and forward; a pixel is the ray from the camera
// through its own place on the film, and the glass below meets that ray as
// real geometry. pView.y = 0 stands the camera at the default distance,
// 12 tube widths — a photo taken from about an arm's length away.
float camYaw = radians(clamp(pView.x, -30.0, 30.0));
float camPitch = radians(clamp(pView.z, -20.0, 20.0));
float cYawC = cos(camYaw), cYawS = sin(camYaw);
float cPitC = cos(camPitch), cPitS = sin(camPitch);
vec3 cRight = vec3(cYawC, 0.0, cYawS);
vec3 cDown = vec3(-cYawS * cPitS, cPitC, cYawC * cPitS);
vec3 cFwd = vec3(cYawS * cPitC, cPitS, -cYawC * cPitC);
mat3 camB = mat3(cRight, cDown, cFwd);
vec2 film = px - pSize * 0.5;                   // this pixel, on the film plane
float tubeW = (pTile.w < 0.5) ? max(pSize.x - 2.0 * pInset, 1.0)
                              : max(pTile.x - 2.0 * pTile.z, 1.0);
const float CAM_TUBES = 12.0;
float camDist = ((pView.y > 0.0) ? max(pView.y, 1.0) : CAM_TUBES) * tubeW;
vec3 rayD = normalize(film.x * cRight + film.y * cDown + camDist * cFwd);
if (pTile.w < 0.5) {
    // The tube stands on the film's centre: its drawing is exactly the picture
    // this camera takes from dead ahead, so its frame is the camera's own.
    out_colour = nixie_tube(px, film, -camDist * cFwd, rayD, camB, camDist,
                            pSize, pInset, accent, pDigit, pFlicker, pBulb, edgeFade);
} else {
    // The row: four tubes in one pass, which is the only way their light adds up
    // into one lamp instead of four lit rectangles. The light is additive (the
    // compositor treats what a ShaderEffect writes as premultiplied), so the tubes'
    // contributions are summed; the alpha is coverage, and the glasses do not
    // overlap, so the largest wins.
    // Each tube's frame takes the camera off its axis: a tube further along the
    // row is further from the lens, so it is drawn smaller and its centre moves
    // inward — the row's perspective, now from one real camera instead of a
    // screen-space scale.
    vec4 acc = vec4(0.0);
for (int i = 0; i < 4; i++) {
// The tube's own frame: the camera is off its axis by this tube's place in
// the row, so the tube's depth along the view axis sets the film's scale
// there and its centre is where the camera puts it.
float x = pRowX[i];
float depth = camDist + x * cFwd.x;
float gs = camDist / max(depth, 1.0);
vec2 centre = gs * x * vec2(cRight.x, cDown.x);
// The tier's first cut: a pixel this far from the tube's centre sees none of
// its glass and only the dregs of its spill, so the whole tube is skipped.
// The rectangle is deliberately generous — 1.10 of the item's width and 0.90
// of its height from the centre leaves the bloom's tails (about 17 mm past the
// glass) room; measured against the same row without the cut, what it removes
// stays under 7/255 and is the spill's tail, not the lamp.
if (pQuality >= 0.5) {
float reachX = gs * 1.10 * pTile.x;
float reachY = gs * 0.90 * pTile.y;
if (abs(px.x - pSize.x * 0.5 - centre.x) > reachX
    || abs(px.y - pSize.y * 0.5 - centre.y) > reachY) continue;
}
vec2 p = (film - centre) / gs;
vec3 rayO = (-camDist * cFwd - vec3(x, 0.0, 0.0)) / gs;
vec4 tube = nixie_tube(px, p, rayO, rayD, camB, depth / gs,
                       pTile.xy, pTile.z, accent,
                       pRowDigit[i], pRowFlicker[i], 0.0, edgeFade);
	acc.rgb += tube.rgb;
	acc.a = max(acc.a, tube.a);
}
out_colour = acc;
}
fragColor = vec4(out_colour.rgb, out_colour.a) * qt_Opacity;
}
