"""Tone-map the path-traced beauty into the sprite: the colour comes from the
render, the alpha from the geometry (the sprite is an overlay, so its interior has
to stay transparent enough for the discharge behind it to read)."""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

W, HH = 1120, 2304
MM_W, MM_H = 29.15, 60.0
R, H, WALL = 9.25, 49.34, 1.1
RT, RW = 6.6, 0.30
BASE, RB = 10.6, 9.7
DIG_H, DIG_W = 21.0, 11.5
STACK_Z = np.linspace(-1.1, 1.1, 10)


def aces(x):
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    return np.clip((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0)


def digit_sdf(d, P):
    def seg(a, b):
        ba = b - a
        h = np.clip(((P - a) @ ba) / (ba @ ba), 0, 1)
        return np.linalg.norm(P - a - h[..., None] * ba, axis=-1)

    def arc(c, r, a0, a1):
        q = P - c
        rel = np.mod(
            np.arctan2(q[..., 1], q[..., 0]) - a0 + 18.8495559215,
            6.28318530718,
        )
        on = np.abs(np.linalg.norm(q, axis=-1) - r)
        e0 = c + r * np.array([np.cos(a0), np.sin(a0)])
        e1 = c + r * np.array([np.cos(a1), np.sin(a1)])
        off = np.minimum(
            np.linalg.norm(P - e0, axis=-1), np.linalg.norm(P - e1, axis=-1)
        )
        return np.where(rel <= (a1 - a0), on, off)

    def ell(c, rx, ry):
        q = (P - c) / np.array([rx, ry])
        return np.abs((np.linalg.norm(q, axis=-1) - 1.0) * min(rx, ry))

    if d == 0:
        return ell(np.zeros(2), 0.30, 0.88)
    if d == 1:
        return seg(np.array([0.0, -1.02]), np.array([0.0, 1.02]))
    if d == 2:
        return np.minimum(
            np.minimum(
                arc(np.array([0.0, 0.60]), 0.31, 0.0, math.pi),
                seg(np.array([0.31, 0.60]), np.array([-0.32, -1.00])),
            ),
            seg(np.array([-0.35, -1.02]), np.array([0.35, -1.02])),
        )
    if d == 3:
        return np.minimum(
            arc(np.array([0.0, 0.52]), 0.52, -1.05, 2.53),
            arc(np.array([0.0, -0.52]), 0.52, -2.09, 1.05),
        )
    if d == 4:
        return np.minimum(
            np.minimum(
                seg(np.array([0.26, 0.95]), np.array([-0.31, -0.10])),
                seg(np.array([-0.31, -0.10]), np.array([0.32, -0.10])),
            ),
            seg(np.array([0.26, 0.95]), np.array([0.26, -1.02])),
        )
    if d == 5:
        return np.minimum(
            np.minimum(
                seg(np.array([-0.30, 1.02]), np.array([0.30, 1.02])),
                seg(np.array([-0.30, 1.02]), np.array([-0.27, 0.01])),
            ),
            arc(np.array([0.0, -0.30]), 0.41, -1.25, 2.28),
        )
    if d == 6:
        return np.minimum(
            np.minimum(
                arc(np.array([0.0, 0.50]), 0.30, 0.0, math.pi),
                seg(np.array([-0.30, 0.50]), np.array([-0.30, -0.52])),
            ),
            ell(np.array([0.0, -0.52]), 0.30, 0.44),
        )
    if d == 7:
        return np.minimum(
            seg(np.array([-0.32, 1.02]), np.array([0.32, 1.02])),
            seg(np.array([0.28, 1.02]), np.array([-0.09, -1.02])),
        )
    if d == 8:
        return np.minimum(
            ell(np.array([0.0, 0.50]), 0.27, 0.50),
            ell(np.array([0.0, -0.50]), 0.30, 0.50),
        )
    return np.minimum(
        ell(np.array([0.0, 0.54]), 0.30, 0.44),
        seg(np.array([0.30, 0.48]), np.array([0.28, -1.02])),
    )


def main(beauty, out, exposure=0.55):
    a = np.load(beauty + ".npy")
    xmm = (np.arange(W) + 0.5) / W * MM_W - MM_W / 2.0
    ymm = -((np.arange(HH) + 0.5) / HH * MM_H - MM_H / 2.0)
    X, Y = np.meshgrid(xmm, ymm)
    xr = np.clip(X / R, -1, 1)
    domec = H / 2.0 - R
    dome = (X**2 + (Y - domec) ** 2) <= R**2
    glass = (
        (np.abs(X) <= R) & (Y <= H / 2.0) & (Y >= -H / 2.0 + BASE * 0.5)
    ) | (dome & (Y > domec))
    # wires and the cage, for the alpha only
    wire = np.zeros_like(X)
    for i, zc in enumerate(STACK_Z):
        dep = i - 4.5
        px = (X - dep * 0.06) / (DIG_W / 2.0)
        py = (Y - 0.8 - dep * 0.05) / (DIG_H / 2.0) * 1.15
        wire = np.maximum(
            wire,
            np.clip(
                1.0
                - (digit_sdf(i, np.stack([px, py], -1)) * (DIG_W / 2.0) - RW)
                / 0.14,
                0,
                1,
            ),
        )
    ang = np.arcsin(xr)
    cage = np.clip(
        1.0
        - (np.abs(np.mod(ang / (math.pi / 12.0) + 0.5, 1.0) - 0.5) * 2 / 0.30)
        ** 2,
        0,
        1,
    )
    cage = np.maximum(
        cage,
        np.clip(
            1.0 - (np.abs(np.mod(Y / 4.0 + 0.5, 1.0) - 0.5) * 2 / 0.35) ** 2,
            0,
            1,
        )
        * 0.6,
    )
    cage *= (
        (np.abs(X) < RT)
        & (Y < H / 2.0 - 1.5)
        & (Y > -H / 2.0 + BASE * 0.5 + 0.8)
    )

    a = np.maximum(a, 0.0)

    # Denoise where a path tracer is noisiest: the dark glass, whose refractions and
    # caustics need far more samples than the metals. A small bilateral keeps the
    # edges of the wires while it smooths the grain — grain is what reads as dirt.
    lum0 = a.mean(axis=2)
    soft = np.clip((0.22 - lum0) / 0.22, 0.0, 1.0)
    if soft.max() > 0.01:
        sig_c, sig_s = 0.060, 2.8
        acc = np.zeros_like(a)
        wsum = np.zeros_like(lum0)
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                sh = np.roll(np.roll(a, dy, axis=0), dx, axis=1)
                lsh = np.roll(np.roll(lum0, dy, axis=0), dx, axis=1)
                w = np.exp(-((lsh - lum0) ** 2) / (2 * sig_c**2)) * math.exp(
                    -(dx * dx + dy * dy) / (2 * sig_s**2)
                )
                acc += sh * w[..., None]
                wsum += w
        a = (
            a * (1 - soft[..., None])
            + (acc / np.maximum(wsum, 1e-6)[..., None]) * soft[..., None]
        )

    rgb = aces(a * exposure)
    rgb = np.where(
        rgb <= 0.0031308,
        rgb * 12.92,
        1.055 * np.power(np.maximum(rgb, 1e-6), 1 / 2.4) - 0.055,
    )
    lum = 0.3 * rgb[..., 0] + 0.6 * rgb[..., 1] + 0.1 * rgb[..., 2]

    # Bloom: a discharge in gas glows far past the wire it burns on, and without
    # that halo the numerals read as printed lines instead of a discharge. The
    # veins are the ones that bleed, and the core keeps its own brightness.
    vein = np.clip((lum - 0.35) / 0.40, 0.0, 1.0) ** 1.6
    core = np.clip((lum - 0.55) / 0.45, 0.0, 1.0)
    vein = vein * (1.0 - 0.60 * core)
    if vein.max() > 0.01:
        halo = (
            np.asarray(
                Image.fromarray((vein * 255).astype("uint8"), "L").filter(
                    ImageFilter.GaussianBlur(2.6)
                ),
                np.float32,
            )
            / 255.0
        )
        tint = np.array([1.00, 0.62, 0.32], np.float32)
        rgb = 1.0 - (1.0 - rgb) * (
            1.0 - np.clip(halo, 0, 1)[..., None] * tint * 0.45
        )

    # The alpha is per material, from two flat coverage passes: the metal (wires,
    # cage, collar) is opaque, the glass is not. Modulating the glass by its own
    # brightness keeps its reflections readable while its body stays clear — a
    # brightness-based alpha alone turned the glass into more metal.
    hw = (
        np.load(beauty + "_hw.npy")
        if os.path.exists(beauty + "_hw.npy")
        else np.zeros_like(lum)
    )
    # The metal: an ordinary overlay, opaque where it is.
    al = np.where(hw > 0.5, 0.97, 0.0).astype(np.float32)
    img = np.clip(rgb, 0, 1)
    Image.fromarray(
        (np.concatenate([img, al[..., None]], -1) * 255).astype("uint8"),
        "RGBA",
    ).save(out)
    # The glass, additive: a reflection adds light, it does not hide the numeral
    # behind it. Treating it as opacity is exactly what made the tube read as metal.
    gp = np.load("/tmp/ms/glass.npy")
    gp = np.maximum(gp, 0.0)
    g = aces(gp * exposure)
    g = np.where(
        g <= 0.0031308,
        g * 12.92,
        1.055 * np.power(np.maximum(g, 1e-6), 1 / 2.4) - 0.055,
    )
    g = np.clip(g, 0, 1)
    Image.fromarray(
        (
            np.concatenate(
                [g, np.clip(g.max(axis=2) * 1.25, 0.0, 1.0)[..., None]], -1
            )
            * 255
        ).astype("uint8"),
        "RGBA",
    ).save(out.replace("nixie-tube", "nixie-glass"))
    print(
        "saved",
        out.replace("nixie-tube", "nixie-glass"),
        "| стекло: max %.2f mean %.3f" % (g.max(), g.mean()),
    )
    print(
        "saved",
        out,
        "| alpha max %.2f mean %.3f | яркость max %.2f mean %.3f | шум в стекле %.3f"
        % (
            al.max(),
            al.mean(),
            lum.max(),
            lum.mean(),
            (
                float(lum[glass & (lum < 0.2)].std())
                if (glass & (lum < 0.2)).any()
                else 0.0
            ),
        ),
    )


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
