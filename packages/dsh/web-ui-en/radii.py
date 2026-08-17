#!/usr/bin/env python3
"""Halve every px border-radius in the compiled @deepseek-ai tree.

The dsh 0.1.0-rc.6 web frontend rounds nearly every surface (cards, panels,
menus, buttons) with hardcoded border-radius values scattered across the
compiled client bundles (CSS-module strings inside client.js, the static
index-*.css asset, and the --dsl-*-radius theme variables). This patch walks
the whole @deepseek-ai subtree and halves every numeric px radius so the
whole GUI reads noticeably less round:

  - `border-radius:Npx` (single and multi-value) -> `border-radius:N/2px`,
    rounded up to the nearest integer (3px -> 2px, 5px -> 3px, 7px -> 4px).
  - the --dsl-*-radius custom property definitions (12px -> 6px).
  - radii >= 100px (pill/capsule buttons) and percentages (50% circles,
    avatars/dots) are left untouched — halving them would either change
    nothing visually or turn circles into ovals.
  - var(...)/inherit/0 values are left as-is.

Idempotent per build: runs on a fresh copy of the tree, so applying it again
just halves already-halved values; the runCommand always starts from the
unpatched dsh output.

Run:  python3 radii.py <path-to-@deepseek-ai-subtree>
"""

import pathlib
import re
import sys

# radius property values: `border-radius: <v>`, `border-top-left-radius: <v>`, ...
# The (?<![\w-]) guard stops the pattern from matching the "border-radius"
# substring inside custom property names like `--dsl-code-block-border-radius`
# (which VAR_RADIUS_RE handles once, whole-name).
RADIUS_RE = re.compile(r"(?<![\w-])(border-[\w-]*radius\s*:\s*)([^;}]+)")
# custom property definitions: `--dsl-code-block-border-radius: 12px;`
VAR_RADIUS_RE = re.compile(r"(--[\w-]*radius\s*:\s*)([^;}]+)")


def _halve_px(value: str) -> str:
    """Halve every `Npx` token in a radius value; leave %/var()/inherit/0."""

    def one(m: re.Match) -> str:
        n = int(m.group(1))
        if n >= 100:  # pill/capsule radius — halving changes nothing visually
            return m.group(0)
        return f"{(n + 1) // 2}px"  # round half up, 1px stays 1px

    return re.sub(r"(\d+)px", one, value)


def patch_file(path: pathlib.Path) -> bool:
    try:
        data = path.read_bytes()
    except OSError:
        return False
    if b"radius" not in data:
        return False
    text = data.decode("utf-8")
    new_text = RADIUS_RE.sub(
        lambda m: m.group(1) + _halve_px(m.group(2)), text
    )
    new_text = VAR_RADIUS_RE.sub(
        lambda m: m.group(1) + _halve_px(m.group(2)), new_text
    )
    if new_text == text:
        return False
    path.write_text(new_text, encoding="utf-8")
    return True


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 1

    patched = 0
    scanned = 0
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix not in (".js", ".css"):
            continue
        scanned += 1
        if patch_file(path):
            patched += 1
            print(f"halved radii: {path.relative_to(root)}")
    print(f"done: halved radii in {patched}/{scanned} js/css files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
