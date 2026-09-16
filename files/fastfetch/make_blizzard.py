#!/usr/bin/env python3
"""Black-metal blizzard generator (animated WebP) from a reference image.

Different dithering algorithms produce different skull textures - the source
of variability. A wrapper (blizzard.sh) applies presets.

Usage:
  python3 make_blizzard.py --dither fs --out out.webp
  python3 make_blizzard.py --dither bayer --storm 1.3 --wind 1.2 --palette ash
"""

import argparse
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

REF = "/home/neg/pic/necro/8a8c0e082df595deed2ef785f73c3476.jpg"
TW, TH = 640, 806

PALETTES = {
    "ash": [
        [0.0, (6, 7, 9)],
        [0.4, (60, 68, 82)],
        [0.7, (130, 145, 165)],
        [0.9, (205, 216, 230)],
        [1.0, (246, 250, 255)],
    ],
    "ember": [
        [0.0, (8, 4, 5)],
        [0.35, (120, 22, 10)],
        [0.62, (205, 68, 16)],
        [0.85, (244, 130, 42)],
        [1.0, (255, 216, 155)],
    ],
    "ice": [
        [0.0, (6, 10, 16)],
        [0.35, (20, 50, 74)],
        [0.62, (40, 95, 130)],
        [0.85, (80, 160, 200)],
        [1.0, (200, 240, 255)],
    ],
}


def hex_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i : i + 2], 16) for i in (0, 2, 4))


def build_gradient(hexc):
    """Build a 5-stop dark->bright gradient of the given base color."""
    r, g, b = hex_rgb(hexc)
    out = []
    for f in [0.0, 0.35, 0.62, 0.85, 1.0]:
        wt = max(0.0, (f - 0.6)) * 0.55  # mix toward white for the bright end
        c = (
            min(255, int(r * f + 60 * wt)),
            min(255, int(g * f + 60 * wt)),
            min(255, int(b * f + 60 * wt)),
        )
        out.append([f, c])
    return out


def apply_shader(im, shader):
    """Optional post shader: inversion and/or RGB (chromatic) shift."""
    if shader in ("none", ""):
        return im
    arr = np.array(im).astype(int)
    if "invert" in shader:
        arr = 255 - arr
    if "rgb" in shader:
        sh = 14  # stronger chromatic split (visible when scaled down)
        arr[..., 0] = np.roll(arr[..., 0], sh, axis=1)  # R right
        arr[..., 2] = np.roll(arr[..., 2], -sh, axis=1)  # B left
    return Image.fromarray(arr[..., :3].clip(0, 255).astype("uint8"))


def compute_snow_contour(norm, blur=7, thresh=0.18, win=25):
    """Return per-column top contour (y) of the hood/shoulders silhouette."""
    im = Image.fromarray((norm * 255).astype("uint8")).filter(
        ImageFilter.GaussianBlur(blur)
    )
    N = np.array(im).astype(float) / 255.0
    mask = N > thresh
    hh, ww = mask.shape
    yt = []
    for x in range(ww):
        c = np.nonzero(mask[:, x])[0]
        yt.append(int(c[0]) if len(c) else hh)
    k = win // 2
    sm = []
    for x in range(ww):
        lo = max(0, x - k)
        hi = min(ww, x + k + 1)
        sm.append(int(np.mean(yt[lo:hi])))
    return sm


