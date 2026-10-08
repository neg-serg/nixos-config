# Nixie clock on the login screen (nixie-tube)

The login screen's clock is four gas-discharge tubes and a colon between them. Nothing about a tube
is a picture: the glass, the picture bent through it, the cathode stack, the anode cage, the crimped
collar and the discharge of the lit numeral are one fragment shader, driven by a handful of uniforms.

## Files

| file | what it is |
| --- | --- |
| `files/quickshell/greeter/shaders/nixie.frag` | the tube: glass, optics, internals, discharge, collar |
| `files/quickshell/greeter/shaders/nixie.frag.qsb` | the same shader compiled for Quickshell (qsb, GLSL `100es,120,150`) |
| `files/quickshell/greeter/lock/NixieTube.qml` | one tube: uniforms, the strike, the wallpaper patch it refracts |
| `files/quickshell/greeter/lock/NixieClock.qml` | the row of four tubes and the gaps between them |
| `packages/nixie/` | the workbench: the same shader rendered off-screen on the GPU |

Rebuild the shader after every edit — Quickshell loads the `.qsb`, not the source:

```
QSB=$(ls -d /nix/store/*qtshadertools-6.11.2/bin/qsb | head -1)
"$QSB" --glsl "100es,120,150" -o files/quickshell/greeter/shaders/nixie.frag.qsb \
      files/quickshell/greeter/shaders/nixie.frag
```

## The envelope

Every number in the drawing comes from Reflector's IN-12A/B data sheet (1988): bulb Ø19 × 28 mm, base
Ø21 × 7 mm, pins Ø1 mm on an 11.5 mm circle, the pip Ø3.5 mm, the numerals 18 mm high, the whole lamp
35 mm without its pins. The drawing's box is 21 × 35 mm and it is the item that agrees with the sheet,
not a uniform: an item stretched by its parent would put the millimetre somewhere else. `pMm` is the
scale (px per millimetre) and the numerals are 25 mm high in it.

`nixie validate` checks that arithmetic: one axis, no gaps, the dome a real hemisphere on the
cylinder, the numerals inside the bore, the collar where the sheet puts it.

## The numerals

A cathode is a piece of wire that was bent, so every numeral is a distance field of its own centre
line in its own square space: x in -0.425..0.425 (its width), y in -1.02..1.02 (its height), both at
the same scale. The wire's radius is a theme token (see below) and the whole numeral is one connected
wire — the workbench checks that by rasterising it.

The primitives, all in `nixie.frag`:

- `sdSegment` — a straight piece of wire;
- `sdArc` — an arc of a circle, by centre, radius and an angular range;
- `sdEllipse` / `sdEllipseArc` — the same for a circle stretched to the numeral's proportions;
- `sdBentRect` — the outline of a rectangle whose four corners are quadrants of a circle of radius r:
  straight sides, bends of one radius, which is how a drawing font bends a wire;
- `sdRoundQuad` — a quadrilateral whose four corners are each replaced by an arc of one radius r,
  tangent to both of its edges: the sides run between the tangent points, not as chords across the
  corners. It is the loop that is wide at its crown and pinched at the waist, which is the 8's own
  shape;
- `smin` — a smooth union. It is still used where two strokes of different direction meet without a
  common tangent, but a bend with a known radius is built from quadrants, not from a softened corner.
  At an elbow the softening is the wire's own radius, taken from the `nixieWire` token (about
  0.90 mm at the heavy-duty default): a wire that was bent has the thickness of the wire it was bent
  from, no more.

The figures:

| digit | how it is bent |
| --- | --- |
| 0 | one oval |
| 1 | a mast with a flag |
| 2 | a shoulder (an arc), a diagonal and the foot |
| 3 | two ellipse arcs pinched together at the waist |
| 4 | a diagonal over a bar, with a mast |
| 5 | Iosevka's (Iosevkaneg): the bar with a short stub at its right end, the stem leaning left, and a bowl half a unit wide whose corners are quarters of a 0.25 circle |
| 6 | Iosevka's (Iosevkaneg): a closed bowl and a cap over it whose right-hand side stops short, `sdBentRect` with r = 0.24 |
| 7 | a lid and a leg |
| 8 | Iosevka's (Iosevkaneg): two loops, wide at their crowns and pinched at a shared waist, the lower a little wider, `sdRoundQuad` with r = 0.22 |
| 9 | a bowl and a leg |

The 5, the 6 and the 8 are not the drawing font's: they were measured off the user's own cut of
Iosevka (Iosevkaneg-Regular). The glyph raster gives the aspect, ~0.51, and a stroke about 11% of
the height; the profile gives the shapes — for the 5 a centre line taken off the glyph's own
skeleton: the bar at 0.835 with its stub down to 0.58, the stem's foot at −0.225/0.19, the waist at
0.0/0.23 and the bowl's sides at x = ±0.25 with its bottom at −0.83. The 6 is a closed bowl with a
cap over it whose right-hand side stops short — that gap is what makes it a 6 and not an 8 — and
every bend is a quadrant of r = 0.24. The 8 is two loops, wide at their crowns and pinched at a
shared waist, the lower a little wider than the upper, with r = 0.22.

