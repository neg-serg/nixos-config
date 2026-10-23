#!/usr/bin/env bash
# Measure the bar's widgets against Quickshell's, window by window.
#
# `parity-bar.sh` answers "how much of the strip differs" with one number, and that
# number hid both of the defects the owner could see: the left cluster had drifted
# 32 logical px by the weather capsule, and the MPD badge was 25 px of ink where
# the reference's was 10. A mean over 3840x50 pixels cannot say "this widget moved".
#
# What is gated, and why exactly these numbers:
#
#   · **drift**, per window — the shift of one window's ink profile that best
#     explains the difference between the strips. Tolerance 4 logical px, because
#     the largest innocent residual measured on this machine after the parity
#     batches was +2 (the clock's ink sits 2 px left of the reference's) and the
#     smallest real defect was -20 (the missing badge shifted the right window by
#     20) and +32 (the left cluster before the widths were taken from the
#     reference). 4 is twice the noise and a fifth of the smallest signal.
#   · **the icon-only pairs of the right window** — the badge and the mic are the
#     same glyphs on both bars, of the same size, so their positions are
#     comparable to the pixel: 4 px of position and 3 px of width. Measured there:
#     -1 and -2 px once the widgets were right, -14 and +15 while the badge was a
#     capsule instead of a glyph.
#
# What is printed but *not* gated, because it cannot discriminate:
#
#   · the ink-profile mismatch of the left window. That window carries the
#     throughput digits, the temperature, the humidity and the wind — data that
#     changes every minute and differs between the two bars by construction (the
#     reference reads its own source, the port reads `/proc/net/dev`). It measured
#     17.2 % with the bar in its current state and 19.4 % before the badge fix:
#     the same order, so gating on it would fail for the weather outside.
#   · the number of ink runs, which kerning and digit shapes move by one.
#   · the per-run table of the left window — printed so a residual like the -1/-2 px
#     of the clock and the workspace capsule stays visible instead of disappearing
#     into a tolerance.
#
# Both bars run at once on this machine: Quickshell's sits on the bottom edge and
# the port's directly above it, so one frame holds both. `--ref high` swaps which
# band is the reference.
#
# Usage: parity-clusters.sh [REPO_ROOT] [--shot FILE] [--strip PX]
#                           [--tol-pos N] [--tol-w N] [--ref low|high] [--json]
#   --shot FILE   measure this PNG instead of taking a fresh one
#   --strip PX    height of one bar strip in physical px (default: 50)
#   --tol-pos N   allowed drift and |Δx| in logical px (default: 4)
#   --tol-w N     allowed |Δw| of an icon pair in logical px (default: 3)
#
# Exit: 0 within tolerance, 1 a window drifted or an icon moved or changed width,
#       2 no frame.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
shift || true

SHOT=""
STRIP=50
TOL_POS=4
TOL_W=3
REF=low
JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --shot) SHOT="${2:-}"; shift 2 ;;
    --strip) STRIP="${2:-}"; shift 2 ;;
    --tol-pos) TOL_POS="${2:-}"; shift 2 ;;
    --tol-w) TOL_W="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    *) echo "parity-clusters: unknown argument \$1" >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

if [ -z "$SHOT" ]; then
  for tool in grim magick python3; do
    command -v "$tool" >/dev/null || { echo "parity-clusters: $tool is missing" >&2; exit 2; }
  done
  [ -n "${WAYLAND_DISPLAY:-}" ] || {
    echo "parity-clusters: WAYLAND_DISPLAY is not set — run it from the session that shows the bar" >&2
    exit 2
  }
  SHOT="$(mktemp -t parity-clusters-XXXXXX.png)"
  grim "$SHOT" 2>/dev/null || {
    echo "parity-clusters: grim could not capture the screen" >&2
    exit 2
  }
fi
[ -f "$SHOT" ] || { echo "parity-clusters: no frame at $SHOT" >&2; exit 2; }

python3 - "$SHOT" "$STRIP" "$TOL_POS" "$TOL_W" "$REF" "$JSON" <<'PY'
import json
import sys
from PIL import Image
import numpy as np

shot, strip, tol_pos, tol_w, ref, as_json = (
    sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6] == "1",
)

img = np.asarray(Image.open(shot).convert("L"), dtype=np.float32)
h, w = img.shape
if h < 2 * strip:
    sys.exit(f"parity-clusters: {shot} is {h} px tall, two {strip} px strips do not fit")

low = img[h - strip:h]
high = img[h - 2 * strip:h - strip]
reference, port = (low, high) if ref == "low" else (high, low)

