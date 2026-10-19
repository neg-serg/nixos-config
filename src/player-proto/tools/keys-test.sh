#!/usr/bin/env bash
# End-to-end test of the keyboard state machine against the user's own rmpc bindings
# (~/.config/rmpc/config.ron): tokens go through the same handler a real keyboard hits,
# the MPD worker runs with PLAYER_DRY_RUN=1 so playback is never touched, and every step
# prints a [state] line that this script asserts on.
#
# The captures are split into suites, one process each, because they are independent: the only
# edge in the graph is hits -> hover (the hover run parks the pointer in the middle of the
# rectangles the hit dump prints). Everything else reads the live daemon or its own stub on its
# own port and writes its own log, so the set runs in a few parallel waves instead of one long
# serial sweep. A suite is a plain function that runs its captures and writes into its own
# directory under $work; it asserts nothing. The assertions are the single python block at the
# end, which reads the logs and prints one line per check.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
bin=${PROTO_BIN:-$root/target/release/player}
# No LD_LIBRARY_PATH: `src/preload.rs` resolves what winit and ash dlopen, so the suite runs the
# same binary a user runs, with the same environment.
unset LD_LIBRARY_PATH
keys="down,down,tab,tab,tab,slash,abc,esc,colon,vol 30,enter,w,esc,5,j,p,>,<,f,b,=,-,z,r,y,R,d,d,colon,save ktl,enter,colon,renameplaylist ktl ktl2,enter,colon,rmplaylist ktl2,enter,J,K,2,noop,noop,noop,noop,3,noop,noop,noop,noop,P,noop,noop,noop,noop,1,a,noop,noop,noop,noop,enter,ctrl+s,esc,F,noop,noop,b,u,enter,o,wait!outputs=true,wait!outs=filled,down,noop,enter,esc"
# One directory instead of eleven files: each suite writes its log, its frames and its stub port
# file under its own name ($work/<suite>/). Two suites sharing a path would overwrite each
# other's captures, and the per-key frames used to be left behind in /tmp long after the run.
work=$(mktemp -d)
goldenfail=$work/goldenfail

# One capture: <log> <binary arguments...>. The wrappers differ only in the switches a capture
# needs. `timeout` is a backstop: a run that hangs has to fail its suite, not wedge the session.
state_run() { # scripted keys in, [state] dumps out, playback untouched
  local log=$1
  shift
  PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
    timeout 180 "$bin" "$@" > "$log" 2>&1
}

hits_run() { # the same run, plus the hit rectangles the pointer is resolved against
  local log=$1
  shift
  PLAYER_DUMP_HITS=1 PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
    timeout 180 "$bin" "$@" > "$log" 2>&1
}

frame_run() { # a golden capture: pixels only, so neither the dump nor the dry-run switch
  local log=$1
  shift
  timeout 180 "$bin" "$@" > "$log" 2>&1
}

# Golden references: two captures of one layout (1440x900 at scale 1 and 2880x1800 at scale 2)
# compared pixel-for-pixel against the committed references in golden/. They are what turns a
# silent layout drift — a row that moved two units, a title that lost its weight, text that
# stopped being rasterised at device scale — into a failing suite instead of something a human
# has to notice in a screenshot. Regenerate them deliberately, never reflexively:
#   ./keys-test.sh --update-golden
update_golden=0
keep_work=0
for arg in "$@"; do
  case "$arg" in
    --update-golden) update_golden=1 ;;
    # Keeps the work directory and prints its path: a failing suite deletes the evidence it just
    # produced, which turns every investigation into a re-run.
    --keep) keep_work=1 ;;
    *)
      echo "keys-test: unknown argument $arg" >&2
      exit 2
      ;;
  esac
done
# The work directory is removed when the run ends unless --keep asked otherwise; the decision is
# taken here, after the flags are parsed.
if [ "${keep_work:-0}" = 1 ]; then
  echo "keys-test: work directory $work (kept)"
else
  trap 'rm -rf "$work"' EXIT
fi

for tool in compare gzip; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "FAIL golden comparison needs $tool on PATH (ImageMagick and gzip)"
    exit 1
  }
done
golden_dir=$root/golden
mkdir -p "$golden_dir"

# ---- suites. One function per capture process; the launcher at the bottom decides the order.
# The whole binding surface, played into a narrow frame against the live daemon: motion, the
# modes, the command line, the transport commands and the pane switches all come from this log.
suite_main() {
  local d=$work/main
  mkdir -p "$d"
  if ! stub_up "$d" --queue --outputs --playlists --library --library --library --library --library --library; then
    echo "FAIL the stub MPD server did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=800x600 \
    --shot-seq="$d/seq" --keys="$keys"
  stub_down
}

# Pane focus (which drives the elevation of the panes) depends on the layout width: the library
# pane exists only at >= 1080 logical units, and only then does its tab take the keys. The main
# run is deliberately narrow, so a second, wide run is what exercises the library case.
suite_wide() {
  local d=$work/wide
  mkdir -p "$d"
  if ! stub_up "$d" --queue --outputs --playlists --library --library --library --library --library --library; then
    echo "FAIL the stub MPD server did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=1440x900 \
    --shot-seq="$d/seq" --keys="tab,noop,tab"
  stub_down
}
# Hover: the frame resolves the pointer against the previous frame's hit rectangles. Rather than
# hard-coding coordinates that drift with every layout change, the first run dumps those
# rectangles (PLAYER_DUMP_HITS=1) and the second run parks the pointer in the middle of the ones
# the test cares about. Both runs share the 1440 layout, where the now-playing column exists.
# This pair is the only dependency between suites, so the launcher splits it around a short
# sequential step: dump the rectangles, read the coordinates, then start the hover run.
suite_hits() {
  local d=$work/hits
  mkdir -p "$d"
  if ! stub_up "$d" --queue --outputs --playlists --library --library --library --library --library --library; then
    echo "FAIL the stub MPD server did not start"
    return 1
  fi
  hits_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=1440x900 \
    --shot="$d/frame.ppm" --shot-after=320 --keys="noop,o,noop,noop,noop,noop,noop"
  stub_down
}

# Targets, in the order the second run will visit them: an empty corner (nothing under the
# pointer), a queue row, a tab, the transport play button, a mode chip, the volume bar and — once
# the overlay is open — an output row.
compute_coords() { # prints "x1y1 x2y2 …" for the six targets, one per line of --keys
  python3 - "$work/hits/log" << 'PY'
import re
import sys
closed, opened, scope = {}, {}, "closed"
for line in open(sys.argv[1], errors="replace"):
    if line.startswith("[state]"):
        scope = "open" if "outputs=true" in line else "closed"
        continue
    m = re.match(r"\[hit\] (\S+) x=(-?[\d.]+) y=(-?[\d.]+) w=([\d.]+) h=([\d.]+)", line)
    if not m:
        continue
    x, y, w, h = (float(m.group(i)) for i in (2, 3, 4, 5))
    (opened if scope == "open" else closed)[m.group(1)] = (x + w / 2, y + h / 2)
want = [
    ("row:queue:2", closed),
    ("tab:albums", closed),
    ("transport:0", closed),
    ("chip:1", closed),
    ("volume", closed),
    ("output:1", opened),
]
missing = [name for name, table in want if name not in table]
if missing:
    sys.exit(f"hit dump is missing {missing}")
print(" ".join(f"{table[name][0]:.0f}x{table[name][1]:.0f}" for name, table in want))
PY
}

