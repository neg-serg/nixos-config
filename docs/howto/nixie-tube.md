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
scale (px per millimetre) and the numerals are 30 mm high in it.

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

The figures:

| digit | how it is bent |
| --- | --- |
| 0 | one oval |
| 1 | a mast with a flag |
| 2 | a shoulder (an arc), a diagonal and the foot |
| 3 | two ellipse arcs pinched together at the waist |
| 4 | a diagonal over a bar, with a mast |
| 5 | the drawing font's: a bar across the top, the stem off its left end, the waist and a shallow bowl — quadrants of r = 0.20 at every turn |
| 6 | Iosevka's (Iosevkaneg): a closed bowl and a cap over it whose right-hand side stops short, `sdBentRect` with r = 0.24 |
| 7 | a lid and a leg |
| 8 | Iosevka's (Iosevkaneg): two loops, wide at their crowns and pinched at a shared waist, the lower a little wider, `sdRoundQuad` with r = 0.22 |
| 9 | a bowl and a leg |

The 5 was measured off a drawing-font reference (GOST 2.304, the drawing font): the reference raster
was read into the numeral's own space and its ink profiled by height, which is where the proportions
and the bend radius come from. A bend there turns over about a tenth of the numeral's height, i.e.
r ≈ 0.20 of the glyph's own units.

The 6 and the 8 are not the drawing font's: they were measured off the user's own cut of Iosevka
(Iosevkaneg-Regular). The glyph raster gives the aspect, ~0.51, and a stroke about 11% of the height;
the profile gives the two shapes. The 6 is a closed bowl with a cap over it whose right-hand side
stops short — that gap is what makes it a 6 and not an 8 — and every bend is a quadrant of r = 0.24.
The 8 is two loops, wide at their crowns and pinched at a shared waist, the lower a little wider than
the upper, with r = 0.22.

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

**The glass is a lens, not a window.** A cylinder has power across its axis and none along it, so the
picture inside is magnified sideways — most of all on the axis (up to 0.30) and not at all at the
wall, where the glass is edge-on. The glass also disperses: three indices (1.5155, 1.5200, 1.5280 for
red, green and blue), three rays, three taps of the picture, one channel from each. The far wall does
catch the wire, but it is a wall and not a mirror: the image is squeezed, dimmed and defocused, and a
crisp flipped copy of the numeral inside the tube would read as a second, broken digit.

## What the theme can turn

`files/quickshell/Theme/greeter.jsonc` (mirrored in `GreeterTheme.qml`):

| token | what it does |
| --- | --- |
| `nixieDigitSize` | the numeral in px before `uiScale`; the tubes, the gaps and the colon are built from it |
| `nixieGlow` | how hard the discharge burns |
| `nixieCoreColor`, `nixieGlowColor` | the lit cathode and the gas around it |
| `nixieGlassColor`, `nixieCathodeColor` | the envelope's tint and the unlit wire behind the lit one |
| `nixieWire` | the cathode's radius as a share of the numeral's height (0.0127 of 30 mm = 0.38 mm) |
| `nixieStack` | how visible the nine unlit cathodes behind the lit one are |
| `nixieHighlight` | how much light the glass catches |
| `nixieWarmth` | declared and passed to the shader, **not used yet** — the discharge's landing on the glass is drawn at a fixed weight |
| — | the wire's own colour is still the theme's `nixieCoreColor`, not a temperature; the mesh is the first part that emits by Planck's law |
| `nixieFlickerMs` | restrike time on a digit change; 0 leaves the tubes steady |

The theme is copy-once: `Theme/` is copied into `~/.config/quickshell/Theme/`, so after an edit it has
to be copied and touched again, or the login screen keeps the old numbers.

## What is still simulation, not physics

The parts above are measured or modelled. These ten are still drawn to look right, and each one is a
place where the render is a look-alike rather than the thing:

1. The lit wire's colour is the theme's `nixieCoreColor` (`pCore`), not a temperature: the wire is
   tinted, not heated. It needs a `pTempK` uniform and Planck's law with a Stefan-Boltzmann power,
   as `blackbody`/`heat_power` already drive the mesh.
2. `nixieWarmth` is bound (`pWarmth`, `NixieTube.qml`) and never read in the shader: the discharge's
   landing on the glass is a fixed weight. It needs the glass-deposition term scaled by `pWarmth`.
3. Rough metal is five taps in a cross (`metal_hit`, `blurred_room`), a stencil blur. It needs a
   microfacet model (GGX) or a pre-filtered mip chain, so `rough` is a BRDF lobe and not a sample
   radius.
4. The glass traces one path — in, across the bore, out (`rayTr`/`rayTg`/`rayTb`, `rayOut`) — and the
   far wall's catch (`wallRefl`) is painted, not traced: the discharge is never reflected off the
   inner wall. It needs a second ray inside the bore, with its own Fresnel.
5. Beer's law has no dispersion of its own: `absorb` takes the glass tint as a per-channel
   coefficient and the green ray's path length for all three channels. It needs the attenuation
   carried per wavelength along each of the three dispersed rays.
6. The discharge is one colour per token (`pCore`, `pHalo`) plus a fixed violet fringe. A neon
   discharge is a line spectrum; it needs a small set of emission lines weighted by the gas model.
7. The cathode heats uniformly along its length (`core`, `pGlow`). In life the middle of a stroke runs
   hotter than its ends; it needs the heating, and with it the colour, to fall off along the wire.
8. Nothing ages. There is no cathode sputtering and no getter deposit, the two things that darken a
   real tube's glass over its life. It needs a usage term that thins the wire and films the envelope.
9. The base is a crimped moulding (the `collarH` path, and `COLLAR_H_MM = 0` disables even that). It
   has no pins on the sheet's 11.5 mm circle and no lugs, so the lamp cannot be shown plugged in. It
   needs the sheet's leads added and the base switched on.
10. The shader compresses into 0..1 (`add = 1 - exp(-add * 1.55)`, `fragColor` clamped), so there is
    no HDR headroom, while the session outputs 10-bit with colour management and an HDR path
    (`bitdepth = 10`, `cm = "auto"` in `files/gui/hypr/greetd.lua`; `hdr_output_metadata` needs
    atomic KMS per `modules/user/session/greetd/session-wrapper.sh`). It needs an HDR path that keeps
    the highlights above 1.0 and declares the output transfer and primaries instead of compressing
    them away.

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

Two known gaps, both honest:

- the render is not reproducible from run to run — two identical invocations differ by ~9/255 on
  average over the frame, so the sweep's own numbers carry that noise;
- the wire is drawn fatter than a real cathode (0.76 mm across against the sheet's 0.24 mm) on
  purpose: a hairline disappears on a login screen. `validate`'s limit is 0.8 mm for that reason.
