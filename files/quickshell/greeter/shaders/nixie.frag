#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 1) out vec4 fragColor;

layout(binding = 0) uniform buf {
mat4 qt_Matrix;
float qt_Opacity;

vec2 pSize;        // the item: the envelope plus the room the bloom needs
float pInset;      // how much of pSize is the bloom's room
float pBase;       // height of the metal base band, px (0 = a plain envelope)
float pGlow;       // discharge strength (0 = the tube is on but shows nothing)
float pDigit;      // the lit cathode, 0..9; -1 = nothing is lit
float pBulb;       // 1 = the colon separator: one filled bulb, no numerals
float pWire;       // the cathode wire, as a fraction of the numeral's height
float pWarmth;     // how much of the discharge lands on the glass itself
float pFlicker;    // ignition progress, 1 = struck and steady
vec4 pCore;        // colour of the lit cathode
vec4 pHalo;        // colour of the gas around it
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
// ==== SECTION GLASS-OPTICS (L2) ====
// The envelope, the anode cage, the cathode stack and the collar are a
// pre-rendered sprite now (assets/nixie-tube.png). They never change, and
// offline there is room for real optics: two glass surfaces with Fresnel, a view
// bent by the wall, the wires with parallax between them, a crimped collar.
// This shader keeps what does change — the discharge of the lit cathode — and
// the shadow the tube throws on the wall behind it.
vec3 colour = vec3(0.0);
vec3 glassLight = vec3(0.0);
float alpha = 0.0;

// the numeral's own space: y-up, the width as the unit on both axes
float unit = 0.46 * hs.y;
vec2 centre = vec2(0.0, -0.075 * hs.y * 2.0);
vec2 dp = vec2(p.x - centre.x, centre.y - p.y) / unit;
float wireR = pWire;
float baseTop = hs.y - pBase;

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
float gas = exp(-dist / 0.050) * 1.00 + exp(-dist / 0.16) * 0.45 + exp(-dist / 0.42) * 0.15;
gas *= 0.90 + 0.22 * hash(floor(px / 2.0));
float coreLit = pGlow * pow(pFlicker, 0.5);
float haloLit = pGlow * pow(pFlicker, 1.4);
vec3 wireColour = mix(pCore.rgb, vec3(1.0, 0.96, 0.88), pow(core, 8.0) * 0.25);
		add += wireColour * core * 0.78 * coreLit;

add += pHalo.rgb * gas * 0.70 * haloLit;
// the fringe where the discharge dies out drifts violet
add += vec3(0.78, 0.24, 0.72) * exp(-abs(dist - 0.17) / 0.09) * 0.10 * step(0.06, dist) * haloLit;
// the far wall of the glass catches a squeezed, dim image of the wire
vec2 mp = vec2(-p.x * 0.86, p.y);
vec2 mirror = vec2(mp.x - centre.x, centre.y - mp.y) / unit;
add += pHalo.rgb * exp(-max(digitWire(int(pDigit + 0.5), mirror) - wireR, 0.0) / 0.22) * 0.10 * abs(xr) * haloLit;
gasMap = gas;
}

// exposure: the gas never reaches white, the wire always does
add = vec3(1.0) - exp(-add * 1.25);
// The discharge does not stop at the glass. A lamp burning in a dark room lays a
// warm wash on everything it can see: the wall behind it, the panel under it, the
// tube beside it. Without that wash the tube reads as a picture of a tube — the
// reviews called the result "stickers pasted on the wallpaper". The wash reaches
// far and falls off slowly; the tight term keeps the glass edge itself bright.
float spill = exp(-max(sd, 0.0) / (0.9 * hs.x)) * 0.55
            + exp(-max(sd, 0.0) / (3.0 * hs.x)) * 0.60
            + exp(-max(sd, 0.0) / (9.0 * hs.x)) * 0.30;
// The wash carries the discharge's own colour: the gas between the numerals is
// violet, but what a lamp throws on a wall is the warm end of it. The halo
// colour alone is too pale to read against the foliage, so the wash is mixed
// towards the core's orange before it lands.
vec3 wash = mix(pHalo.rgb, pCore.rgb, 0.65);
colour += add * inside + wash * add * spill;
alpha += clamp(gasMap * pGlow * 0.10, 0.0, 0.30) * inside;

	// ==== END SECTION COLLAR (L5) | SECTION COMPOSITE (L6) ====
// the glass lights land on the front surface, in front of everything inside
colour += glassLight * (1.0 - clamp(max(add.r, max(add.g, add.b)) * 0.9, 0.0, 0.85));

// The shadow the tube throws on the wallpaper: a lamp is a thing in front of a
// wall, and without this it floats. Analytic, like everything else here.
// Two widths: a core right at the silhouette and a wide soft one. A single
// radius read as a halo around the tube rather than as shade under it.
float shadow = exp(-max(sd, 0.0) / 7.0) * 0.55
             + exp(-max(sd, 0.0) / 26.0) * 0.45;
shadow *= clamp(0.35 + 0.65 * (-p.y / hs.y), 0.25, 1.0);
float outside = clamp(1.0 - inside, 0.0, 1.0);
	alpha = min(alpha + shadow * 0.52 * outside, 1.0);
	colour *= 1.0 - shadow * 0.46 * outside;

fragColor = vec4(colour + glassLight + add, clamp(alpha, 0.0, 0.98)) * qt_Opacity;
}
// ==== END SECTION COMPOSITE (L6) ====
