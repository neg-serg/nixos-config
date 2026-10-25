#!/usr/bin/env bash
# Every `emit` in a pleamar scene must reach something.
#
# The owner's first report about the port was "the click leads nowhere": the
# capsule had no rule, or the rule emitted an event no logic ever listened to.
# Compiling does not catch that — `emit nosuch` compiles as soon as the scene
# declares the event, and a scene that declares twenty events and handles two
# compiles fine.
#
# What counts as reaching something, and why each is legitimate:
#   · a logic handler — `on("name", …)` in a .luau;
#   · a scene rule — `on name { … }` in a .plm;
#   · a component's event parameter — `component X(step: event, …)` with
#     `emit step(…)` inside; the caller passes the real event, so the name is
#     alive without a handler of its own (this is how the volume capsule is
#     shared between the sink and the source).
#
# Handlers are collected from the whole tree rather than file by file: a plugin
# handler lives in `lib/` while the emit that reaches it lives in the scene that
# imports it, and `emit Pill.toggle` is answered by `pill.luau`. Being generous
# here is deliberate — the gate is for events that reach *nothing*, and a false
# positive would teach everyone to ignore it.
#
# Comments are stripped first: a note that quotes an event is not an emit.
#
# Exit: 0 every emit reaches something, 1 a dead emit was found.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
SHELLS="$REPO_ROOT/files/pleamar/shells"
LIB="$REPO_ROOT/files/pleamar/lib"

[ -d "$SHELLS" ] || {
  echo "check-scene-events: no scenes under $SHELLS" >&2
  exit 1
}

python3 - "$SHELLS" "$LIB" << 'PY'
import pathlib
import re
import sys

shells = pathlib.Path(sys.argv[1])
lib = pathlib.Path(sys.argv[2])

EMIT = re.compile(r"\bemit\s+([A-Za-z_][\w.]*)")
HANDLER = re.compile(r'\bon\(\s*"([\w.]+)"')
EVENT_PARAM = re.compile(r"(\w+)\s*:\s*event\b")
RULE = re.compile(r"^\s*on\s+([A-Za-z_][\w.]*)\s*(?:\{|while\b|->|$)")
INPUT_RULE = ("key", "press", "enter", "leave", "drag", "wheel", "hold")
COMMENT = re.compile(r"(?<!:)//[^\n]*")


def read(path):
    try:
        return path.read_text()
    except OSError:
        return ""


def code(text):
    """The file without its `//` comments."""
    return COMMENT.sub("", text)


plms = sorted(shells.glob("*/*.plm")) + sorted(lib.rglob("*.plm"))
luaus = sorted(shells.glob("*/*.luau")) + sorted(lib.rglob("*.luau"))

known = set()
for path in luaus:
    known |= set(HANDLER.findall(code(read(path))))
for path in plms:
    text = code(read(path))
    known |= set(EVENT_PARAM.findall(text))
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("on ") and not stripped.startswith(tuple("on " + w for w in INPUT_RULE)):
            match = RULE.match(line)
            if match:
                known.add(match.group(1))

dead = []
for plm in plms:
    for name in sorted(set(EMIT.findall(code(read(plm))))):
        # `Pill.toggle` is the plugin boundary's name for the event the plugin's own logic
        # handles as "toggle": the head names the library, the tail names the handler.
        parts = name.split(".")
        if name in known or parts[0] in known or parts[-1] in known:
            continue
        dead.append((str(plm.relative_to(shells.parent)), name))

if dead:
    for where, name in dead:
        print(f"check-scene-events: {where}: emit {name} reaches nothing", file=sys.stderr)
    print(f"check-scene-events: {len(dead)} dead emit(s)", file=sys.stderr)
    sys.exit(1)

print(f"check-scene-events: ok ({len(plms)} scene and library file(s))")
PY
