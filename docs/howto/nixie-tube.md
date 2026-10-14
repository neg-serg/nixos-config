# Nixie clock on the login screen (nixie-tube)

The login screen's clock is four gas-discharge tubes and a colon between them. Nothing about a tube
is a picture: the glass, the picture bent through it, the cathode stack, the anode cage, the crimped
collar and the discharge of the lit numeral are one fragment shader, driven by a handful of
uniforms.

## Files

| file                                              | what it is                                                          |
| ------------------------------------------------- | ------------------------------------------------------------------- |
| `files/quickshell/greeter/shaders/nixie.frag`     | the tube: glass, optics, internals, discharge, collar               |
| `files/quickshell/greeter/shaders/nixie.frag.qsb` | the same shader compiled for Quickshell (qsb, GLSL `100es,120,150`) |
| `files/quickshell/greeter/lock/NixieTube.qml`     | one tube: uniforms, the strike, the wallpaper patch it refracts     |
| `files/quickshell/greeter/lock/NixieClock.qml`    | the row of four tubes and the gaps between them                     |
| `packages/nixie/`                                 | the workbench: the same shader rendered off-screen on the GPU       |

Rebuild the shader after every edit — Quickshell loads the `.qsb`, not the source:

```
QSB=$(ls -d /nix/store/*qtshadertools-6.11.2/bin/qsb | head -1)
"$QSB" --glsl "100es,120,150" -o files/quickshell/greeter/shaders/nixie.frag.qsb \
      files/quickshell/greeter/shaders/nixie.frag
```

## The envelope

Every number in the drawing comes from Reflector's IN-12A/B data sheet (1988): bulb Ø19 × 28 mm,
base Ø21 × 7 mm, pins Ø1 mm on an 11.5 mm circle, the pip Ø3.5 mm, the sheet's numerals 18 mm high,
the whole lamp 35 mm without its pins. The drawing's box is 21 × 35 mm and it is the item that
agrees with the sheet, not a uniform: an item stretched by its parent would put the millimetre
somewhere else. `pMm` is the scale (px per millimetre) — and the drawing uses one numeral scale, 25
mm: the glyphs are drawn 25 mm high (`DIGIT_H` in `nixie.frag`) in a 14 mm-wide box (`DIGIT_W`), so
they sit inside the 28 mm bulb with a margin, and the ink keeps Iosevka's own aspect as the glyph
raster measures it.

`nixie validate` checks that arithmetic: one axis, no gaps, the dome a real hemisphere on the
cylinder, the numerals inside the bore, the collar where the sheet puts it.

## The numerals

A cathode is a piece of wire that was bent, so every numeral is a distance field of its own centre
line in its own square space: x in -0.425..0.425 (its width), y in -1.02..1.02 (its height), both at
the same scale. The wire's radius is a theme token (see below) and the whole numeral is one
connected wire — the workbench checks that by rasterising it.

The primitives, all in `nixie.frag`:

- `sdSegment` — a straight piece of wire;
- `sdArc` — an arc of a circle, by centre, radius and an angular range;
- `sdEllipse` / `sdEllipseArc` — the same for a circle stretched to the numeral's proportions;
- `sdBentRect` — the outline of a rectangle whose four corners are quadrants of a circle of radius
  r: straight sides, bends of one radius, which is how a drawing font bends a wire;
- the 8's own figure — a Gerono lemniscate sampled as 160 chords, because the 8 is one curve whose
  waist crosses itself and not two rings;
- `smin` — a smooth union. It is still used where two strokes of different direction meet without a
  common tangent, but a bend with a known radius is built from quadrants, not from a softened
  corner. At an elbow the softening is the wire's own radius, taken from the `nixieWire` token
  (about 1.10 mm at the heavy-duty default): a wire that was bent has the thickness of the wire it
  was bent from, no more.

The figures:

| digit | how it is bent                                                                                                                                                                                |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | one oval                                                                                                                                                                                      |
| 1     | a mast with a flag                                                                                                                                                                            |
| 2     | a shoulder (an arc), a diagonal and the foot                                                                                                                                                  |
| 3     | two ellipse arcs pinched together at the waist                                                                                                                                                |
| 4     | a diagonal over a bar, with a mast                                                                                                                                                            |
| 5     | Iosevka's (Iosevkaneg): the bar with a short stub at its right end, the stem leaning left, and a bowl half a unit wide whose corners are quarters of a 0.25 circle                            |
| 6     | Iosevka's (Iosevkaneg): a closed bowl and a cap over it whose right-hand side stops short, `sdBentRect` with r = 0.24                                                                         |
| 7     | a lid and a leg                                                                                                                                                                               |
| 8     | Iosevka's (Iosevkaneg): one curve, a Gerono lemniscate sampled as 160 chords, wide at the crowns and pinched at a shared waist; the strand that passes over the waist is flagged (`wirePass`) |
| 9     | a bowl and a leg                                                                                                                                                                              |

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

| part                                  | material                 | F0 (550 nm)      |
| ------------------------------------- | ------------------------ | ---------------- |
| anode mesh                            | rhodium (n 2.06, k 5.31) | 0.79, 0.79, 0.80 |
| collector ring at the top of the cage | gold (n 0.47, k 2.40)    | 1.00, 0.77, 0.34 |
| sleeve the stack is welded into       | rhodium                  | 0.79, 0.79, 0.80 |
| rods and the unlit stack              | nickel (n 1.90, k 3.90)  | 0.56, 0.55, 0.52 |
| crimped collar                        | steel, matte             | 0.29, 0.30, 0.33 |

Rhodium goes on the mesh and the sleeve: it does not tarnish, it survives the gas, and it keeps its
own colour neutral, so the only colour on it is the discharge. Gold goes where the eye looks for it.
The mesh's reflection is smeared by its own roughness (five taps in a cross, the radius from
`rough`), so the collar's polish and the wire do not reflect the room with the same sharpness.

**The mesh is hot.** A wire in a discharge is not a mirror, it is a heater: the fit below takes it
from the room's 320 K to about 1100 K where the arc touches it, which is where its own emission
takes over from the room's reflection. `blackbody()` is Planck's colour (Bartlett's sRGB fit) and
`heat_power()` is Stefan-Boltzmann's fourth power against the temperature the tube is drawn at (2550
K), capped so a knob turned all the way up cannot blow the frame out. Measured on the render: with
the discharge on, the mesh's own region gains light with R/B ≈ 5 — dull red, as it should be.

**The discharge is exposed and tone-mapped, not clipped.** The wire and its gas are summed as light
— the wire's colour from the measured Planck fit below, the gas's linearised from the theme's own
colour — and mapped once through Khronos' PBR-neutral curve (`tone_map`, the theme's
`nixieExposure`): the wire stands a stop and a half above white, the curve's shoulder turns that
into a white core, and the metal's own colour survives under it. The result is encoded back into the
display values the rest of the pass and the compositor work in. Nothing is clipped, and nothing is
added after the curve: what the old code called "HDR headroom" was a fixed fraction of the wire's
excess added on top of the display value, which an 8-bit sRGB surface simply throws away.

**Where the wire's colour and its brightness come from.** Both are measured, not fitted by eye, by a
spectral path trace of the Planck spectrum itself (`scripts/dev/nixie-calibrate.py`, Mitsuba's
`blackbody` emitter, one flat rectangle per temperature, read back as D65-normalised linear sRGB):

|                                            | physics           | the shader                                               |
| ------------------------------------------ | ----------------- | -------------------------------------------------------- |
| colour at 2400 K                           | (1, 0.406, 0.086) | quartic in 1000/T over 1600..5200 K, error 0.001 / 0.003 |
| colour at 3200 K                           | (1, 0.570, 0.285) | same fit                                                 |
| visible radiance at 1850 K, against 2550 K | 0.023             | quartic in ln(T/2550), error 0.1%                        |
| visible radiance at 2400 K                 | 0.560             | same fit                                                 |
| visible radiance at 3200 K                 | 6.22              | same fit                                                 |

The radiance column is the one that changed a look. Stefan-Boltzmann's fourth power is the
*bolometric* power; a camera sees the visible band, and as the Planck peak walks into it that band's
share grows fast — the local exponent is 11 near 2000 K and 9 near 3000 K. `HEAT_END_DROP` is 150 K
for that reason: the 550 K this used to lose at the ends would have put them out thirty times over.