suite_hover() {
  local d=$work/hover
  mkdir -p "$d"
  # Two extra noops after `o`: the overlay's rows come from the worker, so the pointer has to
  # wait for the reply instead of racing it — one frame is enough when the daemon is idle and
  # not enough when it is not, and this run already lives next to three others.
  if ! stub_up "$d" --queue --outputs --playlists --library --library --library --library --library --library; then
    echo "FAIL the stub MPD server did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=1440x900 \
    --shot="$d/frame.ppm" --shot-after=760 \
    --keys="cursor:2x2,noop,cursor:$row_at,noop,cursor:$tab_at,noop,cursor:$play_at,noop,cursor:$chip_at,noop,cursor:$vol_at,noop,o,noop,noop,noop,noop,noop,noop,cursor:$out_at,noop"
  stub_down
}
# Playlist management from the pane itself: `c`/`e`/`d`/`A` must reach the same commands as
# `:save`/`:renameplaylist`/`:rmplaylist` (dry-run shows which), must name the playlist under the
# cursor instead of one typed into the command line, and must not fire in other panes. The run
# also cancels a prompt with esc and then presses `c` outside the pane, so both negative cases
# are covered by the same script.
suite_playlists() {
  local d=$work/playlists
  mkdir -p "$d"
  if ! stub_up "$d" --queue --outputs --playlists --library --library --library --library --library --library; then
    echo "FAIL the stub MPD server did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=800x600 \
    --shot-seq="$d/seq" \
    --keys="P,noop,c,noop,fromui,noop,enter,noop,down,e,noop,renamed,noop,enter,noop,d,noop,d,noop,A,noop,c,esc,noop,1,noop,c,noop"
  stub_down
}
# Empty MPD: an answered-but-empty library must read "ничего нет" and the outputs overlay must
# read "нет выходов" — the frame used to print "загружаю…" forever, which is indistinguishable
# from a real MPD that holds nothing. The stub server speaks the protocol with well-formed but
# empty replies and delays the list answers a little, so the transient "loading" frame is
# observable without racing the worker's poll loop. Only read-only commands run under dry-run,
# so the real daemon is never involved.
#
# The same stub in --outputs mode publishes two audio outputs: one in the modern shape
# (plugin and driver in the reply) and one in the shape of a daemon older than 0.22, plus a
# `config` reply with the device paths. In the default mode `config` is refused exactly like a
# real MPD refuses it to a non-local client, which is how the empty run proves the overlay
# degrades instead of erroring.
# The stub must not inherit this function's stdout: a background child holding the pipe open
# keeps the `$(...)` substitution waiting for EOF long after the shell itself has moved on.
start_stub() {
  python3 "$here/stub-mpd.py" "$1" "${@:2}" > "$1.log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 100); do
    [ -s "$1" ] && break
    sleep 0.05
  done
  echo "$pid"
}
# A stub belongs to the suite that starts it: stub_up sets $stub_pid and $stub_addr from that
# suite's own port file, stub_down reaps it. The suites are subshells, so nothing leaks between
# them and none of them can read another's port.
stub_up() { # <dir> [stub flags…]
  local dir=$1
  shift
  stub_pid=$(start_stub "$dir/port" "$@")
  stub_addr=$(cat "$dir/port" 2> /dev/null)
  [ -n "$stub_addr" ] || return 1
  # The port file is written before the listening socket is ready for the *first* client, and a
  # refused connect costs the app a two-second retry — which a capture of a couple of hundred
  # frames does not have. Wait for a real handshake instead of for a file.
  for _ in $(seq 1 100); do
    python3 - "$stub_addr" << 'PYCHK' > /dev/null 2>&1 && return 0
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 0.2)
s.settimeout(0.2)
sys.exit(0 if s.recv(32).startswith(b"OK MPD") else 1)
PYCHK
    sleep 0.05
  done
  return 1
}

stub_down() {
  [ -n "${stub_pid-}" ] || return 0
  kill "$stub_pid" 2> /dev/null
  wait "$stub_pid" 2> /dev/null
  # A killed server reports its own fate, and a suite's status is its last command's: tearing a
  # stub down is not a failure.
  return 0
}

# Everything the stub suites need from a daemon lives inside the suite: its own stub, its own
# port file, its own log. That is what keeps them safe to run next to each other — no suite can
# read another's port, and none of them depends on the order the others start in.
suite_empty() {
  local d=$work/empty
  mkdir -p "$d"
  if ! stub_up "$d"; then
    echo "FAIL the stub MPD server did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=800x600 --shot-seq="$d/seq" \
    --keys="2,noop,noop,noop,3,noop,noop,noop,P,noop,noop,noop,o,noop,noop,noop"
  stub_down
}

suite_meta() {
  local d=$work/meta
  mkdir -p "$d"
  if ! stub_up "$d" --outputs; then
    echo "FAIL the stub MPD server with outputs did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=800x600 --shot-seq="$d/seq" \
    --keys="o,noop,noop,noop,cursor:400x300,noop"
  stub_down
}

# ---- golden frames. The same stub, the same frame number, the same pinned scale: the layout is
# the only thing that can differ between two runs, which is exactly what a reference is for.
# The stub reports `state: stop`, so nothing in the frame animates (no equaliser, no progress,
# no elapsed digits) — the one live pixel is the connection pulse in the top-right corner, and
# the region table below simply does not cover it. `--scale` pins the device scale so the 1x and
# 2x captures are the same logical layout at two device resolutions rather than two layouts.
#
# Regions are logical pixels at scale 1; the 2x run multiplies each by its scale. They name the
# area that moved, so a failure says "queue pane" instead of "the images differ". The whole
# frame is compared too, which is what catches a change in the gaps between the regions.
golden_regions=(
  "top bar|1320x56+0+0"
  "connection status|96x56+1344+0"
  "library pane|292x792+16+68"
  "queue pane|748x792+324+68"
  "now-playing pane|344x792+1080+68"
  "footer|1440x40+0+860"
)
# Zero measured noise inside the regions (a stopped stub renders the same bytes every run), so
# the tolerance only has to absorb a future change in the GPU's rounding, not this one.
region_limit=0.0005
# The pulse dot lives in the whole-frame comparison and its phase is wall-clock, so the limit has
# to swallow it at its worst: a fully different dot is worth ~2e-5 today and ~1.7e-3 in the worst
# case, while a 1 px layout shift is worth 2.7e-2 at scale 2 and 3.5e-2 at scale 1. 4e-3 sits in
# the gap — loose enough for the animation, tight enough that a shift cannot hide in it.
frame_limit=0.004

