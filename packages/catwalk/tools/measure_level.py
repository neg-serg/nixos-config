#!/usr/bin/env python3
"""Print the rock-top profile used by the falls staircase in src/level.rs.

Scans columns for the first long run of warm rock below the tree line and
prints x, top. Run it after changing the wallpaper crop if the level needs to
be re-aligned: the numbers in Level::waterfall come from this table.

Usage: python3 tools/measure_level.py SRC.jpg
"""

import sys

from PIL import Image
import numpy as np


def main() -> None:
    img = Image.open(sys.argv[1]).convert("RGB")
    a = np.asarray(img).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    rock = (r > b + 20) & (r > 60) & (g > 35)
    run = 24
    for x in range(650, 1450, 25):
        col = rock[1700:2100, x]
        top = None
        for i in range(len(col) - run):
            if col[i : i + run].mean() > 0.9:
                top = 1700 + i
                break
        if top is not None:
            print(f"{x:5d} {top:5d}")


if __name__ == "__main__":
    main()