**The metal's own colour is dull orange.** The theme draws it at 2100 K by default — the vintage
lamp, a deep orange close to the glow of a cathode in an old photograph. 2400 K, the temperature the
calibration was taken at, is one token away and reads as a modern amber wire; the two looks are the
same physics with `nixieTempK` and `nixieExposure` moved together (2100/2.5 and 2400/1.5). A nixie's
cathode is nowhere near a tungsten filament, and the white in photographs of one is the camera, not
the metal; the gas around the wire is what carries the orange.

**The wire is hottest in the middle of a run.** A cathode is held at both ends by the stack's rods,
and heat conducts out through them, so the shader carries the two ends of every numeral's wire
(`digitEnds`) and lets the temperature fall by `HEAT_END_DROP` = 150 K over the last `HEAT_FALLOFF`
= 0.30 of a numeral unit (about 4.4 mm) at either end. The colour is Planck's at the local
temperature, the power Stefan-Boltzmann's, the white core fades out as the metal cools, and the gas
sheath thins with it — a cooler stretch of cathode carries a dimmer glow. The ends are the tips the
numerals are drawn from, and a closed loop carries its seam twice; the distance to the nearer end is
the stand-in for the position along the run — exact along a straight stroke, an overestimate around
a bend.

**The tube breathes.** A discharge is never perfectly still: the gas wanders, the wire hums with the
mains, and the eye reads that as a lamp that is on — `breathe` and `hum` in `nixie.frag`, a few per
cent at a fraction of a hertz, driven by `pTime` and scaled by the `nixieShimmer` token.
`NixieClock.qml` and `NixieTube.qml` advance their time only on the shimmer tick — `nixieShimmerMs`
(66 ms by default) — and stop the timer entirely when `nixieShimmer` is 0 or the item is not
visible; the still login screen the plan asked for is a deliberate casualty of the owner asking for
life, and the price is one small repaint per tick and nothing at all when it is off.

**The wall is not a cylinder.** Two scales of value noise — bubbles in the glass and the ripple the
blower left — are read as their own gradient and added to the wall's normal, a few degrees at most.
That is what breaks the room the wall reflects into glints, ripples the picture it passes, and stops
the two lights the tube catches from being two perfect lines (`vnoise`, `bump`, `broke`).

**The wire's section is flat, its rim is not.** A heated wire is a surface, and a surface at one
temperature has one radiance: the section is flat, not a painted ramp. What makes it read as a
bright filament is the exposure (the metal stands several times above white and the tone curve
whitens it), the optics, which defocus its two edges by about a pixel
(`core = smoothstep(wirePx + 0.5, wirePx - 0.5, axis)`), and the metal's own limb darkening
(`limb = 1 - 0.55 * (1 - cos)^2`), read off the surface's angle to the eye across the wire. The gas
sheath around it is what carries the orange; a drawn radial gradient would read as a rod of neon,
not a filament.

**The glass is a lens, not a window.** A cylinder has power across its axis and none along it, so
the picture inside is magnified sideways — most of all on the axis (up to 0.30) and not at all at
the wall, where the glass is edge-on. The glass also disperses: three indices (1.5155, 1.5200,
1.5280 for red, green and blue), three rays, three taps of the picture, one channel from each. The
far wall does catch the wire, but it is a wall and not a mirror: the image is squeezed, dimmed and
defocused, and a crisp flipped copy of the numeral inside the tube would read as a second, broken
digit. That second image is traced, not painted: the eye's own ray, reflecting off the cylinder, is
intersected with the cathode's plane (`wallRefl`), so the reflection sits where the glass puts it
and the curvature of the wall does the softening.

## What the theme can turn

`files/quickshell/Theme/greeter.jsonc` (mirrored in `GreeterTheme.qml`). "shader clamp" is enforced
by `nixie.frag` itself; colour tokens are `#AARRGGBB` when the alpha is a strength (tint, glass) and
`#RRGGBB` when they are opaque (glow, cathode).