BUCKET = 4  # physical px: two design px at scale 2

def runs(band, x0, x1, thr=60, gap=10):
    columns = band[:, x0:x1].max(axis=0) > thr
    found, start = [], None
    for i, on in enumerate(columns):
        if on and start is None:
            start = i
        elif not on and start is not None:
            found.append((start, i - 1))
            start = None
    if start is not None:
        found.append((start, len(columns) - 1))
    merged = []
    for a, b in found:
        if merged and a - merged[-1][1] <= gap:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    return [((x0 + a) / 2.0, (b - a + 1) / 2.0) for a, b in merged]

def profile(band, x0, x1, thr=60):
    columns = (band[:, x0:x1].max(axis=0) > thr)
    n = len(columns) // BUCKET
    return np.array([columns[i * BUCKET:(i + 1) * BUCKET].any() for i in range(n)], dtype=bool)

def drift_of(x0, x1):
    a, b = profile(reference, x0, x1), profile(port, x0, x1)
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    best = (0, 1.0)
    span = int(round(tol_pos * 2 / (BUCKET / 2))) + 2
    for shift in range(-span * 2, span * 2 + 1):
        if shift >= 0:
            x, y = a[shift:], b[:n - shift] if shift else b
        else:
            x, y = a[:n + shift], b[-shift:]
        if len(x) == 0 or len(y) == 0:
            continue
        mismatch = float(np.mean(x != y))
        if mismatch < best[1]:
            best = (shift, mismatch)
    return best[0] * (BUCKET / 2.0), best[1]

windows = {"left": (0, int(w * 0.45)), "right": (int(w * 0.92), w)}
report, rows, failures = [], [], []

for name, (x0, x1) in windows.items():
    drift, mismatch = drift_of(x0, x1)
    ref_runs, port_runs = runs(reference, x0, x1), runs(port, x0, x1)
    if abs(drift) > tol_pos:
        failures.append(f"{name}: drift {drift:+.0f} logical px (tolerance {tol_pos})")
    # пары иконок гейтятся только там, где данные не участвуют
    pairs = []
    if name == "right":
        if len(ref_runs) != len(port_runs):
            failures.append(f"{name}: the reference draws {len(ref_runs)} icons, the port {len(port_runs)}")
        for i, ((rx, rw), (px, pw)) in enumerate(zip(ref_runs, port_runs)):
            dx, dw = round(px - rx, 1), round(pw - rw, 1)
            pairs.append((i, rx, px, dx, dw))
            if abs(dx) > tol_pos or abs(dw) > tol_w:
                failures.append(f"{name}[{i}]: Δx {dx:+} Δw {dw:+} (reference {rx:.0f}/{rw:.0f}, port {px:.0f}/{pw:.0f})")
    else:
        for i, ((rx, rw), (px, pw)) in enumerate(zip(ref_runs, port_runs)):
            pairs.append((i, rx, px, round(px - rx, 1), round(pw - rw, 1)))
    report.append({
        "window": name, "drift": round(drift, 1), "ink_diff_pct": round(mismatch * 100, 1),
        "runs_ref": len(ref_runs), "runs_port": len(port_runs), "gated_pairs": name == "right",
    })
    rows.append((name, drift, mismatch, len(ref_runs), len(port_runs), pairs))

if as_json:
    print(json.dumps({"windows": report, "failures": failures}, indent=2))
else:
    print(f"{'window':7s} {'drift':>7s} {'ink diff':>9s} {'runs ref/port':>14s}  gated")
    for window, drift, mismatch, rr, pr, _ in rows:
        gated = "drift + icon pairs" if window == "right" else "drift"
        print(f"{window:7s} {drift:>+7.1f} {mismatch * 100:>8.1f}% {rr:>7d}/{pr:<6d}  {gated}")
    print()
    print("per-run Δ (logical px, information on the left — gated on the right):")
    print(f"  {'window':7s} {'#':>3s} {'ref x':>6s} {'port x':>6s} {'Δx':>6s} {'Δw':>6s}")
    for window, _, _, _, _, pairs in rows:
        for index, rx, px, dx, dw in pairs:
            print(f"  {window:7s} {index:>3d} {rx:>6.0f} {px:>6.0f} {dx:>+6.1f} {dw:>+6.1f}")
    print()
    for failure in failures:
        print("FAIL " + failure)
    print("parity-clusters: " + ("OK" if not failures else f"{len(failures)} check(s) out of tolerance"))

sys.exit(0 if not failures else 1)
PY