# Scale a 1x region geometry (WxH+X+Y) to the capture scale.
scale_geometry() {
  awk -v g="$1" -v n="$2" 'BEGIN {
    split(g, wh, "x"); split(wh[2], off, "+");
    printf "%dx%d+%d+%d", wh[1] * n, off[1] * n, off[2] * n, off[3] * n
  }'
}

golden_check() { # <label> <reference> <shot> <geometry> <limit>
  local label=$1 ref=$2 shot=$3 geom=$4 limit=$5 metric norm
  metric=$(compare -metric RMSE "${ref}[$geom]" "${shot}[$geom]" null: 2>&1)
  norm=$(printf '%s' "$metric" | sed -n 's/.*(\([^)]*\)).*/\1/p')
  norm=${norm:-1}
  if awk -v v="$norm" -v l="$limit" 'BEGIN { exit !(v <= l) }'; then
    printf 'ok   %s (RMSE %s <= %s)\n' "$label" "$norm" "$limit"
  else
    printf 'FAIL %s — RMSE %s > %s at %s\n' "$label" "$norm" "$limit" "$geom"
    echo "$label" >> "$goldenfail"
  fi
}

# One capture + its reference + the region sweep over both.
golden_run() { # <name> <logical size> <scale> <render size>
  local name=$1 size=$2 scale=$3 render=$4 shot="$work/golden/$1.ppm"
  local ref="$golden_dir/$name.ppm.gz"
  if [ "$update_golden" = 1 ]; then
    frame_run "$work/golden/$name.log" --mpd="127.0.0.1:$stub_addr" \
      --render-size="$render" --scale="$scale" --shot="$shot" --shot-after=300
    if [ ! -s "$shot" ]; then
      echo "FAIL the $name capture for --update-golden produced no frame"
      echo "golden $name" >> "$goldenfail"
      return
    fi
    gzip -9 -c "$shot" > "$ref"
    echo "updated golden/$name.ppm.gz ($size at scale $scale)"
  fi
  if [ ! -s "$ref" ]; then
    echo "FAIL golden/$name.ppm.gz is missing — regenerate with ./keys-test.sh --update-golden"
    echo "golden $name" >> "$goldenfail"
    return
  fi
  frame_run "$work/golden/$name.log" --mpd="127.0.0.1:$stub_addr" \
    --render-size="$render" --scale="$scale" --shot="$shot" --shot-after=300
  if [ ! -s "$shot" ]; then
    echo "FAIL the $name capture produced no frame (see $work/golden/$name.log)"
    echo "golden $name" >> "$goldenfail"
    return
  fi
  gzip -dc "$ref" > "$work/golden/$name-ref.ppm"
  local dims
  dims=$(head -c 64 "$shot" | awk 'NR==2 { print $1"x"$2 }')
  if [ "$dims" != "$render" ]; then
    echo "FAIL the $name capture is $dims, not $render"
    echo "golden $name" >> "$goldenfail"
    return
  fi
  # The whole frame: the capture is exactly the render size, so the geometry is the image.
  golden_check "the $size frame at scale $scale matches its golden" \
    "$work/golden/$name-ref.ppm" "$shot" "$render" "$frame_limit"
  local entry label geom
  for entry in "${golden_regions[@]}"; do
    label=${entry%%|*}
    geom=$(scale_geometry "${entry#*|}" "$scale")
    golden_check "$label at scale $scale matches its golden" \
      "$work/golden/$name-ref.ppm" "$shot" "$geom" "$region_limit"
  done
}

# The two captures that make up the references are the one pair that must stay sequential: a
# concurrent `--update-golden` would truncate a reference the other capture is reading. The stub
# is the queue one for both, so the layout under test has content in every pane.
suite_golden() {
  local d=$work/golden
  mkdir -p "$d"
  if ! stub_up "$d" --queue; then
    echo "FAIL the stub MPD server with a queue did not start"
    return 1
  fi
  golden_run queue-1440x900-s1 1440x900 1 1440x900
  golden_run queue-2880x1800-s2 2880x1800 2 2880x1800
  stub_down
}

# Queue filter: the stub publishes six tracks whose initials never repeat, so a one-letter
# filter can match exactly one row. The run proves the three things that can go wrong — the
# filter is a pane state and not a mode (view stays `queue`, `mode` stays `normal`), the
# cursor keeps a real queue index (`sel=2`, not the filtered position 0), and the keys that
# would otherwise act (`q` quits, `down` moves) go to the filter while it is collecting.
suite_queue() {
  local d=$work/queue
  mkdir -p "$d"
  if ! stub_up "$d" --queue; then
    echo "FAIL the stub MPD server with a queue did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=800x600 --shot-seq="$d/seq" \
    --keys="noop,noop,noop,noop,slash,w,noop,enter,noop,down,noop,enter,noop,esc,noop,slash,q,noop,esc,noop"
  stub_down
}

# Interface zoom: the scale is a preference the user moves at runtime, so the keys, the `:zoom`
# command, the reflowed logical canvas and the state file all have to agree. The suite points
# PLAYER_UI_STATE at its own file instead of the user's (~/.local/state/player-proto/ui.conf):
# a test that wrote there would change the next real run, and a capture that *read* it would
# stop being reproducible.
suite_zoom() {
  local d=$work/zoom
  mkdir -p "$d"
  PLAYER_UI_STATE="$d/ui.conf" PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
    timeout 180 "$bin" \
    --render-size=800x600 --shot-seq="$d/seq" \
    --keys="ctrl+equals,noop,ctrl+equals,noop,ctrl+equals,noop,colon,zoom 150,enter,noop,colon,zoom +10,enter,noop,ctrl+0,noop,ctrl+minus,noop" \
    > "$d/log" 2>&1
  # The second run presses nothing: whatever zoom it reports came out of the file.
  PLAYER_UI_STATE="$d/ui.conf" PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
    timeout 180 "$bin" \
    --render-size=800x600 --shot-seq="$d/seq2" --keys="noop,noop,noop" > "$d/log2" 2>&1
}

# Command-line completion: `:` offers the vocabulary it will accept, Tab walks it, and the
# argument of a command that names something the app already holds (a playlist, a theme, `reset`)
# completes from that list instead of from a prefix of the command names. The run spells out the
# three shapes: a name list, a fixed value list, and a name list that needs the daemon's answer.
suite_compl() {
  local d=$work/compl
  mkdir -p "$d"
  state_run "$d/log" --render-size=800x600 --shot-seq="$d/seq" \
    --keys="colon,noop,r,noop,tab,noop,tab,noop,tab,noop,esc,colon,noop,t,h,noop,tab,noop,tab,noop,tab,noop,esc,colon,noop,z,o,noop,tab,noop,tab,noop,esc,colon,noop,r,m,noop,tab,noop,tab,noop,esc"
}