## What the parts are made of

A metal is a mirror tinted by its own F0, and F0 is not a taste — it falls out of the metal's n and
k. The parts that have to survive a discharge and still read as jewellery are plated:

| part | material | F0 (550 nm) |
| --- | --- | --- |
| anode mesh | rhodium (n 2.06, k 5.31) | 0.79, 0.79, 0.80 |
| collector ring at the top of the cage | gold (n 0.47, k 2.40) | 1.00, 0.77, 0.34 |
| sleeve the stack is welded into | rhodium | 0.79, 0.79, 0.80 |
| rods and the unlit stack | nickel (n 1.90, k 3.90) | 0.56, 0.55, 0.52 |
| crimped collar | steel, matte | 0.29, 0.30, 0.33 |

Rhodium goes on the mesh and the sleeve: it does not tarnish, it survives the gas, and it keeps its
own colour neutral, so the only colour on it is the discharge. Gold goes where the eye looks for it.
The mesh's reflection is smeared by its own roughness (five taps in a cross, the radius from `rough`),
so the collar's polish and the wire do not reflect the room with the same sharpness.

**The mesh is hot.** A wire in a discharge is not a mirror, it is a heater: the fit below takes it
from the room's 320 K to about 1100 K where the arc touches it, which is where its own emission takes
over from the room's reflection. `blackbody()` is Planck's colour (Bartlett's sRGB fit) and
`heat_power()` is Stefan-Boltzmann's fourth power against the temperature the tube is drawn at
(2550 K), capped so a knob turned all the way up cannot blow the frame out. Measured on the render:
with the discharge on, the mesh's own region gains light with R/B ≈ 5 — dull red, as it should be.

**The metal's own colour is dull orange.** The theme draws it at 2400 K — a nixie's cathode is
nowhere near a tungsten filament, and the white in photographs of one is the camera, not the metal;
the gas around the wire is what carries the orange.

**The wire is hottest in the middle of a run.** A cathode is held at both ends by the stack's rods,
and heat conducts out through them, so the shader carries the two ends of every numeral's wire
(`digitEnds`) and lets the temperature fall by `HEAT_END_DROP` = 550 K over the last `HEAT_FALLOFF` =
0.30 of a numeral unit (about 4.4 mm) at either end. The colour is Planck's at the local temperature,
the power Stefan-Boltzmann's, the white core fades out as the metal cools, and the gas sheath thins
with it — a cooler stretch of cathode carries a dimmer glow. The ends are the tips the numerals are
drawn from, and a closed loop carries its seam twice; the distance to the nearer end is the stand-in
for the position along the run — exact along a straight stroke, an overestimate around a bend.

**The tube breathes.** A discharge is never perfectly still: the gas wanders, the wire hums with the
mains, and the eye reads that as a lamp that is on — `breathe` and `hum` in `nixie.frag`, a few per
cent at a fraction of a hertz, driven by `pTime`. `NixieTube.qml` advances its `clock` fifteen times a
second so the shimmer has something to move with; the still login screen the plan asked for is a
deliberate casualty of the owner asking for life, and the cost is one small repaint per tick.

**The wall is not a cylinder.** Two scales of value noise — bubbles in the glass and the ripple the
blower left — are read as their own gradient and added to the wall's normal, a few degrees at most.
That is what breaks the room the wall reflects into glints, ripples the picture it passes, and stops
the two lights the tube catches from being two perfect lines (`vnoise`, `bump`, `broke`).

**The wire is hot in the middle of its own section, too.** The discharge is drawn on the metal, and
the metal's axis is hotter than its surface, so the radiance ramps across the wire's radius
(`core * (0.55 + 0.80 * core)`): a white-hot core inside an orange body, with the gas sheath around
both. That gradient is what keeps a stroke from reading as a rod of neon — a flat profile, however
thin, is a tube of light, not a filament.

**The glass is a lens, not a window.** A cylinder has power across its axis and none along it, so the
picture inside is magnified sideways — most of all on the axis (up to 0.30) and not at all at the
wall, where the glass is edge-on. The glass also disperses: three indices (1.5155, 1.5200, 1.5280 for
red, green and blue), three rays, three taps of the picture, one channel from each. The far wall does
catch the wire, but it is a wall and not a mirror: the image is squeezed, dimmed and defocused, and a
crisp flipped copy of the numeral inside the tube would read as a second, broken digit. That second
image is traced, not painted: the eye's own ray, reflecting off the cylinder, is intersected with the
cathode's plane (`wallRefl`), so the reflection sits where the glass puts it and the curvature of the
wall does the softening.

## What the theme can turn

`files/quickshell/Theme/greeter.jsonc` (mirrored in `GreeterTheme.qml`):

| token | what it does |
| --- | --- |
| `nixieDigitSize` | the numeral in px before `uiScale`; the tubes, the gaps and the colon are built from it |
| `nixieGlow` | how hard the discharge burns |
| `nixieTempK`, `nixieGlowColor` | the cathode's temperature in kelvin and the gas around it: Planck gives the metal's colour, Stefan-Boltzmann its power |
| `nixieGlassColor`, `nixieCathodeColor` | the envelope's tint and the unlit wire behind the lit one |
| `nixieWire` | the cathode's radius as a share of the numeral's height (0.0360 of 25 mm = 0.90 mm, so the wire is 1.80 mm across, and every bend is that radius) |
| `nixieStack` | how visible the nine unlit cathodes behind the lit one are |
| `nixieHighlight` | how much light the glass catches |
| `nixieWarmth` | how much of the discharge's light lands on the glass (0.45 is the tube's own look) |
| `nixieFlickerMs` | restrike time on a digit change; 0 leaves the restrike out, the idle shimmer below stays |