def load_norm(path):
    ref = Image.open(path).convert("L")
    w, h = ref.size
    blur = ref.filter(ImageFilter.GaussianBlur(8))
    ba = np.array(blur).astype(float)
    lo, hi = np.percentile(ba, 2), np.percentile(ba, 98)
    bn = np.clip((ba - lo) / (hi - lo), 0, 1)
    mask = np.zeros_like(bn)
    mask[: int(h * 0.6), :] = 1
    f = (bn > 0.55) * mask
    ys, xs = np.nonzero(f)
    fx, fy = xs.mean() / w, ys.mean() / h
    aspect = TW / TH
    cw = int(0.66 * w)
    ch = int(cw / aspect)
    x0 = int(fx * w - cw / 2)
    y0 = int(fy * h - ch / 2)
    x0 = max(0, min(w - cw, x0))
    y0 = max(0, min(h - ch, y0))
    crop = ref.crop((x0, y0, x0 + cw, y0 + ch))
    a = np.array(crop).astype(float)
    lo, hi = np.percentile(a, 2), np.percentile(a, 98)
    norm = np.clip((a - lo) / (hi - lo), 0, 1) ** 0.7
    img = Image.fromarray((norm * 255).astype("uint8")).resize(
        (TW, TH), Image.LANCZOS
    )
    return np.array(img).astype(float) / 255.0


def _diffuse(g, kern, divisor=1):
    """Error-diffusion dither shared by fs/atkinson/sierra/stucki.

    ``kern`` is a list of (dx, dy, weight); ``divisor`` scales the
    quantisation error (Atkinson uses 8, the others 1).
    """
    buf = g.tolist()
    hh = len(buf)
    ww = len(buf[0])
    o = [[0] * ww for _ in range(hh)]

    def cl(v):
        return max(0.0, min(1.0, v))

    for y in range(hh):
        for x in range(ww):
            old = buf[y][x]
            new = 1.0 if old >= 0.5 else 0.0
            o[y][x] = new
            err = (old - new) / divisor
            for dx, dy, k in kern:
                nx, ny = x + dx, y + dy
                if 0 <= nx < ww and 0 <= ny < hh:
                    buf[ny][nx] = cl(buf[ny][nx] + err * k)
    return np.array(o)


def dither_fs(g):
    return _diffuse(
        g,
        [(1, 0, 7 / 16), (-1, 1, 3 / 16), (0, 1, 5 / 16), (1, 1, 1 / 16)],
    )


def dither_atkinson(g):
    return _diffuse(
        g,
        [(1, 0, 1), (2, 0, 1), (-1, 1, 1), (0, 1, 1), (1, 1, 1), (0, 2, 1)],
        divisor=8,
    )


def dither_sierra(g):
    return _diffuse(
        g,
        [
            (1, 0, 5 / 32),
            (2, 0, 3 / 32),
            (-2, 1, 2 / 32),
            (-1, 1, 4 / 32),
            (0, 1, 5 / 32),
            (1, 1, 4 / 32),
            (2, 1, 2 / 32),
            (-1, 2, 2 / 32),
            (0, 2, 3 / 32),
            (1, 2, 2 / 32),
        ],
    )


def dither_stucki(g):
    return _diffuse(
        g,
        [
            (1, 0, 8 / 42),
            (2, 0, 4 / 42),
            (-2, 1, 2 / 42),
            (-1, 1, 4 / 42),
            (0, 1, 8 / 42),
            (1, 1, 4 / 42),
            (2, 1, 2 / 42),
            (-2, 2, 1 / 42),
            (-1, 2, 2 / 42),
            (0, 2, 4 / 42),
            (1, 2, 2 / 42),
            (2, 2, 1 / 42),
        ],
    )


def dither_bayer(g, n=4):
    base = np.array(
        [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]],
        dtype=float,
    )
    hh, ww = g.shape
    o = np.zeros(g.shape)
    for y in range(hh):
        for x in range(ww):
            th = (base[y % n][x % n] + 0.5) / (n * n)
            o[y][x] = 1 if g[y][x] >= th else 0
    return o


def dither_noise(g, seed=0):
    r = np.random.RandomState(seed)
    return (g > r.rand(*g.shape)).astype(int)


def dither_none(g):
    return (g >= 0.5).astype(int)


DITHERS = {
    "fs": dither_fs,
    "atkinson": dither_atkinson,
    "sierra": dither_sierra,
    "stucki": dither_stucki,
    "bayer": dither_bayer,
    "noise": dither_noise,
    "none": dither_none,
}


