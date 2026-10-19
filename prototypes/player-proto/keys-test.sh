#!/usr/bin/env bash
# End-to-end test of the keyboard state machine against the user's own rmpc bindings
# (~/.config/rmpc/config.ron): tokens go through the same handler a real keyboard hits,
# the MPD worker runs with PLAYER_DRY_RUN=1 so playback is never touched, and every step
# prints a [state] line that this script asserts on.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${PROTO_BIN:-$here/target/release/player}
[ -s "$here/.libs" ] || "$here/libs.sh" > "$here/.libs"
keys="down,down,tab,tab,tab,slash,abc,esc,colon,vol 30,enter,w,esc,5,j,p,>,<,f,b,=,-,z,r,y,R,d,d,colon,save ktl,enter,colon,renameplaylist ktl ktl2,enter,colon,rmplaylist ktl2,enter,J,K,2,noop,noop,noop,noop,3,noop,noop,noop,noop,P,noop,noop,noop,noop,1,a,noop,noop,noop,noop,enter,ctrl+s,esc,o,noop,noop,down,enter,esc"
out=$(mktemp)
wide=$(mktemp)
hitslog=$(mktemp)
hoverlog=$(mktemp)
trap 'rm -f "$out" "$wide" "$hitslog" "$hoverlog"' EXIT
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --render-size=800x600 --shot-seq=/tmp/keys-test --keys="$keys" > "$out" 2>&1
# Pane focus (which drives the elevation of the panes) depends on the layout width: the library
# pane exists only at >= 1080 logical units, and only then does its tab take the keys. The main
# run is deliberately narrow, so a second, wide run is what exercises the library case.
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --render-size=1440x900 --shot-seq=/tmp/keys-focus --keys="tab,noop,tab" > "$wide" 2>&1
# Hover: the frame resolves the pointer against the previous frame's hit rectangles. Rather than
# hard-coding coordinates that drift with every layout change, the first run dumps those
# rectangles (PLAYER_DUMP_HITS=1) and the second run parks the pointer in the middle of the ones
# the test cares about. Both runs share the 1440 layout, where the now-playing column exists.
PLAYER_DUMP_HITS=1 PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --render-size=1440x900 --shot=/tmp/keys-hits.ppm --shot-after=150 \
  --keys="noop,o,noop" > "$hitslog" 2>&1
# Targets, in the order the second run will visit them: an empty corner (nothing under the
# pointer), a queue row, a tab, the transport play button, a mode chip, the volume bar and — once
# the overlay is open — an output row.
coords=$(python3 - "$hitslog" << 'PY'
import re, sys
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
) || { echo "FAIL hit rectangles could not be read: $coords"; exit 1; }
read -r row_at tab_at play_at chip_at vol_at out_at <<< "$coords"
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --render-size=1440x900 --shot=/tmp/keys-hover.ppm --shot-after=560 \
  --keys="cursor:2x2,noop,cursor:$row_at,noop,cursor:$tab_at,noop,cursor:$play_at,noop,cursor:$chip_at,noop,cursor:$vol_at,noop,o,noop,cursor:$out_at,noop" \
  > "$hoverlog" 2>&1
python3 - "$out" "$wide" "$hoverlog" << 'PY'
import re, sys
lines = open(sys.argv[1], errors="replace").read().splitlines()
states = [l for l in lines if l.startswith("[state]")]
dry = [l for l in lines if l.startswith("[dry-run]")]

def field(line, name):
    m = re.search(rf"{name}=('([^']*)'|\S+)", line)
    return m.group(2) if m and m.group(2) is not None else (m.group(1) if m else None)

def seq(token, occurrence=0):
    # Prefer the settled dump: it is taken after the worker's replies for this key landed, so
    # assertions do not race the poll loop.
    hits = [s for s in states if f"token={token} " in s]
    settled = [s for s in hits if "settle=1" in s]
    pool = settled or hits
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
check("'o' opens the outputs overlay", oes and field(oes, "outputs") == "true", str(oes))
check("outputs overlay toggles an output", sent("SetOutput"), str([l for l in dry if "SetOutput" in l]))
d_after_o = [s for s in states if "token=down " in s]
check("arrows inside the overlay do not move the queue cursor", d_after_o and field(d_after_o[-1], "outputs") == "true", str(d_after_o[-1:]))

# ---- pane focus (the raised pane). The frame picks its elevation from the same rule, so an
# assertion on `focus` is the cheapest proxy for "the right pane is raised".
wide_states = [
    l for l in open(sys.argv[2], errors="replace").read().splitlines() if l.startswith("[state]")
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
check(
    "at 800 the hidden library pane never takes focus",
    bool(states) and all(field(s, "focus") == "centre" for s in states),
    str([s for s in states if field(s, "focus") != "centre"][:1]),
)

# ---- hover: the pointer is parked in the middle of each dumped rectangle, so these checks
# prove that the rectangle the user sees is the rectangle that answers the pointer. The script
# alternates a `cursor:` move with a `noop` (so the frame that follows the move is drawn and
# dumped), which leaves one settled state per visited target at every second position.
hover_states = [
    l for l in open(sys.argv[3], errors="replace").read().splitlines() if l.startswith("[state]")
]
settled_hover = [field(s, "hover") for s in hover_states if "settle=1" in s]
visited = settled_hover[::2]
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
for index, (name, want) in enumerate(want_hover):
    got = visited[index] if index < len(visited) else "<no dump>"
    check(name, got == want, f"got {got} want {want}")
check(
    "hovering never moves the selection",
    bool(hover_states) and all(field(s, "sel") == "0" for s in hover_states),
    str([s for s in hover_states if field(s, "sel") != "0"][:1]),
)
sys.exit(1 if fails else 0)
PY