| token                | default     | range                                               | what it does                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| -------------------- | ----------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nixieDigitSize`     | 92          | > 0 px                                              | the numeral in px before `uiScale`; the tubes, the gaps and the colon are built from it                                                                                                                                                                                                                                                                                                                                                      |
| `nixieTubeMargin`    | 16          | >= 0 px                                             | the room a tube's item keeps around its glass for the bloom. The clock's row is spaced negative by two of these, so the glass edges can sit a few pixels apart while every tube still has its own margin to glow into. It is also the border the discharge's light no longer stops dead at: the light on the wallpaper fades over the last two margins instead of drawing a rectangle around the tube                                        |
| `nixieGlow`          | 1.0         | >= 0                                                | how hard the discharge burns (0 is a tube that is on but shows nothing)                                                                                                                                                                                                                                                                                                                                                                      |
| `nixieTempK`         | 2100        | 1600..3200 (shader fit 1600..5200)                  | the cathode's temperature in kelvin: the metal's colour and its power are measured off the Planck spectrum (see the calibration below)                                                                                                                                                                                                                                                                                                       |
| `nixieGlowColor`     | `#ff5a10`   | `#RRGGBB`                                           | the gas around the wire                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `nixieExposure`      | 2.5         | 0.5..4.0                                            | how many times brighter than white the wire is exposed at — what turns its colour into a white core through the tone curve. 2100 K at 2.5 is the vintage lamp, 2400 K at 1.5 is the calibrated modern one                                                                                                                                                                                                                                    |
| `nixieTint`          | `#00000000` | `#AARRGGBB` (alpha = strength)                      | coloured glass: the hue the tube's own light takes, with the alpha as how much of it (`#cc66e0ff` is a cyan lamp, `#00000000` is off). Peak for peak, so the exposure means the same thing at any hue                                                                                                                                                                                                                                        |
| `nixieTintWallpaper` | 0.0         | 0..1                                                | 0 is off; above that the tube's light takes the wallpaper's own colour instead of `nixieTint`'s, and this is how much of it. The colour is read from a fixed grid over the patch behind the lamp — one reading for the whole clock, so all four tubes agree — and a grey wallpaper leaves the metal its own                                                                                                                                  |
| `nixieViewAngle`     | 16.0        | -30..30 (shader clamp)                              | the camera's yaw off the tube's axis, in degrees. The numerals inside the glass shift towards the viewer's side and narrow by the cosine while the envelope keeps its silhouette — a cylinder is as wide at an angle as head-on, and that difference is the depth. 16 costs the numerals 4% of their width; 0 is dead ahead                                                                                                                  |
| `nixieViewDistance`  | 8.0         | 0 = shader default                                  | how far the camera stands from the clock, in tube widths (21 mm). A solid of revolution looks the same from any azimuth, so a yaw alone can only move what is inside the glass; at a finite distance the two ends of the row are also drawn at different sizes — the near one larger, about a tenth between the two glasses at 8 — and that is what reads as a row seen from the side. Larger is flatter, the perspective goes as 1/distance |
| `nixieViewPitch`     | 0.0         | -20..20                                             | the camera's pitch above the clock's axis, in degrees (0 is level); the third member of the `pView` uniform carries it, and the shader consumes it from P6 on                                                                                                                                                                                                                                                                                |
| `nixieCameraFollow`  | true        | bool                                                | the pointer pulls the camera off its base yaw and pitch by at most `nixieCameraRange` degrees, smoothed by a Behavior; false keeps the base camera exactly                                                                                                                                                                                                                                                                                   |
| `nixieCameraRange`   | 6.0         | 0..15                                               | how far, in degrees, pointer following may pull the camera from its base                                                                                                                                                                                                                                                                                                                                                                     |
| `nixieGlassColor`    | `#4d120b06` | `#AARRGGBB` (alpha = strength)                      | the envelope's tint                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `nixieCathodeColor`  | `#aab6c4`   | `#RRGGBB`                                           | the unlit wire behind the lit one                                                                                                                                                                                                                                                                                                                                                                                                            |
| `nixieWire`          | 0.0440      | 0.02..0.08                                          | the cathode's radius as a share of the numeral's height (0.0440 of 25 mm = 1.10 mm, so the wire is 2.20 mm across, and every bend is that radius)                                                                                                                                                                                                                                                                                            |
| `nixieStack`         | 0.5         | >= 0                                                | how visible the nine unlit cathodes behind the lit one are                                                                                                                                                                                                                                                                                                                                                                                   |
| `nixieHighlight`     | 0.8         | >= 0                                                | how much light the glass catches                                                                                                                                                                                                                                                                                                                                                                                                             |
| `nixieWarmth`        | 0.45        | 0..1.35 (shader clamps at 3 × the 0.45 calibration) | how much of the discharge's light lands on the glass (0.45 is the tube's own look)                                                                                                                                                                                                                                                                                                                                                           |
| `nixieFlickerMs`     | 320         | >= 0 (0 = no restrike)                              | restrike time on a digit change; 0 leaves the restrike out, the idle shimmer stays                                                                                                                                                                                                                                                                                                                                                           |
| `nixieFlicker`       | true        | bool                                                | restrike on a digit change; false holds every tube at ignition 1 and starts no timers                                                                                                                                                                                                                                                                                                                                                        |
| `nixieShimmer`       | 1.0         | 0..1                                                | multiplier on the shader's breathe/hum; 0 means no shimmer and no periodic repaint at all                                                                                                                                                                                                                                                                                                                                                    |
| `nixieShimmerMs`     | 66          | 33..250                                             | the shimmer tick cadence in ms (66 is the old 15 Hz)                                                                                                                                                                                                                                                                                                                                                                                         |
| `nixieJitter`        | 1.0         | 0..1.5                                              | per-tube strike offsets and lengths; 0 makes all four tubes strike in lockstep                                                                                                                                                                                                                                                                                                                                                               |
| `nixieQuality`       | `"full"`    | `full` \| `balanced` \| `lite`                      | shader quality tier (uniform `pQuality` = 0/1/2); "full" is today's picture                                                                                                                                                                                                                                                                                                                                                                  |
| `nixie24h`           | true        | bool                                                | 24 h format for the clock; false draws 12 h (12 at midnight and noon)                                                                                                                                                                                                                                                                                                                                                                        |
| `nixieLeadingZero`   | false       | bool                                                | true lights the tens of the hours as 0 instead of leaving that tube dark                                                                                                                                                                                                                                                                                                                                                                     |
| `nixieSpacing`       | 1.0         | >= 0                                                | multiplier on the row's gaps (0.055 of the numeral between tubes, 0.20 between the two pairs)                                                                                                                                                                                                                                                                                                                                                |
| `nixieAge`           | 1.0         | >= 0                                                | multiplier on the getter mirror and the sputter film weights; 1.0 keeps today's look                                                                                                                                                                                                                                                                                                                                                         |
| `nixieBase`          | false       | bool                                                | the base (collar, pins, terminals); false is `COLLAR_H_MM = 0`, the bulb drawn as the whole lamp                                                                                                                                                                                                                                                                                                                                             |
| `nixieColon`         | false       | bool                                                | a fifth, bulb-mode tube in the row pass; false is the open gap of today's clock                                                                                                                                                                                                                                                                                                                                                              |