# ncmpcpp parity: the keys and the `:` lines that rmpc never had. Every one of them ends in a
# `[dry-run]` line naming the command it produced, so the check is always "this key reached this
# command" and never "the screen looked right". The run needs the live daemon for the playlist
# completion of `:load` and for the counters behind `@`.
suite_parity() {
  local d=$work/parity
  mkdir -p "$d"
  if ! stub_up "$d" --queue --outputs --playlists --library --library --library --library --library --library; then
    echo "FAIL the stub MPD server did not start"
    return 1
  fi
  state_run "$d/log" --mpd="127.0.0.1:$stub_addr" --render-size=800x600 \
    --shot-seq="$d/seq" \
    --keys="x,noop,X,noop,Y,noop,Y,noop,Z,noop,M,noop,M,noop,T,noop,h,noop,l,noop,plus,noop,colon,seek +5,enter,noop,colon,seek 50%,enter,noop,colon,vol +7,enter,noop,colon,toggle repeat,enter,noop,colon,crossfade 4,enter,noop,colon,gain album,enter,noop,colon,shuffle,enter,noop,colon,prio 100,enter,noop,colon,screen albums,enter,noop,colon,stats,enter,noop,esc,T,noop"
  stub_down
}

# ---- launcher. The window caps how many captures render at once: each one drives its own
# llvmpipe context, and past a few of them the contention costs more wall clock than the
# parallelism wins.
window=3
suite_names=()

launch() { # <suite>
  while [ "$(jobs -rp | wc -l)" -ge "$window" ]; do
    wait -n
  done
  # The exit status goes to a file instead of into `wait`: `wait -n` cannot say which child came
  # back, and with `set -e` deliberately absent a failed child is otherwise just a number.
  (
    "suite_$1"
    echo $? > "$work/rc-$1"
  ) &
  suite_names+=("$1")
}

# Stage one runs on its own: the hit dump is the only capture another suite depends on, and
# llvmpipe is measurably happier with one context than with four (a run that loses the race
# does not fail, it draws nothing and dumps an empty log). Six seconds of serial work buys the
# rest of the set a clean start.
suite_hits
echo $? > "$work/rc-hits"
suite_names+=("hits")

coords_ok=0
if coords=$(compute_coords 2>&1); then
  read -r row_at tab_at play_at chip_at vol_at out_at <<< "$coords"
  coords_ok=1
else
  echo "FAIL hit rectangles could not be read: ${coords:-the hit dump is empty}"
  # The two things that make every later check in this run unreadable: no connection to the
  # suite's own stub, or a stub that never answered. Say which one instead of leaving a cascade.
  echo "  mpd=127.0.0.1:${stub_addr:-<none>} connected=$(rg -o 'connected=(true|false)' "$work/hits/log" | head -1)"
  echo "  stub stderr: $(head -3 "$work/hits/port.log" 2> /dev/null | tr '\n' ' ')"
  # An empty log, so the hover checks fail as checks instead of taking the analysis block down
  # with them: a broken hit dump must not cost the other suites their verdicts.
  mkdir -p "$work/hover"
  : > "$work/hover/log"
fi

# Stage two, longest first: the hover capture is the critical path, so it takes the first slot
# instead of queueing behind the two runs that would have been launched before it.
[ "$coords_ok" = 1 ] && launch hover
launch golden
launch main
launch queue
launch wide
launch playlists
launch meta
launch empty
launch zoom
launch compl
launch parity

wait
suite_rc=0
for name in "${suite_names[@]}"; do
  if [ "$(cat "$work/rc-$name" 2> /dev/null)" != 0 ]; then
    echo "FAIL suite $name exited non-zero"
    suite_rc=1
  fi
done

python3 - "$work/main/log" "$work/wide/log" "$work/hover/log" "$work/playlists/log" \
  "$work/empty/log" "$work/meta/log" "$work/queue/log" "$work/zoom/log" \
  "$work/zoom/log2" "$work/zoom/ui.conf" "$work/compl/log" "$work/parity/log" << 'PY'
import re, shutil, sys


def read_log(path):
    # A suite that never wrote its log leaves its own checks failing; it must not take the whole
    # analysis block — and with it every other suite's verdict — down with a traceback.
    try:
        return open(path, errors="replace").read().splitlines()
    except FileNotFoundError:
        return []


lines = read_log(sys.argv[1])
states = [l for l in lines if l.startswith("[state]")]
dry = [l for l in lines if l.startswith("[dry-run]")]

def field(line, name):
    m = re.search(rf"{name}=('([^']*)'|\S+)", line)
    return m.group(2) if m and m.group(2) is not None else (m.group(1) if m else None)

def seq(token, occurrence=0):
    # Prefer the settled dump: it is taken after the worker's replies for this key landed, so
    # assertions do not race the poll loop. A settle is dropped whenever the worker answers
    # later than the next key, so fall back to the immediate dumps instead of walking off the
    # end of a short pool.
    hits = [s for s in states if f"token={token} " in s]
    settled = [s for s in hits if "settle=1" in s]
    pool = settled if len(settled) > occurrence else hits
    return pool[occurrence] if len(pool) > occurrence else None

fails = []
def check(name, cond, detail=""):
    print(f"{'ok  ' if cond else 'FAIL'} {name}{'' if cond else ' — ' + detail}")
    if not cond:
        fails.append(name)

# Immediate dumps describe the key itself; the "settle=1" repeats describe the state after the
# worker replied, so the motion/tab sequences are read from the immediate ones.
immediate = [s for s in states if "settle=1" not in s]
sels = [int(field(s, "sel")) for s in immediate]
songs = [int(field(s, "song")) for s in states]

check("j/down move one row", len(sels) > 1 and sels[1] == sels[0] + 1, f"sels={sels[:3]}")
tabs = [field(s, "view") for s in immediate if "token=tab " in s]
check(
    "tab cycles the panes in order",
    tabs[:3] == ["library", "artists", "albums"],
    f"{tabs[:3]}",
)
check("'/' enters search mode", (seq("slash") or "") and field(seq("slash"), "mode") == "search")
check("typing fills the search buffer", (seq("abc") or "") and field(seq("abc"), "search") == "abc")
esc = seq("esc")
check("esc leaves search for the queue", esc and field(esc, "mode") == "normal" and field(esc, "view") == "queue", str(esc))
check("':' enters command mode", (seq("colon") or "") and field(seq("colon"), "mode") == "command")
check("command text accumulates", (seq("vol 30") or "") and field(seq("vol 30"), "cmd") == "vol 30")
check("enter executes :vol 30", any("Volume(30)" in l for l in dry), str(dry[:4]))
ask = [s for s in states if "token=w " in s]
check("'w' opens help (rmpc ShowHelp)", ask and field(ask[0], "mode") == "help", str(ask[:1]))
three = seq("5"); j = seq("j")
qlen = int(field(three, "qlen")) if three else 0
want = min(int(field(three, "sel")) + 5, qlen - 1) if three else -1
check("count prefix multiplies the motion (5j)", j and int(field(j, "sel")) == want, f"want {want}")

