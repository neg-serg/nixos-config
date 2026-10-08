import json
import sys

# Rewrite the owned blocks of the tui profile's cordis.patch.yml.
#
# Usage: dsh-tui-preset-patch.py <patch.yml> <rows-file> <presets-json> [prefix]
#
# Three facts about the dsh-TUI bundle and the 0.2.0 preset registry the profile
# layer has to mirror:
#   * its bundle patch replaces the base `agent-presets` roster row with the
#     scoped `dsh-tui-agent-presets` id (legacy, disabled since 0.1.7), while
#     the registry row it wires for the current harness generation is
#     `dsh-tui-agent-preset-registry` — the fallback preset must therefore be
#     named in that row's `config.default` (a row naming `agent-presets` is
#     dropped with `patch: entry "agent-presets" not found` on every start);
#   * the bundle ships no presets of its own (the shipped standard/ptc/minimal/
#     cordis declarations belong to the dsh-web-app bundle, which the terminal
#     profile does not mount), so this deployment declares `neg` and `fast`
#     itself — see dsh-presets.nix;
#   * the bundle already inserts its own code-runtime row, and a second one is a
#     duplicate `codeRuntime` registration that kills the boot — so the runtime
#     block this script used to write is retired and any leftover copy is
#     consumed (see OWNED_MARKERS).
path = sys.argv[1]
rows_path = sys.argv[2] if len(sys.argv) > 2 else None
presets_path = sys.argv[3] if len(sys.argv) > 3 else None
# Marker/echo prefix: the profile owns its marker text, so a rewrite never
# mistakes a hand-written block for its own.
PREFIX = sys.argv[4] if len(sys.argv) > 4 else "dsh-tui-ensure"
MARKER_PRESETS = f"# {PREFIX}: agent presets"
MARKER_PRESET = f"# {PREFIX}: default preset"
MARKER_RUNTIME = f"# {PREFIX}: code runtime"
MARKER_PLUGINS = f"# {PREFIX}: plugin rows"
MARKER_LEGACY = f"# {PREFIX}: retired TUI rows"
plugin_rows = []
if rows_path is not None:
    with open(rows_path, encoding="utf-8") as f:
        plugin_rows = [line.rstrip("\n") for line in f if line.strip()]

spec = None
if presets_path is not None:
    with open(presets_path, encoding="utf-8") as f:
        spec = json.load(f)


def preset_block(spec):
    """Declaration rows for every preset in dsh-presets.nix's JSON.

    The plugin list is the preset's `agent.cordis.yml` verbatim (0.2.0 replaced
    the `.agent-presets/<id>/` directories with exactly this), re-indented under
    `config.plugins`. The file's leading comment banner is dropped — it belongs
    to the source file, and the profile layer is regenerated on every login —
    while inline comments inside the entry list stay, because they document the
    declaration.
    """
    lines = [
        MARKER_PRESETS
        + " — declaration rows (@deepseek-ai/dsh-agent-preset). The old",
        "# $DSH_HOME/.agent-presets/<id>/ directories are dead in 0.2.0; see",
        "# modules/user/nix-maid/apps/dsh-presets.nix for the source of truth.",
    ]
    for preset in spec["presets"]:
        with open(preset["plugins"], encoding="utf-8") as f:
            plugins = f.read().split("\n")
        while plugins and (
            not plugins[0].strip() or plugins[0].lstrip().startswith("#")
        ):
            plugins.pop(0)
        while plugins and not plugins[-1].strip():
            plugins.pop()
        lines += [
            "- insert:",
            f"    - id: preset-{preset['id']}",
            f"      name: '{spec['declarationPlugin']}'",
            "      config:",
            f"        id: {preset['id']}",
            f"        name: {json.dumps(preset['name'], ensure_ascii=False)}",
            "        description: "
            + json.dumps(preset["description"], ensure_ascii=False),
            f"        order: {preset['order']}",
            "        plugins:",
        ]
        lines += [
            (" " * 10 + line).rstrip() if line.strip() else ""
            for line in plugins
        ]
    return lines


# Rows the dsh-TUI 0.14 bundle still carries from the 0.1.5 generation: they
# name plugin packages whose peer ranges are ^0.1.5-rc.1, so dsh 0.2.0 refuses
# them at boot and disables each one with a ~700-character warning (the
# presets they used to serve are declared by this profile now — see
# dsh-presets.nix). Disabling them here produces the same outcome without the
# noise, and keeps the profile layer the single place that decides.
# `liangshen-plugins` and `workflow-worker-thread` warn the same way but are not
# addressable by id (they sit inside the TUI bundle's own nested lists, and an
# id-targeted patch for them is reported as "entry not found" — noise of our
# own), so the harness's own disable stays the only handling for those two.
LEGACY_ROWS = [
    "dsh-tui-agent-presets",
    "dsh-tui-code-runtime",
]
MARKER_LEGACY_BLOCK = (
    MARKER_LEGACY,
    [
        MARKER_LEGACY
        + " — 0.1.5-era plugin packages this harness generation rejects;",
        "# disabled here instead of letting the boot warn about each one.",
    ]
    + [
        line
        for row in LEGACY_ROWS
        for line in (f"- id: {row}", "  disabled: true")
    ],
)

BLOCKS = [
    (
        MARKER_PRESET,
        [
            MARKER_PRESET
            + " — the shipped `standard` belongs to the web-app bundle, which this",
            "# profile does not mount, so the registry default must name a preset the",
            "# profile declares. settings.yaml still overrides it at runtime (the",
            "# registry reads its settings-backed `selectedDefault` first).",
            f"- id: {spec['registryRow'] if spec else 'dsh-tui-agent-preset-registry'}",
            "  config:",
            f"    default: {spec['defaultPreset'] if spec else 'neg'}",
        ],
    ),
    (
        MARKER_PLUGINS,
        [MARKER_PLUGINS] + plugin_rows,
    ),
]
if spec is not None:
    BLOCKS.insert(0, (MARKER_PRESETS, preset_block(spec)))
BLOCKS.append(MARKER_LEGACY_BLOCK)
# Markers we own even though we no longer emit their block: the retired
# code-runtime insert must be consumed, not re-read as a user row (that would
# keep the duplicate this script exists to avoid).
OWNED_MARKERS = [
    MARKER_PRESETS,
    MARKER_PRESET,
    MARKER_RUNTIME,
    MARKER_PLUGINS,
    MARKER_LEGACY,
]

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
print(f"{PREFIX}: {path}: wrote the profile layer (presets + plugin rows)")
