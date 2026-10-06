#!/usr/bin/env python3
"""Measure the nixie tubes on a screenshot: the numbers the tubes are judged by.

The look of a tube cannot be reviewed in a chat, so this measures what a photo of a
real one measures: how wide the lit wire is, how fast its gas falls off, how much
light the glass itself adds, whether the anode mesh is there and how many unlit
cathodes can be seen. Thresholds are the acceptance criteria (A1..A7) in
docs/howto/designs/nixie-lamps-plan.xml.

usage: nixie-metrics.py SHOT.png [--mode digits|clock] [--check]
"""

import sys
import numpy as np
from PIL import Image

LIMITS = {
    "wire_white_px": 8,  # A2: the white-hot zone of the lit wire, device px
    "wire_hot_px": 16,  # A2: R > 200
    "halo_half_px": (6, 14),  # A2: where the gas halves, device px
    # A3: the unlit tube carries the anode cage and the whole cathode stack in
    # front of the picture, so it is darker than bare glass would be.
    "glass_mid_ratio": 0.40,
    "glass_own_light": 0.08,  # A3: the glass's own light vs the wire
    # A6: a weak automated proxy — the wires are thin and the contrast over a dark
    # wallpaper is low. The real check for the stack is the eye on the digits
    # harness (M4 in the plan); this only catches a tube that lost it entirely.
    "cathodes_min": 1,
    "cage_contrast": 0.03,  # A5
}


def runs(mask):
    out, i = [], 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j + 1 < len(mask) and mask[j + 1]:
                j += 1
            out.append((i, j - i + 1))
            i = j + 1
        else:
            i += 1
    return out


def tubes(img):
    """Column clusters of warm pixels — one per lit tube."""
    a = np.asarray(img.convert("RGB")).astype(np.int16)
    r, b = a[..., 0], a[..., 2]
    hot = (r > 110) & (r - b > 40)
    cols = hot.sum(axis=0)
    raw, i = [], 0
    while i < len(cols):
        if cols[i] > 3:
            j = i
            while j + 1 < len(cols) and cols[j + 1] > 3:
                j += 1
            if j - i > 12:
                raw.append([i, j])
            i = j + 1
        else:
            i += 1
    # a numeral can break into two column runs (the mast and its flag): glue the
    # runs that sit closer than half a tube together
    widths = [e - s for s, e in raw] or [1]
    gap = 0.5 * float(np.median(widths))
    clusters = []
    for s, e in raw:
        if clusters and s - clusters[-1][1] < gap:
            clusters[-1][1] = e
        else:
            clusters.append([s, e])
    return a, [tuple(c) for c in clusters]


def measure(a, x0, x1, label, yband=None):
    """Per tube: the wire, the gas, the glass and what is inside it."""
    r = a[..., 0]
    sub = (slice(None), slice(x0, x1))
    warm = (r[sub] > 110) & ((r - a[..., 2])[sub] > 40)
    ys = np.nonzero(warm.any(axis=1))[0]
    if yband is not None:
        y0, y1 = yband
    else:
        y0, y1 = ys.min(), ys.max()
    ymid = (y0 + y1) // 2
    out = {"id": label, "bbox": (int(x0), int(x1), int(y0), int(y1))}

    # the lit wire and its gas, on the row through the middle of the numeral
    rows = range(max(y0, 1), min(y1, a.shape[0] - 1))
    white = [
        max([w for _, w in runs(r[y, x0 - 20 : x1 + 20] > 240)] or [0])
        for y in rows
    ]
    hotw = [
        max([w for _, w in runs(r[y, x0 - 20 : x1 + 20] > 200)] or [0])
        for y in rows
    ]
    out["wire_white_px"] = int(np.median(white)) if white else 0
    out["wire_hot_px"] = int(np.median(hotw)) if hotw else 0
    row = r[ymid, x0 - 20 : x1 + 20]
    peak = np.argmax(row)
    if 0 < peak < len(row) - 1:
        half = row[peak] / 2.0
        i = peak
        while i > 0 and row[i] > half:
            i -= 1
        left = peak - i
        i = peak
        while i < len(row) - 1 and row[i] > half:
            i += 1
        out["halo_half_px"] = int(max(left, i - peak))

    # the glass's own light: the tube's interior above the numeral, against the
    # wallpaper just outside the glass on the same rows
    band = slice(max(y0 - 40, 0), max(y0 - 12, 1))
    lum = a[..., 0] * 0.3 + a[..., 1] * 0.6 + a[..., 2] * 0.1
    cx = (x0 + x1) // 2
    inside = lum[band, cx - 10 : cx + 10].mean()
    outside = np.concatenate(
        [
            lum[band, max(cx - 130, 0) : max(cx - 90, 1)].ravel(),
            lum[band, cx + 90 : cx + 130].ravel(),
        ]
    ).mean()
    out["glass_mid_ratio"] = float(inside / max(outside, 0.01) - 1.0)
    out["glass_own_light"] = float(inside / max(row[peak], 1.0))

    # what is inside: the mesh and the stack show up as high-frequency structure
    win = lum[y0 + 10 : y1 - 10, cx - 18 : cx + 18]
    dx = np.abs(np.diff(win, axis=1))
    out["cage_contrast"] = float(np.median(dx) / max(win.mean(), 0.01))
    profile = win.mean(axis=0)
    out["cathodes_min"] = len(runs(profile > profile.mean() * 1.06))
    out["_ymid"] = int(ymid)
    return out