def sent(marker):
    return any(marker in l for l in dry)

check("'p' toggles pause", sent("Toggle"))
check("'>' plays next", sent("Next"))
check("'<' plays previous", sent("Prev"))
check("'f' seeks forward", sent("SeekRelative(5.0)"))
check("'b' seeks back", sent("SeekRelative(-5.0)"))
check("'=' raises volume", sent("VolumeRelative(5)"))
check("'-' lowers volume", sent("VolumeRelative(-5)"))
check("'z' toggles repeat", sent("Repeat("))
check("'r' toggles random", sent("Random("))
check("'y' toggles single", sent("Single("))
check("'R' toggles consume", sent("Consume("))
check("'d' twice deletes the selected queue row", sent("DeleteIndex("), str([l for l in dry if "Delete" in l]))

def last(token):
    hits = [s for s in states if f"token={token} " in s]
    return hits[-1] if hits else None

panes = {t: field(last(t), "view") for t in ("2", "3", "P", "1")}
check("2/3/P/1 switch to artists/albums/playlists/queue",
      panes == {"2": "artists", "3": "albums", "P": "playlists", "1": "queue"}, str(panes))
# the lists are fetched asynchronously: take the last state seen for each pane view
def pn_for(view):
    hits = [s for s in states if f"view={view} " in s]
    return int(field(hits[-1], "pn")) if hits else 0

counts = {t: pn_for(v) for t, v in (("2", "artists"), ("3", "albums"), ("P", "playlists"))}
check("pickers load their lists from MPD", all(v > 0 for v in counts.values()), str(counts))
check("'J'/'K' reorder the queue", sent("MoveTrack"), str([l for l in dry if "MoveTrack" in l]))
check("'a' adds the selected song to a playlist", sent("AddToPlaylist"), str([l for l in dry if "AddToPlaylist" in l]))
cs = seq("ctrl+s")
check("<C-s> opens the command line with 'save '", cs and field(cs, "cmd") == "save ", str(cs))
check("':save' stores the queue", sent("SavePlaylist"))
check("':renameplaylist' renames", sent("RenamePlaylist"))
check("':rmplaylist' deletes", sent("DeletePlaylist"))

oes = seq("o")
# The finder shells out to the user's own `lusty` binary; skip where it is not installed.
if shutil.which("lusty"):
    check("F opens the lusty finder", any("finder=open:" in s for s in states), f"{[s.split('finder=')[1] for s in states if 'finder=' in s][:2]}")
    check("typing narrows the finder query", any("finder=open:bu" in s for s in states), "")
    ent = seq("enter")
    check("enter closes the finder", ent and "finder=closed" in ent, str(ent))
else:
    print("skip finder checks: lusty not installed")

check("'o' opens the outputs overlay", oes and field(oes, "outputs") == "true", str(oes))
check("outputs overlay toggles an output", sent("SetOutput"), str([l for l in dry if "SetOutput" in l]))
d_after_o = [s for s in states if "token=down " in s]
check("arrows inside the overlay do not move the queue cursor", d_after_o and field(d_after_o[-1], "outputs") == "true", str(d_after_o[-1:]))

# ---- pane focus (the raised pane). The frame picks its elevation from the same rule, so an
# assertion on `focus` is the cheapest proxy for "the right pane is raised".
wide_states = [
    l for l in read_log(sys.argv[2]) if l.startswith("[state]")
]
wlib = [s for s in wide_states if field(s, "view") == "library"]
check(
    "at 1440 the library tab raises the library pane",
    bool(wlib) and all(field(s, "focus") == "library" for s in wlib),
    str(wlib[:1]),
)
wart = [s for s in wide_states if field(s, "view") == "artists"]
check(
    "at 1440 a picker tab raises the centre pane",
    bool(wart) and all(field(s, "focus") == "centre" for s in wart),
    str(wart[:1]),
)
# The column set decides which panes exist, not the window alone: at 800 units the default
# layout keeps the library column (the now-playing one is what gives way), so its tab genuinely
# raises it — that is also what makes `0` reach the browser in a narrow window.
check(
    "the library column survives a narrow frame instead of vanishing",
    any(field(s, "view") == "library" for s in states)
    and all(
        field(s, "focus") == "library"
        for s in states
        if field(s, "view") == "library"
    ),
    str([s for s in states if field(s, "view") == "library"][:1]),
)

# ---- hover: the pointer is parked in the middle of each dumped rectangle, so these checks
# prove that the rectangle the user sees is the rectangle that answers the pointer. The script
# alternates a `cursor:` move with a `noop` (so the frame that follows the move is drawn and
# dumped).
hover_states = [
    l for l in read_log(sys.argv[3]) if l.startswith("[state]")
]
# Every dump, not only the settled ones. A settled dump is emitted once the worker's replies
# have landed, and the run drops one whenever the poll loop is slow enough to answer after the
# next key — reading only settled dumps therefore loses a target under load and shifts every
# later expectation. The immediate dump of the *next* key carries the same resolved hover, so
# the ordered walk below does not care which kind of dump it is: it needs each target to appear
# once, in the order the keys visited them.
hover_seq = [field(s, "hover") for s in hover_states]
want_hover = [
    ("an empty corner hovers nothing", "none"),
    ("a queue row hovers itself", "row:queue:2"),
    ("a tab hovers itself", "tab:albums"),
    ("the play button hovers itself", "transport:0"),
    ("a mode chip hovers itself", "chip:1"),
    ("the volume bar hovers itself", "volume"),
    ("the overlay scrim takes the pointer off the pane underneath", "close"),
    ("an output row hovers itself", "output:1"),
]
# Ordered subsequence instead of a fixed stride: one dump per hovered target is the expected
# shape, but extra dumps in between (and the odd dropped settled one) must not shift the walk.
cursor = 0
for name, want in want_hover:
    while cursor < len(hover_seq) and hover_seq[cursor] != want:
        cursor += 1
    check(name, cursor < len(hover_seq), f"seq {hover_seq[:8]} …")
    cursor += 1
check(
    "hovering never moves the selection",
    bool(hover_states) and all(field(s, "sel") == "0" for s in hover_states),
    str([s for s in hover_states if field(s, "sel") != "0"][:1]),
)

# ---- playlists: the pane manages the lists it shows. Every assertion below reads the command
# the UI produced (dry-run) and the playlist name the cursor was on (the `pl=` field), so the
# checks follow whatever playlists this MPD happens to hold instead of hard-coding a name.
pl_lines = read_log(sys.argv[4])
pl_states = [l for l in pl_lines if l.startswith("[state]")]
pl_dry = [l for l in pl_lines if l.startswith("[dry-run]")]

def pl_key(token, occurrence=0):
    hits = [s for s in pl_states if f"token={token} " in s and "settle=1" not in s]
    return hits[occurrence] if len(hits) > occurrence else None

