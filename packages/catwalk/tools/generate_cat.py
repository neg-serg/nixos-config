#!/usr/bin/env python3
"""Generate the cute-cat sprite sheet used by catwalk.

A small ginger cat drawn from primitives: big head, big eyes, striped tabby
fur, cream muzzle and socks. Sheet layout: idle 0..1, run 2..5, curl-ball
6..8, 40x48 each.

Usage: python3 tools/generate_cat.py
"""

import math
import os

from PIL import Image, ImageDraw

W, H = 40, 48
FUR = (240, 162, 60, 255)
FUR_D = (201, 111, 34, 255)
CREAM = (251, 231, 200, 255)
PINK = (245, 163, 176, 255)
DARK = (58, 36, 24, 255)
EYE = (52, 36, 30, 255)
WHITE = (255, 255, 255, 255)
OUT = (42, 26, 18, 255)


def ell(d, cx, cy, rx, ry, col, outline=None, width=1):
    d.ellipse(
        [cx - rx, cy - ry, cx + rx, cy + ry],
        fill=col,
        outline=outline,
        width=width,
    )


def tri(d, pts, col):
    d.polygon(pts, fill=col)


def cat(tail=0.0, front=(0, 0), back=(0, 0), bob=0, blink=False):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    hx, hy = 19, 14 + bob

    # tail: curled, behind the body
    tx, ty = 11, 37 + bob
    mid = (tx - 6 + tail, ty - 6)
    tip = (mid[0] + 2 + tail, mid[1] - 6)
    d.line([(tx, ty), mid, tip], fill=FUR_D, width=3, joint="curve")
    ell(d, tip[0], tip[1], 1.8, 1.8, FUR)

    # ears
    tri(d, [(9, hy - 7), (11, hy - 15), (17, hy - 8)], FUR)
    tri(d, [(23, hy - 8), (29, hy - 15), (31, hy - 7)], FUR)
    tri(d, [(11, hy - 8), (12, hy - 13), (15, hy - 9)], PINK)
    tri(d, [(25, hy - 9), (28, hy - 13), (29, hy - 8)], PINK)

    # head
    ell(d, hx, hy, 12, 10, FUR)
    # tabby stripes
    d.line([(hx - 5, hy - 9), (hx - 3, hy - 6)], fill=FUR_D, width=1)
    d.line([(hx + 1, hy - 10), (hx + 2, hy - 7)], fill=FUR_D, width=1)
    d.line([(hx + 6, hy - 8), (hx + 5, hy - 6)], fill=FUR_D, width=1)

    # muzzle + nose + mouth
    ell(d, 20, hy + 6, 6, 4, CREAM)
    tri(d, [(18.5, hy + 3), (21.5, hy + 3), (20, hy + 5)], PINK)
    d.line([(20, hy + 5), (20, hy + 6)], fill=DARK, width=1)
    d.line([(18, hy + 7), (20, hy + 6)], fill=DARK, width=1)
    d.line([(22, hy + 7), (20, hy + 6)], fill=DARK, width=1)

    # eyes
    if blink:
        d.line([(12, hy), (17, hy)], fill=EYE, width=1)
        d.line([(24, hy), (29, hy)], fill=EYE, width=1)
    else:
        ell(d, 14.5, hy, 4, 4.5, EYE)
        ell(d, 25.5, hy, 4, 4.5, EYE)
        ell(d, 16, hy - 1.5, 1.4, 1.6, WHITE)
        ell(d, 27, hy - 1.5, 1.4, 1.6, WHITE)

    # body
    by = 32 + bob
    ell(d, 20, by, 7.5, 7, FUR)
    ell(d, 21, by + 2, 4, 4, CREAM)
    d.line([(14, by - 4), (14, by + 2)], fill=FUR_D, width=1)
    d.line([(26, by - 4), (26, by + 2)], fill=FUR_D, width=1)

    # paws
    for px, (dx, dy) in ((15, back), (26, front)):
        ell(d, px + dx, by + 9 + dy, 4.5, 3.5, FUR)
        ell(d, px + dx, by + 8 + dy, 3, 2, CREAM)

    return whiskers(outline(img), hy)


def ball(angle):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy, r = 20, 25, 13
    # tucked tail
    d.arc(
        [cx - r - 3, cy - r + 2, cx + r + 3, cy + r + 8],
        20,
        300,
        fill=FUR_D,
        width=3,
    )
    ell(d, cx, cy, r, r, FUR)
    # ears tucked into the curl
    tri(d, [(cx - 9, cy - 8), (cx - 7, cy - 15), (cx - 2, cy - 10)], FUR)
    tri(d, [(cx + 2, cy - 10), (cx + 7, cy - 15), (cx + 9, cy - 8)], FUR)
    # stripes rotate with the ball
    for i in range(3):
        a = math.radians(angle + i * 120 + 40)
        x0, y0 = cx + math.cos(a) * (r - 3), cy + math.sin(a) * (r - 3)
        x1, y1 = cx + math.cos(a) * (r - 9), cy + math.sin(a) * (r - 9)
        d.line([(x0, y0), (x1, y1)], fill=FUR_D, width=2)
    # curled cream belly patch
    bx = cx + math.cos(math.radians(angle + 200)) * 4
    by = cy + math.sin(math.radians(angle + 200)) * 4
    ell(d, bx, by, 3.5, 3, CREAM)
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


def whiskers(img, hy):
    d = ImageDraw.Draw(img)
    for dy in (4, 7):
        d.line([(8, hy + dy), (13, hy + dy - 0.5)], fill=CREAM, width=1)
        d.line([(32, hy + dy), (27, hy + dy - 0.5)], fill=CREAM, width=1)
    return img


frames = [
    cat(),
    cat(tail=2, bob=1),
    cat(tail=3, front=(3, -2), back=(-3, 0)),
    cat(tail=-2, front=(-2, 1), back=(2, -1)),
    cat(tail=4, front=(3, 0), back=(-3, -1)),
    cat(tail=-3, front=(-2, -1), back=(2, 0)),
    ball(0),
    ball(40),
    ball(80),
]

sheet = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
for i, f in enumerate(frames):
    sheet.alpha_composite(f, (i * W, 0))
out = os.path.join(os.path.dirname(__file__), "..", "assets", "cat.png")
sheet.save(out)
print("wrote", os.path.normpath(out), sheet.size)
