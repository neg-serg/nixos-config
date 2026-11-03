#!/usr/bin/env python3
"""Remove the painted crab from the game's background.

The wallpaper keeps its own crab on the ledge; with Sonic as the player that
crab would sit next to him, so the game composites a small patch cloned from
the clean ledge a few hundred pixels to the left. The source JPEG stays
untouched: the patch is a separate 120x106 PNG, applied over the world at
load time, so the rest of the painting remains bit-identical.

Usage: python3 tools/make_world_patch.py SRC.jpg assets/world_patch.png
"""

import sys

from PIL import Image
import numpy as np

# Crab bounding box in the 7680x2160 painting, plus a margin.
X0, Y0, W, H = 4533, 1772, 120, 106
# Clean ledge immediately to the left (the crab's claws start at ~4537).
DX = 123


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    img = Image.open(src).convert("RGB")
    donor = img.crop((X0 - DX, Y0, X0 - DX + W, Y0 + H))
    target = img.crop((X0, Y0, X0 + W, Y0 + H))

    # Feather the seams so the clone does not show a rectangle.
    feather = 12
    mask = np.ones((H, W), dtype=np.float32)
    for i in range(feather):
        a = i / feather
        mask[i, :] *= a
        mask[H - 1 - i, :] *= a
        mask[:, i] *= a
        mask[:, W - 1 - i] *= a
    mask_img = Image.fromarray((mask * 255).astype(np.uint8), "L")

    patch = Image.composite(donor, target, mask_img)
    patch.save(out)
    print(f"{out}: {patch.width}x{patch.height}")


if __name__ == "__main__":
    main()