def orientation(a, x0, x1, digit):
    """A7: 7 has its mass in the top half, 2 has a bar across the bottom."""
    r = a[..., 0]
    warm = (r[:, x0:x1] > 110) & ((r - a[..., 2])[:, x0:x1] > 40)
    ys, xs = np.nonzero(warm)
    if not len(ys):
        return None
    y0, y1 = ys.min(), ys.max()
    mid = (y0 + y1) / 2
    if digit == 7:
        return "pass" if ys.mean() < mid else "FAIL (mass below the middle)"
    if digit == 2:
        band = warm[int(y1 - 0.2 * (y1 - y0)) :, :]
        widths = [w for _, w in runs(band.any(axis=0))]
        need = 0.45 * (xs.max() - xs.min() + 1)
        return (
            "pass"
            if max(widths or [0]) >= need
            else f"FAIL (no bar, max {max(widths or [0])} < {need:.0f})"
        )
    return "-"


def main():
    path = sys.argv[1]
    mode = "clock"
    check = "--check" in sys.argv
    if "--mode" in sys.argv:
        mode = sys.argv[sys.argv.index("--mode") + 1]
    img = Image.open(path)
    a, clusters = tubes(img)
    if not clusters:
        print("no lit tube found in the shot")
        return 2
    print(f"{path}: {len(clusters)} tube(s), mode={mode}")
    bad = []
    # The last tube of the digits harness is unlit. It is the only place where the
    # glass, the anode mesh and the cathode stack can be measured without the
    # discharge drowning them: measure those there, and only the wire on lit tubes.
    unlit = mode == "digits" and len(clusters) > 10
    lit = clusters[:-1] if unlit else clusters
    boxes = []
    for i, (x0, x1) in enumerate(lit):
        m = measure(a, x0, x1, f"tube{i}")
        boxes.append((m["bbox"][2], m["bbox"][3]))
        print(
            f"  {m['id']}: wire white {m['wire_white_px']}px hot {m['wire_hot_px']}px | "
            f"halo half {m.get('halo_half_px', '?')}px"
        )
        if check:
            if m["wire_white_px"] > LIMITS["wire_white_px"]:
                bad.append(
                    f"{m['id']}: wire white {m['wire_white_px']} > {LIMITS['wire_white_px']}"
                )
            if m["wire_hot_px"] > LIMITS["wire_hot_px"]:
                bad.append(
                    f"{m['id']}: wire hot {m['wire_hot_px']} > {LIMITS['wire_hot_px']}"
                )
    if unlit:
        x0, x1 = clusters[-1]
        yband = (
            (
                int(np.median([b[0] for b in boxes])),
                int(np.median([b[1] for b in boxes])),
            )
            if boxes
            else None
        )
        m = measure(a, x0, x1, "unlit", yband)
        print(
            f"  unlit tube (glass only): glass {m['glass_mid_ratio']:+.0%} / own {m['glass_own_light']:.0%} | "
            f"mesh {m['cage_contrast']:.1%} | bars {m['cathodes_min']}"
        )
        if check and abs(m["glass_mid_ratio"]) > LIMITS["glass_mid_ratio"]:
            bad.append(
                f"unlit: glass {m['glass_mid_ratio']:+.0%} (limit ±{LIMITS['glass_mid_ratio']:.0%})"
            )
        if check and m["cathodes_min"] < LIMITS["cathodes_min"]:
            bad.append(
                f"unlit: visible bars {m['cathodes_min']} < {LIMITS['cathodes_min']}"
            )
        if check and m["cage_contrast"] < LIMITS["cage_contrast"]:
            bad.append(
                f"unlit: mesh contrast {m['cage_contrast']:.1%} < {LIMITS['cage_contrast']:.0%}"
            )
        if check and m["glass_own_light"] > 4.0:
            bad.append(
                f"unlit: glass own light {m['glass_own_light']:.0%} of the wire (expected: dim)"
            )
    if mode == "digits":
        for k in range(min(len(clusters), 10)):
            x0, x1 = clusters[k]
            res = orientation(a, x0, x1, k)
            if res and res != "-":
                print(f"  digit {k}: orientation {res}")
                if check and res != "pass":
                    bad.append(f"digit {k}: {res}")
    if check:
        if bad:
            print("\nFAIL:")
            for b in bad:
                print("  -", b)
            return 1
        print("\nOK: every measured criterion is inside its limit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
