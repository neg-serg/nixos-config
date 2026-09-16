import sys

# Rewrite the owned blocks of a terminal profile's cordis.patch.yml.
#
# Usage: dsh-tui-preset-patch.py <patch.yml> <rows-file> [prefix] [preset-id] [runtime]
#
# The profile layer is shared by the two terminal profiles, but the TUI bundles
# differ in two id-level facts the layer has to mirror:
#   * the agent-preset roster row — Martty keeps the base `agent-presets`,
#     dsh-TUI's bundle patch replaces it with the scoped `dsh-tui-agent-presets`;
#   * the code-runtime row — dsh-TUI's bundle already inserts one, and a second
#     copy is a duplicate `codeRuntime` registration that kills the boot, while
#     Martty's bundle has none.
# `runtime`/`no-runtime` select whether this script writes the code-runtime
# insert at all.
path = sys.argv[1]
# Marker/echo prefix: each terminal profile owns its own marker text, so a
# rewrite never mistakes another profile's blocks for its own. The tui profile
# (dsh-tui-ensure.sh) keeps the default; the martty profile passes its own name.
PREFIX = sys.argv[3] if len(sys.argv) > 3 else "dsh-tui-ensure"
PRESET_ID = sys.argv[4] if len(sys.argv) > 4 else "agent-presets"
WANT_RUNTIME = (
    sys.argv[5] if len(sys.argv) > 5 else "runtime"
) != "no-runtime"
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
# Markers we own even when we no longer emit them: a stale code-runtime block
# must be consumed, not re-read as a user row (that would keep the duplicate
# the switch to dsh-TUI has to remove).
OWNED_MARKERS = [MARKER_PRESET, MARKER_RUNTIME, MARKER_PLUGINS]
if WANT_RUNTIME:
    BLOCKS.append(
        (
            MARKER_RUNTIME,
            [
                MARKER_RUNTIME
                + " — the neg preset promotes the agent to Code Mode",
                "# (tool-bootstrap `promotedPresentation: code`), and dsh-tools refuses",
                '# mode "code" without a ctx.codeRuntime implementation. The web profile',
                "# mounts it; a terminal profile whose bundle does not must add it here.",
                "- insert:",
                "    - id: code-runtime",
                "      name: '@deepseek-ai/dsh-code-runtime-worker-thread'",
            ],
        )
    )

with open(path, encoding="utf-8") as f:
    src = f.read()

lines = src.split("\n")
header, kept, index = [], [], 0
while index < len(lines):
    line = lines[index]
    # A marker we own is consumed whether or not we still emit its block, so a
    # retired block (the code-runtime insert under `no-runtime`) cannot leak
    # back in as a user row.
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

# Blocks we no longer emit (the code-runtime insert under `no-runtime`) were
# already consumed by the skip loop above via OWNED_MARKERS.
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
print(f"{PREFIX}: {path}: wrote the profile layer (preset + code runtime)")