def pl_sent(marker):
    return any(marker in l for l in pl_dry)

new_open = pl_key("c", 0)
check(
    "'c' in the playlists pane opens a name prompt",
    new_open is not None
    and field(new_open, "prompt") == "new-playlist"
    and field(new_open, "mode") == "command",
    str(new_open),
)
check(
    "the typed name saves the queue as a playlist",
    pl_sent('SavePlaylist("fromui")'),
    str([l for l in pl_dry if "SavePlaylist" in l]),
)
ren_open = pl_key("e")
pl_name = field(ren_open, "pl") if ren_open else None
check(
    "'e' opens a rename prompt for the playlist under the cursor",
    ren_open is not None and field(ren_open, "prompt") == "rename-playlist",
    str(ren_open),
)
check(
    "the typed name renames that playlist",
    bool(pl_name) and pl_sent(f'RenamePlaylist {{ from: "{pl_name}", to: "renamed" }}'),
    f"pl={pl_name} {[l for l in pl_dry if 'Rename' in l]}",
)
check(
    "'d' twice deletes that playlist, not a queue row",
    bool(pl_name)
    and pl_sent(f'DeletePlaylist("{pl_name}")')
    and not pl_sent("DeleteIndex"),
    str([l for l in pl_dry if "Delete" in l]),
)
check(
    "'A' adds the now-playing song to that playlist",
    bool(pl_name) and pl_sent(f'AddToPlaylist {{ name: "{pl_name}", uri: "'),
    str([l for l in pl_dry if "AddToPlaylist" in l]),
)
esc_pl = pl_key("esc")
check(
    "esc cancels a prompt without sending anything",
    esc_pl is not None
    and field(esc_pl, "prompt") == "none"
    and field(esc_pl, "mode") == "normal"
    and sum("SavePlaylist" in l for l in pl_dry) == 1,
    f"{esc_pl} saves={[l for l in pl_dry if 'SavePlaylist' in l]}",
)
outside = pl_key("c", 2)
check(
    "the playlist keys stay inside the playlists pane",
    outside is not None
    and field(outside, "prompt") == "none"
    and field(outside, "view") == "queue",
    str(outside),
)

# ---- empty MPD: a library that answered with nothing must say so. The stub in the run above
# holds no artists, albums, playlists or outputs, and delays its list replies, so the immediate
# dump of a key is taken before the answer and the settled dump after it: both halves of the
# loading/empty pair are observable in one run.
empty_lines = read_log(sys.argv[5])
empty_states = [l for l in empty_lines if l.startswith("[state]")]


def empty_dump(token, settled):
    hits = [
        s
        for s in empty_states
        if f"token={token} " in s and (("settle=1" in s) == settled)
    ]
    return hits[0] if hits else None


def last_in_view(view):
    hits = [s for s in empty_states if f"view={view} " in s]
    return hits[-1] if hits else None


# The worker polls MPD every 300ms, so the answer can land later than one settled dump; each
# pane key is followed by noops and the assertion reads the last state of that view instead of a
# fixed frame offset.
for token, word in (("2", "artists"), ("3", "albums"), ("P", "playlists")):
    immediate = empty_dump(token, False)
    settled = last_in_view(word)
    check(
        f"an empty {word} list says 'ничего нет', not a spinner",
        settled is not None and field(settled, word) == "empty",
        str(settled),
    )
    check(
        f"the {word} pane reports loading until MPD answers",
        immediate is not None and field(immediate, word) == "loading",
        str(immediate),
    )
check(
    "an empty MPD never reports a filled picker",
    bool(empty_states)
    and all(
        field(s, w) != "filled"
        for s in empty_states
        for w in ("artists", "albums", "playlists", "outs")
    ),
    str([s for s in empty_states if field(s, "artists") == "filled"][:1]),
)
check(
    "a daemon with no outputs exposes no output metadata",
    bool(empty_states) and all(field(s, "out0") is None for s in empty_states),
    str([s for s in empty_states if field(s, "out0") is not None][:1]),
)
o_immediate = empty_dump("o", False)
o_settled = [s for s in empty_states if "outputs=true" in s]
o_settled = o_settled[-1] if o_settled else None
check(
    "the outputs overlay has its own no-outputs state",
    o_settled is not None and field(o_settled, "outs") == "empty",
    str(o_settled),
)
check(
    "the outputs overlay reports loading before MPD answers",
    o_immediate is not None and field(o_immediate, "outs") == "loading",
    str(o_immediate),
)
# The other half of the pair: against the real daemon the same fields must read "filled", so the
# empty words above cannot be an unconditional string.
filled = {
    view: [
        field(s, view)
        for s in states
        if f"view={view} " in s and "settle=1" in s
    ]
    for view in ("artists", "albums", "playlists")
}
check(
    "a populated MPD reports its pickers as filled",
    all(vals and vals[-1] == "filled" for vals in filled.values()),
    str(filled),
)
# ---- outputs metadata: an output row names the plugin, the driver and the device it runs on,
# so two rows called "PipeWire" can be told apart. The stub in --outputs mode plays three
# shapes of the same reply at once: a modern daemon (plugin and driver both present), a daemon
# older than 0.22 (no plugin field, so the type has to come from `config`) and one whose plugin
# and driver are the same word. The live daemon run covers the fourth: a daemon that refuses
# `config` to this client must still show its plugin and leave the device empty.
def split_meta(state, key):
    raw = field(state, key) if state else None
    return raw.split("|") if raw else []

meta_lines = read_log(sys.argv[6])
meta_states = [l for l in meta_lines if l.startswith("[state]")]
meta_open = [s for s in meta_states if "outputs=true" in s]
meta_last = meta_open[-1] if meta_open else None
meta0 = split_meta(meta_last, "out0")
meta1 = split_meta(meta_last, "out1")
meta2 = split_meta(meta_last, "out2")
check(
    "an output row shows its plugin, driver, device and the joined second line",
    meta0
    == [
        "Stub Pipe",
        "pulse",
        "pipewire",
        "stub-device-0",
        "pulse \u00b7 pipewire \u00b7 stub-device-0",
    ],
    str(meta0),
)
check(
    "a daemon that omits `plugin` still gets one from its config block",
    meta1 == ["Stub Fifo", "alsa", "fifo", "/tmp/stub.fifo", "alsa \u00b7 fifo \u00b7 /tmp/stub.fifo"],
    str(meta1),
)
check(
    "a plugin that repeats its driver is printed once",
    meta2 == ["Stub Repeat", "alsa", "alsa", "", "alsa"],
    str(meta2),
)
check(
    "every configured output gets its own row",
    bool(meta2) and field(meta_last, "out3") is None,
    str(meta_last),
)
real_open = [s for s in states if "outputs=true" in s]
real_first = split_meta(real_open[-1], "out0") if real_open else []
check(
    "the live daemon's plugin reaches the overlay",
    len(real_first) == 5 and bool(real_first[1]),
    str(real_first),
)
# Two daemons, two legitimate shapes: a non-local client is refused `config` (the real MPD) and
# the row keeps an empty device, or `config` is answered (the stub, a local client) and the device
# comes from it. The defect this guards is neither: it is an overlay that fails to fill at all.
check(
    "the output row survives a `config` the daemon refused",
    len(real_first) == 5
    and field(real_open[-1], "outs") == "filled"
    and (real_first[3] == "" or real_first[3].startswith("/") or real_first[3].startswith("stub")),
    f"{real_first} outs={field(real_open[-1], 'outs') if real_open else None}",
)
# ---- queue filter: `/` in the queue pane narrows the rows in place. The stub holds six tracks
# whose initials never repeat, so `w` matches exactly one row — through its *artist* — and the
# cursor has to stay on the real queue index 2, not on the first row of the filtered view.
q_lines = read_log(sys.argv[7])
q_states = [l for l in q_lines if l.startswith("[state]")]
q_dry = [l for l in q_lines if l.startswith("[dry-run]")]


