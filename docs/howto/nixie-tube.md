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
| 6 | the drawing font's: one straight stroke off the top into a closed bowl, `sdBentRect` with r = 0.20 |
| 7 | a lid and a leg |
| 8 | the drawing font's: two closed loops, the lower wider than the upper, `sdBentRect` with r = 0.24 |
| 9 | a bowl and a leg |

The 5, the 6 and the 8 were measured off a drawing-font reference (GOST 2.304, the drawing font): the
reference raster was read into the numeral's own space and its ink profiled by height, which is where
the proportions and the bend radius come from. A bend there turns over about a tenth of the numeral's
height, i.e. r ≈ 0.20 of the glyph's own units.

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
| `nixieFlickerMs` | restrike time on a digit change; 0 leaves the tubes steady |

The theme is copy-once: `Theme/` is copied into `~/.config/quickshell/Theme/`, so after an edit it has
to be copied and touched again, or the login screen keeps the old numbers.

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
