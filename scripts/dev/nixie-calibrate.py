#!/usr/bin/env python3
"""Measure the black body the shader draws the wire with, and print the
coefficients it carries.

The wire is metal at a temperature, so its colour is the Planck spectrum's and
its brightness is how much of that spectrum lands where the eye can see. Both
were approximations in nixie.frag (a code-value fit of the Planckian locus and
Stefan-Boltzmann's fourth power, which is the *bolometric* power). This script
replaces the guesses with measurements: it path-traces a black body emitter in
Mitsuba's spectral variant — one flat rectangle per temperature, so the render
is the spectrum itself and nothing else — reads the result as D65-normalised
linear sRGB, and fits what the shader needs.

    UV_CACHE_DIR=/etc/nixos/.uv-cache \
    DRJIT_LIBLLVM_PATH=$(ls /nix/store/*-llvm-*-lib/lib/libLLVM.so.* | head -1) \
    uv run --with mitsuba --with numpy python scripts/dev/nixie-calibrate.py

Two results, both used by `blackbody()` and `heat_power()` in nixie.frag:

* G/R and B/R against 1000/T — the colour of the metal, red fixed at one. At
  2400 K the physics says (1, 0.406, 0.086); the old fit read (1, 0.33, 0.05),
  half the blue, a visibly redder wire.
* the visible radiance against 2550 K (the temperature the tube is drawn at).
  Its local exponent is 11 near 2000 K and 9 near 3000 K, not 4: a camera sees
  the visible band, and as the Planck peak walks into it that band's share
  grows fast. This is why HEAT_END_DROP is 150 K and not the 550 K that the
  fourth power allowed.

The caps (kelvin 1000..20000 in the fit, 1600..3600 in the radiance fit) and
the printed errors are part of the output: paste them along with the numbers.
"""

import numpy as np
import mitsuba as mi

mi.set_variant("llvm_ad_spectral")

# The fit's own range, and the step the render is sampled at: 100 K is finer
# than the fit needs but cheap, and it makes the printed table readable.
T_MIN, T_MAX, T_STEP = 1600.0, 5200.0, 100.0
# The temperature the tube's drawing is exposed against (the wire's own).
REFERENCE = 2550.0


def blackbody_rgb(kelvin: float) -> np.ndarray:
    """D65-normalised linear sRGB of a black body at this temperature."""
    scene = mi.load_dict(
        {
            "type": "scene",
            "integrator": {"type": "path", "max_depth": 2},
            "sensor": {
                "type": "orthographic",
                "to_world": mi.ScalarTransform4f.look_at(
                    origin=[0, 0, 1], target=[0, 0, 0], up=[0, 1, 0]
                ),
                "film": {
                    "type": "hdrfilm",
                    "width": 4,
                    "height": 4,
                    "rfilter": {"type": "box"},
                    "pixel_format": "rgb",
                    "component_format": "float32",
                },
            },
            "shape": {
                "type": "rectangle",
                "to_world": mi.ScalarTransform4f.scale(4.0),
                "emitter": {
                    "type": "area",
                    "radiance": {"type": "blackbody", "temperature": kelvin},
                },
            },
        }
    )
    frame = np.array(mi.Bitmap(mi.render(scene, spp=1)))
    return frame.reshape(-1, 3).mean(axis=0)


def main() -> int:
    temperatures = np.arange(T_MIN, T_MAX + 0.5, T_STEP)
    rgb = np.array([blackbody_rgb(float(t)) for t in temperatures])
    x = 1000.0 / temperatures
    green = rgb[:, 1] / rgb[:, 0]
    blue = rgb[:, 2] / rgb[:, 0]
    light = rgb[:, 0] / np.interp(REFERENCE, temperatures, rgb[:, 0])
    u = np.log(temperatures / REFERENCE)

    # Quartics: the colour is smooth in 1000/T, the radiance is smooth in
    # ln(T/2550), and both are printed so the shader can carry them as written.
    colour_g = np.polyfit(x, green, 4)
    colour_b = np.polyfit(x, blue, 4)
    power = np.polyfit(u, np.log(light), 4)
    print("G/R quartic in x = 1000/T, x^4..x^0:")
    print("   " + " ".join("%.6f" % c for c in colour_g))
    print("B/R quartic in x = 1000/T, x^4..x^0:")
    print("   " + " ".join("%.6f" % c for c in colour_b))
    print("ln(L/L2550) quartic in u = ln(T/2550), u^4..u^0:")
    print("   " + " ".join("%.6f" % c for c in power))
    print(
        "max error: G/R %.4f  B/R %.4f  L %.2f%% of the reference"
        % (
            np.abs(np.polyval(colour_g, x) - green).max(),
            np.abs(np.polyval(colour_b, x) - blue).max(),
            np.abs(np.exp(np.polyval(power, u)) - light).max()
            / light.max()
            * 100.0,
        )
    )
    print("\n   T      G/R    B/R    L/L2550   (measured / fitted)")
    for t in (1850.0, 2100.0, 2250.0, 2400.0, 2550.0, 2800.0, 3200.0):
        i = int(np.argmin(np.abs(temperatures - t)))
        xx, uu = 1000.0 / t, np.log(t / REFERENCE)
        print(
            "%6.0f   %.3f/%.3f  %.3f/%.3f   %.4f/%.4f"
            % (
                t,
                green[i],
                np.polyval(colour_g, xx),
                blue[i],
                np.polyval(colour_b, xx),
                light[i],
                np.exp(np.polyval(power, uu)),
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