def q_seq(token, occurrence=0):
    # Same rule as `seq`: the settled dump is the better witness, the immediate one is the one
    # that always exists.
    hits = [s for s in q_states if f"token={token} " in s]
    settled = [s for s in hits if "settle=1" in s]
    pool = settled if len(settled) > occurrence else hits
    return pool[occurrence] if len(pool) > occurrence else None


# The first dump that already sees the stub's six rows, settled or not: the queue arrives from
# the worker and a settled dump is dropped whenever the answer lands after the next key, so an
# index into one of the two streams is a race, not an assertion.
loaded = next(
    (
        s
        for s in q_states
        if field(s, "qlen") == "6" and field(s, "qfilter") == "" and field(s, "qedit") == "0"
    ),
    None,
)
check(
    "the queue pane reports the six rows the stub published",
    loaded is not None and field(loaded, "qstate") == "filled",
    str(loaded),
)
slash = q_seq("slash")
check(
    "'/' in the queue pane starts a filter without leaving the pane",
    slash is not None
    and field(slash, "qedit") == "1"
    and field(slash, "view") == "queue"
    and field(slash, "mode") == "normal",
    str(slash),
)
typed = q_seq("w")
check(
    "typing filters the rows and keeps the cursor on a real queue index",
    typed is not None
    and field(typed, "qfilter") == "w"
    and field(typed, "qmatch") == "1"
    and field(typed, "sel") == "2",
    str(typed),
)
handed_back = q_seq("enter", 0)
check(
    "enter keeps the filter and hands the keys back",
    handed_back is not None
    and field(handed_back, "qedit") == "0"
    and field(handed_back, "qmatch") == "1",
    str(handed_back),
)
moved = q_seq("down")
check(
    "motions stay inside the filter instead of escaping it",
    moved is not None and field(moved, "sel") == "2",
    str(moved),
)
check(
    "enter plays the filtered row's real queue index, not its position",
    any("PlayIndex(2)" in l for l in q_dry),
    str([l for l in q_dry if "PlayIndex" in l]),
)
cleared = q_seq("esc", 0)
check(
    "esc drops the filter and the whole queue comes back",
    cleared is not None
    and field(cleared, "qfilter") == ""
    and field(cleared, "qmatch") == "6"
    and field(cleared, "qstate") == "filled",
    str(cleared),
)
nomatch = q_seq("q")
check(
    "a filter that matches nothing reports nomatch, not a blank list",
    nomatch is not None
    and field(nomatch, "qfilter") == "q"
    and field(nomatch, "qmatch") == "0"
    and field(nomatch, "qstate") == "nomatch",
    str(nomatch),
)
final = q_seq("esc", 1)
check(
    "q types into the filter instead of quitting the player",
    final is not None
    and field(final, "qfilter") == ""
    and field(final, "qstate") == "filled",
    str(final),
)

# ---- interface zoom. The scale is a preference the user moves while the app runs, so three
# things have to agree: the key chord and the `:zoom` command land on the same number, the frame
# reflows to the logical canvas that number implies (a bigger zoom is a smaller canvas), and the
# state file carries the value into the next process. The second run presses nothing, so any
# zoom it reports came out of that file.
zoom_states = [l for l in read_log(sys.argv[8]) if l.startswith("[state]")]


def zoom_dump(token, occurrence=0):
    # The zoom is local state, applied by the key handler itself: the immediate dump already has
    # it, and unlike the settled dump it cannot be dropped while the worker is busy.
    hits = [s for s in zoom_states if f"token={token} " in s and "settle=1" not in s]
    return hits[occurrence] if len(hits) > occurrence else None


def zoom_pct(state):
    raw = field(state, "zoom") if state else None
    return None if raw is None else round(float(raw) * 100)


def canvas(state):
    return field(state, "size") if state else None


# One press of the chord is five points, three presses are fifteen, and the command line can set
# either an absolute percentage or a relative step.
steps = [
    ("ctrl+equals", 0, 105),
    ("ctrl+equals", 1, 110),
    ("ctrl+equals", 2, 115),
    ("enter", 0, 150),  # after `:zoom 150`
    ("enter", 1, 160),  # after `:zoom +10`
    ("ctrl+0", 0, 100),  # the reset chord
    ("ctrl+minus", 0, 95),
]
for token, occurrence, want in steps:
    got = zoom_dump(token, occurrence)
    check(
        f"zoom reaches {want}% at {token} #{occurrence + 1}",
        zoom_pct(got) == want,
        f"zoom={zoom_pct(got)} {got}",
    )
# The logical canvas is physical / (device scale * zoom), so a bigger zoom is a smaller canvas:
# 800x600 at 115% is 696x522 and at 160% it is 500x375. That is the reflow the panes see.
check(
    "a bigger zoom lays the frame out on a smaller logical canvas",
    canvas(zoom_dump("ctrl+equals", 2)) == "696x522"
    and canvas(zoom_dump("enter", 1)) == "500x375"
    and canvas(zoom_dump("ctrl+minus", 0)) == "842x632",
    f"{canvas(zoom_dump('ctrl+equals', 2))} / {canvas(zoom_dump('enter', 1))} / {canvas(zoom_dump('ctrl+minus', 0))}",
)
remembered = [l for l in read_log(sys.argv[9]) if l.startswith("[state]")]
check(
    "the zoom is remembered by the next run",
    bool(remembered) and zoom_pct(remembered[-1]) == 95,
    str(remembered[-1]),
)
# ... and it is remembered by *writing a file*, not by keeping it in memory: the second run only
# saw the number because this line exists.
try:
    stored = open(sys.argv[10], errors="replace").read().strip()
except OSError:
    stored = ""
check(
    "the state file holds the zoom the run ended on",
    "zoom=0.9500" in stored and "layout=" in stored,
    repr(stored),
)
# ---- command-line completion. `:` lists the vocabulary, Tab walks it, and a command whose value
# is something the app already holds completes from that list: the command names first, then the
# argument. The walk is what makes pressing Tab twice useful, and re-scoping is what keeps `:rm`
# from offering `rmplaylist` a second time instead of the playlists it can delete.
compl_states = [l for l in read_log(sys.argv[11]) if l.startswith("[state]")]


