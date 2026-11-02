#!/usr/bin/env python3
"""Extract the three embedded Python programs from the legacy shell proxy.

The Rust port replaces `packages/local-bin/bin/proxy`. Its config generator
(`gen_cfg`), bootstrap patcher and node validator lived inside bash heredocs;
this script copies those heredocs verbatim so the golden fixtures can be
regenerated from the original implementation while the shell script still
exists. The extracted programs are intentionally NOT committed: they are
unformatted Python (`import a, b`, undefined `os`, one-line `if` bodies) and
would fail the repository's ruff/black gates. `regenerate.sh` extracts them
into a throwaway directory instead.

Usage:
    python3 tests/reference/extract_oracle.py <proxy-shell-script> [output-dir]

Without an output directory the programs are written next to this script.
"""

import pathlib
import sys

NAMES = ["gen_cfg", "bootstrap_patch", "validate_nodes"]


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(
            f"usage: {sys.argv[0]} <proxy-shell-script> [output-dir]",
            file=sys.stderr,
        )
        return 2
    src = pathlib.Path(sys.argv[1]).read_text().splitlines()
    blocks = []
    i = 0
    while i < len(src):
        if "python3" in src[i] and "<< 'PYEOF'" in src[i]:
            i += 1
            body = []
            while i < len(src) and src[i].strip() != "PYEOF":
                body.append(src[i])
                i += 1
            blocks.append("\n".join(body) + "\n")
        i += 1
    if len(blocks) != len(NAMES):
        print(
            f"expected {len(NAMES)} heredocs, found {len(blocks)}",
            file=sys.stderr,
        )
        return 1
    if len(sys.argv) == 3:
        out = pathlib.Path(sys.argv[2])
        out.mkdir(parents=True, exist_ok=True)
    else:
        out = pathlib.Path(__file__).resolve().parent
    for name, body in zip(NAMES, blocks):
        (out / f"{name}.py").write_text(body)
        print(f"wrote {out / (name + '.py')} ({len(body.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
