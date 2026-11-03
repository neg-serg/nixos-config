#!/usr/bin/env python3
"""Generate the badnik sprite sheet (the run's procedural opponent).

Classic-style hovering robot: steel shell, red lens, propeller, pincers. Drawn
from primitives, no third-party asset. Sheet: 3 frames of 36x36 (hover A,
hover B, destroyed).

Usage: python3 tools/generate_badnik.py
"""

import math
import os

from PIL import Image, ImageDraw

W = H = 36
STEEL = (185, 198, 207, 255)
LIGHT = (226, 235, 240, 255)
DARK = (58, 70, 80, 255)
OUT = (10, 16, 40, 255)
RED = (224, 48, 48, 255)
DRED = (140, 20, 24, 255)
ORANGE = (255, 168, 64, 255)
YELLOW = (255, 236, 150, 255)


def ell(d, cx, cy, rx, ry, col, outline=None, width=1):
    d.ellipse(
        [cx - rx, cy - ry, cx + rx, cy + ry],
        fill=col,
        outline=outline,
        width=width,
    )


def blade(d, cx, cy, angle, length=11, width=3):
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    x0, y0 = cx - dx * length, cy - dy * length
    x1, y1 = cx + dx * length, cy + dy * length
    nx, ny = -dy * width / 2, dx * width / 2
    d.polygon(
        [
            (x0 + nx, y0 + ny),
            (x1 + nx, y1 + ny),
            (x1 - nx, y1 - ny),
            (x0 - nx, y0 - ny),
        ],
        fill=DARK,
    )


def hover(angle):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # propeller
    blade(d, 18, 6, angle)
    blade(d, 18, 6, angle + 90)
    ell(d, 18, 6, 2.5, 2.5, LIGHT, DARK)
    d.rectangle([16, 8, 20, 11], fill=DARK)
    # pincers
    d.polygon([(9, 26), (4, 30), (9, 32)], fill=DARK)
    d.polygon([(27, 26), (32, 30), (27, 32)], fill=DARK)
    d.polygon([(9, 27), (6, 30), (9, 31)], fill=STEEL)
    d.polygon([(27, 27), (30, 30), (27, 31)], fill=STEEL)
    # body
    ell(d, 18, 20, 11, 10, STEEL)
    ell(d, 14, 15, 4.5, 3.5, LIGHT)
    # lens
    ell(d, 24, 18, 5, 4.5, DARK)
    ell(d, 24, 18, 3.4, 3.2, RED)
    ell(d, 23, 17, 1.2, 1.2, LIGHT)
    # grille
    for i in range(3):
        d.line([(10, 25 + i * 2), (17, 25 + i * 2)], fill=DARK, width=1)
    # cartoon outline
    return outline(img)


def boom():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(8):
        a = math.radians(i * 45)
        tip = (18 + math.cos(a) * 15, 18 + math.sin(a) * 15)
        b1 = (18 + math.cos(a + 0.4) * 7, 18 + math.sin(a + 0.4) * 7)
        b2 = (18 + math.cos(a - 0.4) * 7, 18 + math.sin(a - 0.4) * 7)
        d.polygon([b1, tip, b2], fill=ORANGE)
    ell(d, 18, 18, 8, 8, YELLOW)
    return outline(img)


def outline(img):
    px = img.load()
    mask = [[px[x, y][3] > 0 for x in range(W)] for y in range(H)]
    out = img.copy()
    od = ImageDraw.Draw(out)
    for y in range(H):
        for x in range(W):
            if mask[y][x]:
                continue
            near = any(
                0 <= x + dx < W and 0 <= y + dy < H and mask[y + dy][x + dx]
                for dy in (-1, 0, 1)
                for dx in (-1, 0, 1)
            )
            if near:
                od.point((x, y), fill=OUT)
    return out


frames = [hover(0), hover(45), boom()]
sheet = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
for i, f in enumerate(frames):
    sheet.alpha_composite(f, (i * W, 0))
out = os.path.join(os.path.dirname(__file__), "..", "assets", "badnik.png")
sheet.save(out)
print("wrote", os.path.normpath(out), sheet.size)