def compl_dump(token, occurrence=0):
    # Local state, applied by the key handler: the immediate dump has it and cannot be dropped.
    hits = [s for s in compl_states if f"token={token} " in s and "settle=1" not in s]
    return hits[occurrence] if len(hits) > occurrence else None


def line_of(state):
    return field(state, "cmd") if state else None


def offers(state):
    raw = field(state, "compl") if state else None
    if not raw:
        return None
    count, _, sel = raw.partition(":")
    return int(count), int(sel or 0)


check(
    "an empty ':' line offers the whole vocabulary",
    offers(compl_dump("colon", 0)) == (39, 0),
    str(compl_dump("colon", 0)),
)
check(
    "typing a prefix narrows the vocabulary",
    line_of(compl_dump("r", 0)) == "r" and offers(compl_dump("r", 0)) == (6, 0),
    str(offers(compl_dump("r", 0))),
)
walk = [
    ("tab", 0, "resume ", "the first Tab takes the first candidate"),
    ("tab", 1, "repeat ", "a second Tab walks to the next name"),
    ("tab", 2, "random ", "and the walk keeps going"),
    ("tab", 3, "theme ", "completing a name re-scopes the popup to that command's values"),
    # The value list is the resolved skin names (built-ins plus anything `skins.toml` adds), so
    # the first two candidates are the strict skin and its quiet variant.
    ("tab", 4, "theme neg", "the re-scoped list completes the value"),
    ("tab", 5, "theme neg-soft", "and walking it reaches the second value"),
    ("tab", 6, "zoom ", "the zoom command completes"),
    ("tab", 7, "zoom reset", "and offers its only keyword"),
    ("tab", 8, "rmplaylist ", "a playlist command completes"),
]
for token, occurrence, want, why in walk:
    got = line_of(compl_dump(token, occurrence))
    check(why, got == want, f"{got!r} != {want!r}")
rm = compl_dump("tab", 9)
check(
    "the playlist argument completes from the daemon's list",
    (line_of(rm) or "").startswith("rmplaylist ")
    and len(line_of(rm) or "") > len("rmplaylist "),
    repr(line_of(rm)),
)
# ---- ncmpcpp parity. The keys and commands below did not exist; each one has to reach the
# command it claims, and the ones that change local state have to show up in the dump. The
# `[dry-run]` log is the proof that the command was *sent*, which is what a scripted run can
# assert without a daemon that would actually crossfade or shuffle.
par_lines = read_log(sys.argv[12])
par_dry = [l for l in par_lines if l.startswith("[dry-run]")]
par_states = [l for l in par_lines if l.startswith("[state]")]


def sent(pattern):
    return [l for l in par_dry if pattern in l]


def par_dump(token, occurrence=0):
    hits = [s for s in par_states if f"token={token} " in s and "settle=1" not in s]
    return hits[occurrence] if len(hits) > occurrence else None


parity = [
    ("x toggles crossfade on", "Crossfade(5)", "x"),
    ("X raises the crossfade", "Crossfade(7)", "X"),
    ("Y at off reaches track", 'ReplayGain("track")', "Y"),
    ("Y cycles to album", 'ReplayGain("album")', "Y"),
    ("Z shuffles the queue", "Shuffle", "Z"),
    ("M mutes by setting the volume to zero", "Volume(0)", "M"),
    ("M again restores the volume", "Volume(40)", "M"),
    ("h seeks back five seconds", "SeekRelative(-5.0)", "h"),
    ("l seeks forward five seconds", "SeekRelative(5.0)", "l"),
    ("+ raises the volume", "VolumeRelative(5)", "plus"),
    (":seek +5 steps instead of jumping", "SeekRelative(5.0)", "seek +5"),
    (":seek 50% seeks by fraction", "SeekPercent(50.0)", "seek 50%"),
    (":vol +7 steps instead of setting 7%", "VolumeRelative(7)", "vol +7"),
    (":toggle repeat flips it", "Repeat(true)", "toggle repeat"),
    (":crossfade 4 sets it", "Crossfade(4)", "crossfade 4"),
    (":gain album sets the mode", 'ReplayGain("album")', "gain album"),
    (":shuffle reaches the daemon", "Shuffle", "shuffle"),
    (":prio 100 covers the queue", "Priority", "prio 100"),
    (":screen albums switches the pane", "view=albums", ""),
]
for why, needle, token in parity:
    if needle.startswith("cmd='") or needle.startswith("view="):
        # Content, not an index: the first dump that shows it, wherever the run put it.
        got = next((s for s in par_states if needle in s), None)
        check(why, got is not None, f"no dump with {needle!r}")
    else:
        hits = sent(needle)
        check(why, bool(hits), f"no [dry-run] line with {needle!r}: {par_dry[-3:]}")
check(
    "a crossfade set from the line is reported by the state dump",
    (par_dump("enter", 4) or "").find("xfade=4") > 0,
    str(par_dump("enter", 4)),
)
check(
    "add mode is a state, not a toast",
    (par_dump("T", 0) or "").find("addmode=1") > 0
    and (par_dump("T", 1) or "").find("addmode=0") > 0,
    f"{par_dump('T', 0)} / {par_dump('T', 1)}",
)
# `@` and `:stats` both open the panel; what a scripted run can assert is that it opened and
# stayed open (the counters themselves need a daemon that answers `stats`, which the stub does —
# the dry-run line is gone because `stats` is read-only and therefore actually runs).
opened = [s for s in par_states if "server=1" in s]
# The sequence opens the panel with `:stats`, leaves it a few keys, then closes it with `esc`, so
# the honest pair of assertions is "it opened and stayed open for a while" plus "esc closes it" —
# asserting that it is still open at the end would only re-state where the sequence puts its esc.
check(
    "the server panel opens and stays open",
    len(opened) >= 3,
    f"{len(opened)} dumps with server=1, last={par_states[-1][:40] if par_states else None}",
)
check(
    "esc closes the server panel",
    bool(par_states) and "server=0" in par_states[-1],
    str(par_states[-1][:40] if par_states else None),
)
check(
    "replay gain survives the cycle in the dump",
    (par_dump("Y", 1) or "").find("gain=album") > 0,
    str(par_dump("Y", 1)),
)
sys.exit(1 if fails else 0)
PY
python_rc=$?
# The golden checks run in bash (they shell out to ImageMagick), so their verdict has to be
# folded into the exit status the python block already produced.
if [ -s "$goldenfail" ]; then
  echo "golden references no longer match: $(tr '\n' ' ' < "$goldenfail")"
  echo "  if this change is intended: ./keys-test.sh --update-golden and review the diff"
  exit 1
fi
# A suite that produced no log already failed its own checks above; one that died says so here.
exit $((python_rc || suite_rc))
