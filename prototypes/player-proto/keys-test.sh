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
trap 'rm -f "$out"' EXIT
PLAYER_DUMP_STATE=1 PLAYER_DRY_RUN=1 \
  env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" \
  "$bin" --render-size=800x600 --shot-seq=/tmp/keys-test --keys="$keys" >"$out" 2>&1
python3 - "$out" <<'PY'
import re, sys
lines = open(sys.argv[1], errors="replace").read().splitlines()
states = [l for l in lines if l.startswith("[state]")]
dry = [l for l in lines if l.startswith("[dry-run]")]

def field(line, name):
    m = re.search(rf"{name}=('([^']*)'|\S+)", line)
    return m.group(2) if m and m.group(2) is not None else (m.group(1) if m else None)

def seq(token, occurrence=0):
    hits = [s for s in states if f"token={token} " in s]
    return hits[occurrence] if len(hits) > occurrence else None

fails = []
def check(name, cond, detail=""):
    print(f"{'ok  ' if cond else 'FAIL'} {name}{'' if cond else ' — ' + detail}")
    if not cond:
        fails.append(name)

sels = [int(field(s, "sel")) for s in states]
songs = [int(field(s, "song")) for s in states]

check("j/down move one row", len(sels) > 1 and sels[1] == sels[0] + 1, f"sels={sels[:3]}")
tabs = [field(s, "view") for s in states if "token=tab " in s]
check("tab cycles queue -> library -> search -> queue", tabs[:3] == ["library", "search", "queue"], f"{tabs[:3]}")
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
sys.exit(1 if fails else 0)
PY