The theme is copy-once: `Theme/` is copied into `~/.config/quickshell/Theme/`, so after an edit it has
to be copied and touched again, or the login screen keeps the old numbers.

## What is still simulation, not physics

The parts above are measured or modelled. These seven are still drawn to look right, and each one is a
place where the render is a look-alike rather than the thing:

1. Rough metal is five taps in a cross (`metal_hit`, `blurred_room`), a stencil blur. It needs a
   microfacet model (GGX) or a pre-filtered mip chain, so `rough` is a BRDF lobe and not a sample
   radius.
2. The glass traces one path in and out (`rayTr`/`rayTg`/`rayTb`, `rayOut`), and the far wall's catch
   is traced off the cylinder — but the returning ray carries one tuned weight, not Fresnel at the
   wall it reflects from and absorption along the way back out. It needs the same optics twice.
3. Beer's law has no dispersion of its own: `absorb` takes the glass tint as a per-channel
   coefficient and the green ray's path length for all three channels. It needs the attenuation
   carried per wavelength along each of the three dispersed rays.
4. The gas is one colour per token (`pHalo`) plus a fixed violet fringe. A neon discharge is a line
   spectrum; it needs a small set of emission lines weighted by the gas model.
5. Nothing ages over time. The getter mirror and the sputter film are drawn at fixed weights, not
   grown by a usage term, and the cathode is never thinned by the metal it throws off. It needs the
   tube's hours of life to drive both.
6. The base is drawn but switched off: `COLLAR_H_MM = 0` keeps the crimped collar, its twelve pins on
   the sheet's 11.5 mm circle and the two gold terminals out of the picture, because the bulb is
   drawn as the whole lamp. Switching the base on would show the lamp plugged in.
7. The wire's excess above white is carried past 1.0 (`headroom`), but the shader declares no output
   transfer function or primaries, so what the surface does with that excess is the surface's
   decision: the session's 10-bit output path (`bitdepth = 10`, `cm = "auto"` in
   `files/gui/hypr/greetd.lua`; `hdr_output_metadata` needs atomic KMS per
   `modules/user/session/greetd/session-wrapper.sh`) is where it has to be told.

## The workbench

`packages/nixie` draws the same shader off-screen with Vulkan — no Quickshell, no monitor, no
compositor — and measures what it drew:

```
nixie validate                       # the geometry against the sheet
nixie render out.png --digit 6       # one tube, off-screen
nixie sweep out.png --check          # all ten numerals, measured, as one sheet
```

`validate` exits non-zero when the drawing stops agreeing with the sheet. `sweep` measures the wire's
white core, the halo's fall-off, the glass's own light and the mesh's contrast and prints them per
digit; `--check` fails when a measurement is outside the limits in `src/measure.rs`.

The sweep measures the picture as the screen shows it: every frame is composited over the wallpaper
the way the compositor lays it down, the halo is measured against the room the tube burns in, and
the glass's own light is sampled where the numeral is *not* — the lit wire is the lamp's source, not
its glass, and a median that took its glow in would judge the discharge instead of the wall.

Three known gaps, all honest:

- the render is not reproducible from run to run — two identical invocations differ by ~9/255 on
  average over the frame, so the sweep's own numbers carry that noise;
- the wire is drawn fatter than a real cathode (1.80 mm across against the sheet's 0.24 mm) on
  purpose: a hairline disappears on a login screen, and what the eye reads is the glowing filament.
  `validate`'s limit is 2.0 mm for that reason, and the plan's A2 widths (white ≤ 8 px, hot ≤ 16 px)
  were written for a hairline — the accepted lamp is wider than those numbers, so `sweep --check`
  reports the wire as thick;
- the sweep draws the room at full brightness (`room = 1.0`), while the login screen samples the
  wallpaper through its own dimming — a glass-light number is therefore taken on a brighter room
  than the one the login shows.
