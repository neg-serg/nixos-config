import sys

path = sys.argv[1]
MARKER_PRESET = "# dsh-tui-ensure: default preset"
MARKER_RUNTIME = "# dsh-tui-ensure: code runtime"
MARKER_PLUGINS = "# dsh-tui-ensure: plugin rows"
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
            "- id: agent-presets",
            "  config:",
            "    default: neg",
        ],
    ),
    (
        MARKER_PLUGINS,
        [MARKER_PLUGINS] + plugin_rows,
    ),
    (
        MARKER_RUNTIME,
        [
            MARKER_RUNTIME
            + " — the neg preset promotes the agent to Code Mode",
            "# (tool-bootstrap `promotedPresentation: code`), and dsh-tools refuses",
            '# mode "code" without a ctx.codeRuntime implementation. The web profile',
            "# mounts it; the TUI profile's bundles (dsh-base + the tui plugin) do not.",
            "- insert:",
            "    - id: code-runtime",
            "      name: '@deepseek-ai/dsh-code-runtime-worker-thread'",
        ],
    ),
]

with open(path, encoding="utf-8") as f:
    src = f.read()

lines = src.split("\n")
header, kept, index = [], [], 0
while index < len(lines):
    line = lines[index]
    owned = next((block for marker, block in BLOCKS if marker in line), None)
    if owned is not None:
        # Skip this block: its marker line plus everything up to the next
        # block we own (or EOF). Content-based skipping would leave a stale
        # or malformed block behind — the loader then dies on a duplicate
        # entry id.
        index += 1
        while index < len(lines) and not any(
            marker in lines[index] for marker, _ in BLOCKS
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
    print(f"dsh-tui-ensure: {path}: profile layer already current")
    sys.exit(0)
with open(path, "w", encoding="utf-8") as f:
    f.write(body)
print(
    f"dsh-tui-ensure: {path}: wrote the profile layer (preset + code runtime)"
)