`GreeterTheme.qml` also carries a process-local override layer for the settings menu: `overrides`,
`setOverride(path, value)`, `clearOverrides()`, `isOverridden(path)` and
`effective(path, fallback)`, with every token resolved override → theme file → hardcoded fallback.
Overrides never touch a file; the menu's Save is the only disk path.

The theme is copy-once: `Theme/` is copied into `~/.config/quickshell/Theme/`, so after an edit it
has to be copied and touched again, or the login screen keeps the old numbers.

## The clock is one object, not four

Four tubes are drawn in one pass over one item (`NixieClock.qml` hands the shader the row: `pTile.w`
= 1, the four centres in `pRowX`, their digits in `pRowDigit` and their ignitions in `pRowFlicker`;
the shader loops over them and sums what each contributes, because light adds). The item is the
whole row plus one `nixieTubeMargin`, and every tube inside it keeps its own margin for the bloom —
which is why the glasses can sit six pixels apart while each still has room to glow into.

Four items instead put four rectangles of lamp-lit wallpaper around the clock and left a step where
one met the next: a tube's item is finite and its light is not. With one item there is no border
between the tubes to see, and the light pools the way it does around a row of lamps on a desk.

`nixie --row 1750` draws the same row off-screen — it is how that seam was measured, and the
single-tube mode (`pTile.w` = 0, what `nixie render` and the tube lab draw) is the same shader with
one tube in the loop's place.

