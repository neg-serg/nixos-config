#!/usr/bin/env python3
"""Cap long chat markdown code blocks with an internal scrollbar.

The dsh 0.1.0-rc.6 web frontend renders assistant code fences at full
height: the CodeBlock wrapper (class `md-code-block`, scoped `._block_...`)
and its `pre.shiki` carry no height limit, so a long listing pushes the
whole conversation. This patch appends an override to the compiled
`dsh-web-frontend/dist/assets/*.css` asset(s) that caps the wrapper height
(`min(50vh, 400px)`) and makes it scroll internally; `overscroll-behavior`
keeps the page from scroll-chaining while the cursor is over the block.

Idempotent per build: the runCommand always starts from a fresh copy of the
unpatched dsh output; the guard below only protects against manual re-runs.

Run:  python3 codeblocks.py <path-to-@deepseek-ai-subtree>
"""

import pathlib
import sys

RULE = (
    "/* dsh-web-en: cap long code blocks, scroll inside */\n"
    ".md-code-block{max-height:min(50vh,400px);overflow:auto;overscroll-behavior:contain}\n"
)


def main(root: pathlib.Path) -> int:
    found = 0
    for css in root.glob("dsh-web-frontend/dist/assets/*.css"):
        text = css.read_text(encoding="utf-8")
        if ".md-code-block{max-height" in text:
            print(f"[codeblocks] already patched: {css}")
        else:
            css.write_text(text + "\n" + RULE, encoding="utf-8")
            print(f"[codeblocks] patched: {css}")
        found += 1
    if not found:
        print("[codeblocks] WARNING: no dsh-web-frontend css assets found")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1])))
