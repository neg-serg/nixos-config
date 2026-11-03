#!/usr/bin/env python3
"""Cut the crab out of the source wallpaper.

The crab sits on the grass ledge at the right-hand cliff; its body is partly
hidden by the grass fringe, so the sprite is the exact set of warm pixels from
the painting rather than a redrawn character. Keeping the extraction script in
the package documents where every pixel came from.

Usage: python3 tools/extract_crab.py SRC.jpg OUT.png
Requires Pillow (nix shell nixpkgs#python3Packages.pillow).
"""

import sys

from PIL import Image
import numpy as np

# Bounding box around the crab in the 7680x2160 painting, generous by a few
# pixels so the claws are not clipped.
CROP = (4528, 1790, 4648, 1861)


def main() -> None:
    src, out = sys.argv[1], sys.argv[2]
    img = Image.open(src).convert("RGB")
    x0, y0, x1, y1 = CROP
    box = np.asarray(img)[y0:y1, x0:x1].astype(np.int16)
    r, g, b = box[..., 0], box[..., 1], box[..., 2]

    # The crab is the only warm object on that ledge: grass is green and the
    # cliff behind it is cold blue-grey.
    warm = (r >= g + 6) & (r >= b + 8)

    # Close one-pixel gaps so the mask does not perforate the body, then fill
    # every hole that is not reachable from the crop border.
    mask = warm.copy()
    for _ in range(2):
        p = np.pad(mask, 1)
        mask = (
            p[1:-1, 1:-1]
            | p[:-2, 1:-1]
            | p[2:, 1:-1]
            | p[1:-1, :-2]
            | p[1:-1, 2:]
        )

    height, width = mask.shape
    outside = np.zeros_like(mask)
    stack = [(0, 0)]
    outside[0, 0] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if (
                0 <= ny < height
                and 0 <= nx < width
                and not mask[ny, nx]
                and not outside[ny, nx]
            ):
                outside[ny, nx] = True
                stack.append((ny, nx))
    filled = ~outside

    # Grass blades caught by the closing pass are green/olive: drop them.
    green = (g >= r - 2) & (g > b + 4)
    alpha = filled & ~green

    # Dropping the green leaves can orphan a few pixels: keep only real
    # components so no confetti follows the crab around.
    seen = np.zeros_like(alpha)
    for start_y in range(height):
        for start_x in range(width):
            if not alpha[start_y, start_x] or seen[start_y, start_x]:
                continue
            stack = [(start_y, start_x)]
            seen[start_y, start_x] = True
            component = []
            while stack:
                y, x = stack.pop()
                component.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if (
                        0 <= ny < height
                        and 0 <= nx < width
                        and alpha[ny, nx]
                        and not seen[ny, nx]
                    ):
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(component) < 30:
                for y, x in component:
                    alpha[y, x] = False

    rgba = np.dstack([box.astype(np.uint8), (alpha * 255).astype(np.uint8)])
    sprite = Image.fromarray(rgba, "RGBA")

    bbox = sprite.getbbox()
    sprite = sprite.crop(bbox)
    pad = Image.new(
        "RGBA", (sprite.width + 2, sprite.height + 2), (0, 0, 0, 0)
    )
    pad.alpha_composite(sprite, (1, 1))
    pad.save(out)
    print(f"{out}: {pad.width}x{pad.height}")


if __name__ == "__main__":
    main()