## What is still simulation, not physics

The parts above are measured or modelled. These are still drawn to look right, and each one is a
place where the render is a look-alike rather than the thing:

1. Rough metal is five taps in a cross (`metal_hit`, `blurred_room`), a stencil blur. It needs a
   microfacet model (GGX) or a pre-filtered mip chain, so `rough` is a BRDF lobe and not a sample
   radius.
1. The glass traces one path in and out (`rayTr`/`rayTg`/`rayTb`, `rayOut`), and the far wall's
   catch is traced off the cylinder — but the returning ray carries one tuned weight, not Fresnel at
   the wall it reflects from and absorption along the way back out. It needs the same optics twice.
1. Only the discharge is linearised and tone-mapped: the glass, the metals and the room behind them
   are still summed in the display's own encoding, and the light the wire throws on the glass is
   taken from the *tone-mapped* value rather than from the light that made it. A full linear
   workflow — sample the room and the theme in linear, sum everything once, tone map once, encode at
   the end — is the next step, and it will move the whole picture, not just the wire.
1. Beer's law has no dispersion of its own: `absorb` takes the glass tint as a per-channel
   coefficient and the green ray's path length for all three channels. It needs the attenuation
   carried per wavelength along each of the three dispersed rays.
1. The gas is one colour per token (`pHalo`) plus a fixed violet fringe. A neon discharge is a line
   spectrum; it needs a small set of emission lines weighted by the gas model.
1. Nothing ages over time. The getter mirror and the sputter film are drawn at fixed weights, not
   grown by a usage term, and the cathode is never thinned by the metal it throws off. It needs the
   tube's hours of life to drive both.
1. The base is drawn but switched off: `COLLAR_H_MM = 0` keeps the crimped collar, its twelve pins
   on the sheet's 11.5 mm circle and the two gold terminals out of the picture, because the bulb is
   drawn as the whole lamp. Switching the base on would show the lamp plugged in.
1. The shader tone-maps the discharge into display-encoded sRGB values and declares no output
   transfer function or primaries, so the session's 10-bit output path (`bitdepth = 10`,
   `cm = "auto"` in `files/gui/hypr/greetd.lua`; `hdr_output_metadata` needs atomic KMS per
   `modules/user/session/greetd/session-wrapper.sh`) is where any wider-gamut output has to be told;
   nothing is carried above 1.0 today.

## The workbench

`packages/nixie` draws the same shader off-screen with Vulkan — no Quickshell, no monitor, no
compositor — and measures what it drew:

```
nixie validate                       # the geometry against the sheet
nixie render out.png --digit 6       # one tube, off-screen
nixie sweep out.png --check          # all ten numerals, measured, as one sheet
```

`validate` exits non-zero when the drawing stops agreeing with the sheet. `sweep` measures the
wire's white core, the halo's fall-off, the glass's own light and the mesh's contrast and prints
them per digit; `--check` fails when a measurement is outside the limits in `src/measure.rs`.

The sweep measures the picture as the screen shows it: every frame is composited over the wallpaper
the way the compositor lays it down, the halo is measured against the room the tube burns in, and
the glass's own light is sampled where the numeral is *not* — the lit wire is the lamp's source, not
its glass, and a median that took its glow in would judge the discharge instead of the wall.

Three known gaps, all honest:

- the render is not reproducible from run to run — two identical invocations differ by ~9/255 on
  average over the frame, so the sweep's own numbers carry that noise;
- the wire is drawn fatter than a real cathode (2.20 mm across against the sheet's 0.24 mm) on
  purpose: a hairline disappears on a login screen, and what the eye reads is the glowing filament.
  `validate`'s limit is 2.6 mm for that reason, and the plan's A2 widths (white ≤ 8 px, hot ≤ 16 px)
  were written for a hairline — the accepted lamp is wider than those numbers, so `sweep --check`
  reports the wire as thick;
- the sweep draws the room at full brightness (`room = 1.0`), while the login screen samples the
  wallpaper through its own dimming — a glass-light number is therefore taken on a brighter room
  than the one the login shows.
