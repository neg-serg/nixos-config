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
plog=$(mktemp)
emptylog=$(mktemp)
metalog=$(mktemp)
qlog=$(mktemp)
stubport=$(mktemp)
metaport=$(mktemp)
queueport=$(mktemp)
trap 'rm -f "$out" "$wide" "$hitslog" "$hoverlog" "$plog" "$emptylog" "$metalog" "$qlog" "$queueport" "$stubport" "$metaport"' EXIT
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
# Playlist management from the pane itself: `c`/`e`/`d`/`A` must reach the same commands as
# `:save`/`:renameplaylist`/`:rmplaylist` (dry-run shows which), must name the playlist under the
# cursor instead of one typed into the command line, and must not fire in other panes. The run
# also cancels a prompt with esc and then presses `c` outside the pane, so both negative cases
# are covered by the same script.
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --render-size=800x600 --shot-seq=/tmp/keys-playlists \
  --keys="P,noop,c,noop,fromui,noop,enter,noop,down,e,noop,renamed,noop,enter,noop,d,noop,d,noop,A,noop,c,esc,noop,1,noop,c,noop" \
  > "$plog" 2>&1
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
  python3 "$here/stub-mpd.py" "$1" "${@:2}" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 100); do [ -s "$1" ] && break; sleep 0.05; done
  echo "$pid"
}
stub_pid=$(start_stub "$stubport")
stub_addr=$(cat "$stubport" 2>/dev/null)
if [ -z "$stub_addr" ]; then
  echo "FAIL the stub MPD server did not start"
  exit 1
fi
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --mpd="127.0.0.1:$stub_addr" --render-size=800x600 --shot-seq=/tmp/keys-empty \
  --keys="2,noop,noop,noop,3,noop,noop,noop,P,noop,noop,noop,o,noop,noop,noop" > "$emptylog" 2>&1
kill "$stub_pid" 2>/dev/null
wait "$stub_pid" 2>/dev/null

meta_pid=$(start_stub "$metaport" --outputs)
meta_addr=$(cat "$metaport" 2>/dev/null)
if [ -z "$meta_addr" ]; then
  echo "FAIL the stub MPD server with outputs did not start"
  exit 1
fi
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --mpd="127.0.0.1:$meta_addr" --render-size=800x600 --shot-seq=/tmp/keys-outs \
  --keys="o,noop,noop,noop,cursor:400x300,noop" > "$metalog" 2>&1
kill "$meta_pid" 2>/dev/null
wait "$meta_pid" 2>/dev/null

# Queue filter: the stub publishes six tracks whose initials never repeat, so a one-letter
# filter can match exactly one row. The run proves the three things that can go wrong — the
# filter is a pane state and not a mode (view stays `queue`, `mode` stays `normal`), the
# cursor keeps a real queue index (`sel=2`, not the filtered position 0), and the keys that
# would otherwise act (`q` quits, `down` moves) go to the filter while it is collecting.
q_pid=$(start_stub "$queueport" --queue)
q_addr=$(cat "$queueport" 2>/dev/null)
if [ -z "$q_addr" ]; then
  echo "FAIL the stub MPD server with a queue did not start"
  exit 1
fi
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --mpd="127.0.0.1:$q_addr" --render-size=800x600 --shot-seq=/tmp/keys-queue \
  --keys="noop,noop,noop,noop,slash,w,noop,enter,noop,down,noop,enter,noop,esc,noop,slash,q,noop,esc,noop" \
  > "$qlog" 2>&1
kill "$q_pid" 2>/dev/null
wait "$q_pid" 2>/dev/null

python3 - "$out" "$wide" "$hoverlog" "$plog" "$emptylog" "$metalog" "$qlog" << 'PY'
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

# ---- playlists: the pane manages the lists it shows. Every assertion below reads the command
# the UI produced (dry-run) and the playlist name the cursor was on (the `pl=` field), so the
# checks follow whatever playlists this MPD happens to hold instead of hard-coding a name.
pl_lines = open(sys.argv[4], errors="replace").read().splitlines()
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
empty_lines = open(sys.argv[5], errors="replace").read().splitlines()
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

meta_lines = open(sys.argv[6], errors="replace").read().splitlines()
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
check(
    "a refused `config` leaves the device empty instead of failing",
    len(real_first) == 5 and real_first[3] == "" and field(real_open[-1], "outs") == "filled",
    f"{real_first} outs={field(real_open[-1], 'outs') if real_open else None}",
)
# ---- queue filter: `/` in the queue pane narrows the rows in place. The stub holds six tracks
# whose initials never repeat, so `w` matches exactly one row — through its *artist* — and the
# cursor has to stay on the real queue index 2, not on the first row of the filtered view.
q_lines = open(sys.argv[7], errors="replace").read().splitlines()
q_states = [l for l in q_lines if l.startswith("[state]")]
q_dry = [l for l in q_lines if l.startswith("[dry-run]")]


def q_seq(token, occurrence=0):
    hits = [s for s in q_states if f"token={token} " in s]
    settled = [s for s in hits if "settle=1" in s]
    pool = settled or hits
    return pool[occurrence] if len(pool) > occurrence else None


loaded = q_seq("noop", 3)
check(
    "the queue pane reports the six rows the stub published",
    loaded is not None and field(loaded, "qlen") == "6" and field(loaded, "qstate") == "filled",
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
sys.exit(1 if fails else 0)
PY
