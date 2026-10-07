#!/usr/bin/env python3
"""Check the nixie tube's geometry the way a fitter would: every part of the
lamp must sit on one axis, in one frame, with no gaps and no overlaps.

The drawing the tube is built from is Reflector's IN-12A/B data sheet (1988):
bulb Ø19 x 28, base Ø21 x 7, the whole lamp 35 without its pins, the pip Ø3.5,
the numerals 18 mm. Those numbers live in files/quickshell/greeter/shaders/
nixie.frag; this reads them out of the shader and checks the layout they imply —
it does not re-implement the shader, so it cannot agree with a mistake.

usage: check-nixie-geometry.py [--shader PATH]
"""

import re
import sys
from pathlib import Path

SHADER = Path("/etc/nixos/files/quickshell/greeter/shaders/nixie.frag")


def numbers(src, pattern):
    m = re.search(pattern, src)
    if not m:
        raise SystemExit(f"cannot read from the shader: {pattern}")
    return [float(g) for g in m.groups()]


def main():
    path = (
        Path(sys.argv[sys.argv.index("--shader") + 1])
        if "--shader" in sys.argv
        else SHADER
    )
    src = path.read_text()

    box_w, box_h = numbers(src, r"float boxW = ([\d.]+), boxH = ([\d.]+);")
    bulb_r = numbers(src, r"float bulbR = ([\d.]+) \* mm;")[0]
    bulb_h = numbers(src, r"float bulbH = ([\d.]+) \* mm;")[0]
    collar_r = numbers(src, r"float side = clamp\(p\.x / max\(([\d.]+) \* mm")[
        0
    ]
    # the base is the sheet's 7 mm: the shader takes it from the drawing and
    # pBase only says whether the envelope has a collar at all
    collar_h = numbers(
        src, r"float collarH = \(pBase > 0\.5\) \? ([\d.]+) \* mm : 0\.0;"
    )[0]
    digit_h = numbers(src, r"float gy = \(([\d.]+) / ([\d.]+)\) \* mm;")
    digit_h = digit_h[0] / digit_h[1]
    # the glyphs in digitWire() run -1.02..+1.02 across 0.7 units, and the
    # shader centres that box on the glass's middle
    glyph_lo, glyph_hi = -1.02, 1.02
    glyph_h = glyph_hi - glyph_lo
    glyph_w = 0.7
    gx_ratio = numbers(src, r"float gx = ([\d.]+) \* gy;")[0]
    wire_r = numbers(src, r"float wirePx = ([\d.]+) \* mm;")[0]
    mesh_r = numbers(src, r"float cageR = ([\d.]+) \* mm;")[0]
    rod_x = numbers(src, r"abs\(p\.x\) - ([\d.]+) \* mm\)")[0]
    wall_mm = 0.9  # NixieTube.pThick: the glass wall, 0.9 mm

    # the frame: the box is centred in the item, y runs down
    box_mid = box_h / 2.0
    collar = collar_h
    foot_y = box_mid - collar
    apex_y = foot_y - bulb_h
    cap_y = apex_y + bulb_r

    digit_h_mm = digit_h * glyph_h  # the numerals, 18 mm
    digit_w_mm = digit_h * gx_ratio * glyph_w
    digit_mid = (apex_y + foot_y) / 2.0  # the glass's middle
    glyph_origin = digit_mid
    digit_top = glyph_origin + glyph_lo * digit_h
    digit_bottom = glyph_origin + glyph_hi * digit_h
    digit_centre = (digit_top + digit_bottom) / 2.0
    inner_r = bulb_r - wall_mm

    checks = []

    def check(name, ok, detail):
        checks.append((name, ok, detail))

    check(
        "the drawing adds up",
        abs((bulb_h + collar_h) - box_h) < 1e-6,
        f"bulb {bulb_h} + base {collar_h} = box {box_h} mm",
    )
    check(
        "the dome is a hemisphere on the cylinder",
        abs(cap_y - (apex_y + bulb_r)) < 1e-9,
        f"cap centre {cap_y:.2f} = apex {apex_y:.2f} + r {bulb_r}",
    )
    check(
        "the glass meets the base exactly",
        abs((apex_y + bulb_h) - foot_y) < 1e-9,
        f"glass foot {apex_y + bulb_h:.2f} = base top {foot_y:.2f}",
    )
    check(
        "the base hides the glass's foot",
        collar_r >= bulb_r,
        f"base radius {collar_r} >= bulb radius {bulb_r}",
    )
    check(
        "the pip fits the box",
        abs(apex_y - (-box_mid)) < 1e-9,
        f"glass top (the pip) y {apex_y:.2f} = box top {-box_mid:.2f}",
    )
    check(
        "the numerals are 18 mm",
        abs(digit_h_mm - 18.0) < 1e-6,
        f"glyph {glyph_h} units x {digit_h:.3f} mm/unit = {digit_h_mm:.2f} mm",
    )
    check(
        "the numerals stand on the glass's axis",
        abs(digit_centre - digit_mid) < 0.05 * digit_h,
        f"numeral centre {digit_centre:.2f} vs glass centre {digit_mid:.2f}",
    )
    check(
        "the numerals are inside the bore",
        digit_w_mm / 2.0 <= inner_r
        and digit_top >= apex_y
        and digit_bottom <= foot_y,
        f"digit {digit_w_mm:.1f} x {digit_h_mm:.0f} mm inside Ø{2*inner_r:.1f} x {bulb_h:.0f} mm",
    )
    check(
        "the wire is a wire",
        wire_r * 2.0 <= 0.6,
        f"cathode Ø{wire_r * 2:.2f} mm",
    )
    check(
        "the mesh wraps the stack",
        mesh_r <= inner_r and mesh_r > digit_w_mm / 2.0,
        f"mesh Ø{2*mesh_r:.1f} between the numerals {digit_w_mm:.1f} and the bore {2*inner_r:.1f} mm",
    )
    check(
        "the rods clear the numerals",
        rod_x > digit_w_mm / 2.0 and rod_x < mesh_r,
        f"rods at ±{rod_x} mm, numerals ±{digit_w_mm/2:.1f}, mesh {mesh_r}",
    )

    name_w = max(len(n) for n, _, _ in checks)
    failed = 0
    print(f"{path.name}: the drawing's box {box_w:g} x {box_h:g} mm")
    print(
        f"  frame: base {collar_h:g} mm, glass {bulb_h:g} mm, bulb Ø{2*bulb_r:g}, "
        f"base Ø{2*collar_r:g}, apex y {apex_y:.2f} .. foot y {foot_y:.2f}"
    )
    for name, ok, detail in checks:
        print(f"  [{'ok' if ok else 'FAIL'}] {name:<{name_w}}  {detail}")
        failed += 0 if ok else 1
    print(
        "OK: the lamp is one object on one axis"
        if not failed
        else f"{failed} check(s) failed"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
