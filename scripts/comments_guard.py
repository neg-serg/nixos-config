#!/usr/bin/env python3
"""Guard: ensure pkgs.* items inside list blocks have inline comments.

Scans Nix files under modules/ and looks for any list block `[...]` that
contains lines with `pkgs.` but without a `#` comment on the same line.
Exits non‑zero if any offenders are found.
"""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path


def main() -> int:
    try:
        out = subprocess.check_output(["rg", "-l", r"\.nix$", "modules"])  # type: ignore
    except Exception:
        print("ripgrep (rg) is required for COMMENTS_GUARD", file=sys.stderr)
        return 2

    files = out.decode().splitlines()
    missing: list[tuple[str, int, str]] = []

    for f in files:
        text = Path(f).read_text(encoding="utf-8")
        i, n = 0, len(text)
        stack: list[int] = []
        while i < n:
            c = text[i]
            if c == '"':
                j = i + 1
                while j < n:
                    if text[j] == "\\":
                        j += 2
                        continue
                    if text[j] == '"':
                        j += 1
                        break
                    j += 1
                i = j
                continue
            if c == "'" and i + 1 < n and text[i + 1] == "'":
                j = text.find("''", i + 2)
                if j == -1:
                    break
                i = j + 2
                continue
            if c == "[":
                stack.append(i)
            elif c == "]" and stack:
                start = stack.pop()
                block = text[start : i + 1]
                base = text.count("\n", 0, start) + 1
                for off, line in enumerate(block.splitlines()):
                    if "pkgs." in line and "#" not in line:
                        missing.append((f, base + off, line.strip()))
            i += 1

    if missing:
        for f, ln, t in missing:
            print(f"MISSING COMMENT: {f}:{ln}: {t}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
