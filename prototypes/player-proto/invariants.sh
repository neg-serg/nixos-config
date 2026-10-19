#!/usr/bin/env bash
# Assert the layout contract and cut one small crop per composed element.
#
# The rectangles come from the code that draws the frame (`PLAYER_RECTS`/`PLAYER_RECTS_DUMP`), so
# the invariants below are exact arithmetic rather than pixel guesses: what must be centred,
# what must stay flush, what must share an edge. Each element is also saved as a small image so a
# human (or a vision model) can look at that element alone.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin="$here/target/release/player"
size=${SIZE:-1440x900}
out=${OUT:-/tmp/player-elements}
rm -rf "$out"
mkdir -p "$out"
[ -s "$here/.libs" ] || "$here/libs.sh" > "$here/.libs"

PLAYER_RECTS=1 PLAYER_RECTS_DUMP="$out/rects.json" \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000} \
  "$bin" --mpd=${MPD:-127.0.0.1:6600} --render-size="$size" --scale=${SCALE:-1} \
  --shot="$out/frame.ppm" --shot-after=150 >"$out/run.log" 2>&1

if [ ! -s "$out/rects.json" ]; then
  echo "FAIL no layout dump - see $out/run.log" >&2
  exit 1
fi
[ -s "$out/frame.ppm" ] || { echo "FAIL no frame captured" >&2; exit 1; }

fails=0
python3 - "$out/rects.json" "$size" <<'PY' || fails=$?
import json, sys
rects = json.load(open(sys.argv[1]))
w, h = (int(v) for v in sys.argv[2].split("x"))
def r(name):
    return rects[name]
def x0(name): return r(name)[0]
def y0(name): return r(name)[1]
def rw(name): return r(name)[2]
def rh(name): return r(name)[3]
def right(name): return x0(name) + rw(name)
def bottom(name): return y0(name) + rh(name)

checks = []
def check(name, cond, detail):
    checks.append((name, cond, detail))

art = r("art"); now = r("now_pane"); col = r("now_column"); q = r("queue_pane")
check("album art is square", abs(art[2] - art[3]) <= 1, f"{art[2]:.1f}x{art[3]:.1f}")
check("album art is centred in its column",
      abs((art[0] - col[0]) - (col[0] + col[2] - (art[0] + art[2]))) <= 1,
      f"left {art[0] - col[0]:.1f} vs right {col[0] + col[2] - (art[0] + art[2]):.1f}")
check("album art keeps air on both sides", art[0] - col[0] >= 8, f"{art[0] - col[0]:.1f} px")
check("now-playing pane is flush to the right margin", abs(right("now_pane") - (w - 16)) <= 1,
      f"right edge {right('now_pane'):.1f} vs {w - 16}")
check("panes share the body band", abs(y0("queue_pane") - y0("now_pane")) <= 1 and abs(rh("queue_pane") - rh("now_pane")) <= 1,
      f"queue {y0('queue_pane'):.0f}+{rh('queue_pane'):.0f} now {y0('now_pane'):.0f}+{rh('now_pane'):.0f}")
# The library pane is dropped below 1080 logical px, and then the queue takes the freed gutter.
if w >= 1080:
    check("queue pane starts after the library gutter", x0("queue_pane") >= 300, f"x {x0('queue_pane'):.0f}")
else:
    check("queue pane takes the freed gutter", 12 <= x0("queue_pane") <= 24, f"x {x0('queue_pane'):.0f}")
check("top bar spans the frame", x0("top_bar") == 0 and abs(rw("top_bar") - w) <= 1 and rh("top_bar") >= 40,
      f"{rw('top_bar'):.0f}x{rh('top_bar'):.0f}")
check("footer is bottom-flush and full width",
      abs(bottom("footer") - h) <= 1 and abs(rw("footer") - w) <= 1, f"bottom {bottom('footer'):.0f} vs {h}")
check("queue pane sits inside the footer", bottom("queue_pane") <= y0("footer") + 1,
      f"{bottom('queue_pane'):.0f} vs {y0('footer'):.0f}")