def colormap(mask, norm, palette):
    """Vectorized: color the dithered mask by the palette (fast)."""
    stops = palette
    xs = np.array([s[0] for s in stops], dtype=float)
    ys = np.array([[s[1][k] for k in range(3)] for s in stops], dtype=float)
    n = np.clip(norm, 0, 1).astype(float)
    vals = np.empty(n.shape + (3,), dtype=np.float32)
    for k in range(3):
        vals[..., k] = np.interp(n, xs, ys[:, k])
    bg = np.array(stops[0][1], dtype=np.float32) * 0.22
    out = np.where(
        mask[..., None].astype(bool), vals.astype("uint8"), bg.astype("uint8")
    )
    return Image.fromarray(out).convert("RGBA")


def blizzard(
    im, n, storm, wind, seed, contour=None, maxd=66, shader="none", accum=1.0
):
    r = random.Random(seed)

    # three depth layers (depth-of-field): bg small/fast/faint, mid, fg big/slow/close
    def layer(cnt, vrange, rrange, drift, alpha, blur):
        return {
            "fl": [
                {
                    "x": r.uniform(0, TW),
                    "y": r.uniform(-TH, TH),
                    "v": r.uniform(*vrange) * storm,
                    "r": r.uniform(*rrange),
                    "drift": r.uniform(*drift),
                }
                for _ in range(cnt)
            ],
            "alpha": alpha,
            "blur": blur,
        }

    L = [
        layer(200, (150, 270), (0.9, 1.8), (0.5, 1.1), 110, 1.6),
        layer(150, (95, 185), (2.1, 3.5), (0.6, 1.3), 180, 1.0),
        layer(70, (40, 90), (4.0, 6.6), (0.7, 1.6), 235, 0.4),
    ]
    # vortex (subtle swirl of flakes around a center)
    swirl = {"cx": TW * 0.5, "cy": TH * 0.55, "ang": 0.0}
    swirl_pts = [
        {
            "rad": r.uniform(60, 220),
            "spd": r.uniform(0.5, 1.2),
            "phase": r.uniform(0, 6.28),
            "r": r.uniform(1.2, 2.6),
        }
        for _ in range(26)
    ]
    # broad rounded snow drifts (smooth Gaussian mounds along the contour)
    nm = max(4, TW // 55)
    mound0 = []
    for i in range(nm):
        mound0.append(
            (r.uniform(0, TW), r.uniform(30, 170), r.uniform(0.35, 1.9))
        )
    # low-frequency organic wobble so the drift top is irregular, not smooth mounds
    wph1 = r.uniform(0, 6.28)
    wph2 = r.uniform(0, 6.28)
    depth_profile = [0.0] * TW
    for x in range(TW):
        v = 0.0
        for cx, w, h in mound0:
            v = max(v, h * math.exp(-(((x - cx) / w) ** 2)))
        v *= (
            1.0
            + 0.18 * math.sin(x * 0.018 + wph1)
            + 0.10 * math.sin(x * 0.045 + wph2)
        )
        depth_profile[x] = max(0.0, v)
    fr = []
    for t in range(n):
        ph = t / n
        # gust energy: overlapping waves (more variable)
        gust = (
            0.55
            + 0.35 * math.sin(2 * math.pi * ph)
            + 0.20 * math.sin(2 * math.pi * ph * 2 + 1.1)
        )
        inten = max(0.35, gust * wind)
        # wind: wide-varying angle + multi-harmonic gusts
        wnd_ang = math.radians(
            -34 + 26 * math.sin(2 * math.pi * ph * 1.7 + 0.4)
        )
        wnd = (
            2.0
            + 2.6 * math.sin(2 * math.pi * ph + 0.9)
            + 1.2 * math.sin(2 * math.pi * ph * 3 + 2.0)
        )
        wx = math.sin(wnd_ang) * wnd * wind
        # snow drawn at half resolution then upscaled (fast + soft)
        ov = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
        # depth layers, each blurred separately (full quality DoF)
        for Lx in L:
            loy = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
            lod = ImageDraw.Draw(loy)
            for fl in Lx["fl"]:
                fl["y"] += fl["v"]
                fl["x"] += fl["v"] * fl["drift"] * wx
                if fl["y"] > TH + 14:
                    fl["y"] = r.uniform(-40, -4)
                    fl["x"] = r.uniform(0, TW)
                if fl["x"] > TW + 14:
                    fl["x"] = -14
                if fl["x"] < -14:
                    fl["x"] = TW + 14
                rr = fl["r"]
                a = int(Lx["alpha"] * (0.55 + 0.45 * inten))
                # realistic driving snow: soft streak along the wind/fall vector
                vx = fl["v"] * fl["drift"] * wx
                vy = fl["v"]
                mag = math.hypot(vx, vy) or 1.0
                sl = rr * 2.6 + fl["v"] * 0.016  # streak length (motion blur)
                ux, uy = vx / mag, vy / mag
                hx, hy = fl["x"], fl["y"]
                tx, ty = hx - ux * sl, hy - uy * sl
                lod.line(
                    [(hx, hy), (tx, ty)],
                    fill=(236, 243, 253, a),
                    width=max(1, int(rr)),
                )
                lod.line(
                    [(hx, hy), (hx - ux * sl * 0.5, hy - uy * sl * 0.5)],
                    fill=(246, 250, 255, int(a * 1.25)),
                    width=1,
                )
            ov = Image.alpha_composite(
                ov, loy.filter(ImageFilter.GaussianBlur(Lx["blur"]))
            )
        # vortex swirl
        sod = ImageDraw.Draw(ov)
        swirl["ang"] += 0.02
        for pt in swirl_pts:
            a0 = pt["phase"] + swirl["ang"] / pt["spd"]
            x = swirl["cx"] + pt["rad"] * math.cos(a0)
            y = swirl["cy"] + pt["rad"] * 0.62 * math.sin(a0)
            if 0 <= x < TW and 0 <= y < TH:
                sod.ellipse(
                    [x - pt["r"], y - pt["r"], x + pt["r"], y + pt["r"]],
                    fill=(230, 240, 250, max(0, int(140 * inten))),
                )
        # snow accumulation: a growing, layered white cap with organic drifts
        if contour is not None:
            depth = (maxd * accum) * (
                (t + 1) / n
            ) ** 1.8 + 3  # slower accumulation over time
            acc = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
            ad = ImageDraw.Draw(acc)
            for x in range(TW):
                y0 = contour[x]
                if y0 >= TH - 2:
                    continue
                v = depth_profile[x]
                d = max(2, int(v * depth + r.uniform(-1, 1)))
                y1 = min(TH, y0 + d)
                # slope shading (flat peak bright, steep slope dark) + crevice AO (low v)
                sl = (
                    depth_profile[min(x + 1, TW - 1)]
                    - depth_profile[max(x - 1, 0)]
                )
                flat = max(0.0, 1.0 - abs(sl) * 2.3)
                crev = max(
                    0.0, 1.0 - min(1.5, v * 1.2)
                )  # 1 in a deep valley (AO), 0 on ridges
                bright = max(0.0, flat * (1.0 - crev * 0.72))
                steps = 5
                for k in range(steps):
                    fr_t = k / steps
                    t = max(0.0, bright * (1.0 - fr_t * 0.5))
                    rr = int(140 + (252 - 140) * t)
                    gg = int(158 + (253 - 158) * t)
                    bb = int(188 + (255 - 188) * t)
                    a = int(65 + (238 - 65) * (0.30 + 0.70 * t))
                    yy0 = y0 + (k * d) // steps
                    yy1 = y0 + ((k + 1) * d) // steps
                    ad.line(
                        [(x, yy0), (x, yy1)], fill=(rr, gg, bb, a), width=1
                    )
                # snow overhang: wider bright rim bulging just past the silhouette edge
                if d > 5:
                    ad.line(
                        [(x - 1, y0 + 1), (x + 1, y0 + 1)],
                        fill=(255, 255, 255, 215),
                        width=2,
                    )
                # bright specular on sunlit peaks
                if flat > 0.6 and d > 8:
                    ad.line(
                        [(x, y0), (x, y0 + 1)],
                        fill=(255, 255, 255, 245),
                        width=2,
                    )
                # underside shadow where snow meets the hood (soft AO)
                ad.line(
                    [(x, y1), (x, min(TH, y1 + 3))],
                    fill=(70, 84, 116, 90),
                    width=2,
                )
                # deep-valley crevice line
                if crev > 0.5:
                    ad.line(
                        [(x, y1), (x, min(TH, y1 + 2))],
                        fill=(38, 50, 84, 120),
                        width=2,
                    )
            acc = acc.filter(ImageFilter.GaussianBlur(1.3))
            ov = Image.alpha_composite(ov, acc)
        # breathing: gamma + slight brightness (skull pulses, black bg stays black)
        b = 1.0 + 0.05 * math.sin(2 * math.pi * ph)
        g = 1.0 + 0.14 * math.sin(2 * math.pi * ph * 2 + 0.6)
        lut = []
        for v in range(256):
            x = v / 255.0
            x = max(0.0, min(1.0, x))
            x = x ** (1.0 / g)  # keeps 0->0 (blacks pure), pulses mids/highs
            x = min(1.0, x) * b
            lut.append(max(0, min(255, int(x * 255))))
        base = im.point(lut + lut + lut)
        frame = Image.alpha_composite(base.convert("RGBA"), ov).convert("RGB")
        fr.append(apply_shader(frame, shader))
    return fr


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dither", default="fs", choices=list(DITHERS))
    p.add_argument("--palette", default="ash", choices=list(PALETTES))
    p.add_argument(
        "--color",
        default="",
        help="custom base color #RRGGBB -> builds its own gradient",
    )
    p.add_argument(
        "--size",
        default="",
        help="output resolution WxH (default 640x806; bigger e.g. 900x1130)",
    )
    p.add_argument(
        "--shader",
        default="none",
        choices=["none", "invert", "rgb", "invert:rgb"],
    )
    p.add_argument(
        "--accum",
        type=float,
        default=0.0,
        help="snow accumulation amount (0 = off, >0 re-enables the growing cap)",
    )
    p.add_argument("--storm", type=float, default=1.0)
    p.add_argument("--wind", type=float, default=1.0)
    p.add_argument("--frames", type=int, default=24)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument(
        "--out",
        default=os.path.expanduser(
            "~/.local/share/fastfetch/logos/blizzard.webp"
        ),
    )
    p.add_argument("--ref", default=REF)
    a = p.parse_args()
    global TW, TH
    if a.size:
        w_, h_ = a.size.split("x")
        TW, TH = int(w_), int(h_)
    if a.color:
        PALETTES["custom"] = build_gradient(a.color)
        a.palette = "custom"
    norm = load_norm(a.ref)
    mask = DITHERS[a.dither](norm)
    base = colormap(mask, norm, PALETTES[a.palette]).convert("RGB")
    contour = compute_snow_contour(norm) if a.accum > 0 else None
    fr = blizzard(
        base,
        a.frames,
        a.storm,
        a.wind,
        a.seed,
        contour=contour,
        shader=a.shader,
        accum=a.accum,
    )
    fr[0].save(
        a.out,
        "WEBP",
        save_all=True,
        append_images=fr[1:],
        duration=46,
        loop=0,
        lossless=False,
        quality=92,
        method=6,
    )
    print(
        "wrote",
        a.out,
        os.path.getsize(a.out),
        "| dither",
        a.dither,
        "palette",
        a.palette,
    )


if __name__ == "__main__":
    main()
