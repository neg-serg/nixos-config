import sys

# Rewrite the owned blocks of the tui profile's cordis.patch.yml.
#
# Usage: dsh-tui-preset-patch.py <patch.yml> <rows-file> [prefix]
#
# Two facts about the dsh-TUI bundle the profile layer has to mirror:
#   * its bundle patch replaces the base `agent-presets` roster row with the
#     scoped `dsh-tui-agent-presets` id, so the fallback-preset row must target
#     that id (a row naming `agent-presets` is dropped with
#     `patch: entry "agent-presets" not found` on every start);
#   * the bundle already inserts its own code-runtime row, and a second one is a
#     duplicate `codeRuntime` registration that kills the boot — so the runtime
#     block this script used to write is retired and any leftover copy is
#     consumed (see OWNED_MARKERS).
path = sys.argv[1]
# Marker/echo prefix: the profile owns its marker text, so a rewrite never
# mistakes a hand-written block for its own.
PREFIX = sys.argv[3] if len(sys.argv) > 3 else "dsh-tui-ensure"
PRESET_ID = "dsh-tui-agent-presets"
MARKER_PRESET = f"# {PREFIX}: default preset"
MARKER_RUNTIME = f"# {PREFIX}: code runtime"
MARKER_PLUGINS = f"# {PREFIX}: plugin rows"
rows_path = sys.argv[2] if len(sys.argv) > 2 else None
plugin_rows = []
if rows_path is not None:
    with open(rows_path, encoding="utf-8") as f:
        plugin_rows = [line.rstrip("\n") for line in f if line.strip()]
BLOCKS = [
    (
        MARKER_PRESET,
        [
            MARKER_PRESET
            + " — the shipped `standard` is removed from the harness build, so the",
            "# fallback must name a preset that exists (settings.yaml still overrides it).",
            f"- id: {PRESET_ID}",
            "  config:",
            "    default: neg",
        ],
    ),
    (
        MARKER_PLUGINS,
        [MARKER_PLUGINS] + plugin_rows,
    ),
]
# Markers we own even though we no longer emit their block: the retired
# code-runtime insert must be consumed, not re-read as a user row (that would
# keep the duplicate this script exists to avoid).
OWNED_MARKERS = [MARKER_PRESET, MARKER_RUNTIME, MARKER_PLUGINS]

with open(path, encoding="utf-8") as f:
    src = f.read()

lines = src.split("\n")
header, kept, index = [], [], 0
while index < len(lines):
    line = lines[index]
    owned = next((marker for marker in OWNED_MARKERS if marker in line), None)
    if owned is not None:
        # Skip this block: its marker line plus everything up to the next
        # block we own (or EOF). Content-based skipping would leave a stale
        # or malformed block behind — the loader then dies on a duplicate
        # entry id.
        index += 1
        while index < len(lines) and not any(
            marker in lines[index] for marker in OWNED_MARKERS
        ):
            index += 1
        continue
    if line.strip() == "[]":
        index += 1
        continue
    (header if not kept and line.startswith("#") else kept).append(line)
    index += 1

body = "\n".join(header).rstrip("\n")
for _, block in BLOCKS:
    body += "\n\n" + "\n".join(block)
body = body.rstrip("\n") + "\n"
# keep any non-owned rows the user added, after ours
extra = [row for row in kept if row.strip() and not row.startswith("#")]
if extra:
    body = body.rstrip("\n") + "\n" + "\n".join(extra) + "\n"

if body == src:
    print(f"{PREFIX}: {path}: profile layer already current")
    sys.exit(0)
with open(path, "w", encoding="utf-8") as f:
    f.write(body)
print(f"{PREFIX}: {path}: wrote the profile layer (preset + plugin rows)")