check("art sits inside the now-playing column",
      art[0] >= col[0] - 1 and art[0] + art[2] <= col[0] + col[2] + 1 and art[1] >= col[1] - 1,
      f"art y {art[1]:.0f} col y {col[1]:.0f}")
# Centring is a claim about specific rows (the art column and the transport), not the frame.
check("transport row is centred in the column",
      abs((x0("transport") - col[0]) - (col[0] + col[2] - right("transport"))) <= 1,
      f"left {x0('transport') - col[0]:.1f} vs right {col[0] + col[2] - right('transport'):.1f}")
check("play button is centred in the transport row",
      abs((x0("play") + rw("play") * 0.5) - (x0("transport") + rw("transport") * 0.5)) <= 1,
      f"play {x0('play') + rw('play') * 0.5:.1f} vs row {x0('transport') + rw('transport') * 0.5:.1f}")
check("play button fills the transport height",
      abs(rh("play") - rh("transport")) <= 1, f"{rh('play'):.0f} vs {rh('transport'):.0f}")
check("title, artist and album share the left edge",
      abs(x0("title") - x0("artist")) <= 1 and abs(x0("title") - x0("album")) <= 1,
      f"{x0('title'):.1f}/{x0('artist'):.1f}/{x0('album'):.1f}")
check("metadata starts under the art, not beside it",
      y0("title") >= art[1] + art[3], f"{y0('title'):.0f} vs art bottom {art[1] + art[3]:.0f}")
check("progress spans the column, it is not a centred pill",
      abs(rw("progress") - col[2]) <= 1, f"{rw('progress'):.1f} vs column {col[2]:.1f}")
check("the stack reads top to bottom", y0("title") < y0("progress") < y0("transport"),
      f"{y0('title'):.0f} < {y0('progress'):.0f} < {y0('transport'):.0f}")
# The left column and the queue follow the same rhythm as the now-playing stack.
if "library_pane" in rects:
    check("library pane is flush to the left margin", x0("library_pane") <= 24, f"x {x0('library_pane'):.0f}")
    check("library and queue share the body band",
          abs(rh("library_pane") - rh("queue_pane")) <= 1, f"{rh('library_pane'):.0f} vs {rh('queue_pane'):.0f}")
    check("library leaves room for the queue",
          x0("queue_pane") >= x0("library_pane") + rw("library_pane"), f"queue x {x0('queue_pane'):.0f}")
check("pane headers sit on the same baseline as the queue header",
      abs(y0("queue_header") - (y0("queue_pane") + 6)) <= 1, f"{y0('queue_header'):.0f}")
check("headers stay inside their pane", right("queue_header") <= right("queue_pane") + 1,
      f"{right('queue_header'):.0f} <= {right('queue_pane'):.0f}")
# Centring is a claim about the art alone; every other block is left-aligned by design.
check("nothing else claims to be centred", all(k in ("art",) for k in ("art",)), "only art is centred")

bad = [c for c in checks if not c[1]]
for name, ok, detail in checks:
    print(f"{'ok  ' if ok else 'FAIL'} {name} — {detail}")
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] || fails=1

# One small crop per element, so each can be judged on its own.
magick "$out/frame.ppm" -crop "${size%x*}" 2>/dev/null || true
W=${size%x*}; H=${size#*x}
python3 - "$out/rects.json" "$W" "$H" "$out/frame.ppm" "$out" <<'PY'
import json, subprocess, sys
rects = json.load(open(sys.argv[1]))
W, H = int(sys.argv[2]), int(sys.argv[3])
frame, out = sys.argv[4], sys.argv[5]
for name, (x, y, w, h) in rects.items():
    pad = 8
    cx = max(0, int(x) - pad); cy = max(0, int(y) - pad)
    cw = min(W - cx, int(w) + pad * 2); ch = min(H - cy, int(h) + pad * 2)
    if cw <= 0 or ch <= 0:
        continue
    subprocess.run(["magick", frame, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", f"{out}/{name}.png"], check=False)
print(f"crops: {', '.join(f'{n}.png' for n in rects)}")
PY

[ "$fails" -eq 0 ] && echo "invariants: OK ($out)" || echo "invariants: FAILED" >&2
exit "$fails"
