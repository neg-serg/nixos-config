#!/usr/bin/env python3
"""Drop the retired workflow-provider row from the installed liangshen preset.

dsh-TUI ships `presets/liangshen/agent.cordis.yml` with TWO workflow-provider
rows: the 0.1.x `@deepseek-ai/dsh-workflow-worker-thread` fallback and its
0.2.0 replacement `@deepseek-ai/dsh-workflow-ptc`. The fallback carries a
`disabled: !!js` guard (it turns off while the replacement resolves), but the
harness reads the declaration statically: an unevaluated expression is never
`true`, so `prepareProfileEntries` denies the row, then denies the whole
`liangshen-plugins` Include that reaches it ("... and that file is never
rewritten") — the bundled preset cannot activate, and every boot prints two
~700-character warnings. On a runtime that ships the replacement the fallback
is dead code, so the caretaker removes it from the INSTALLED copy: upstream's
file belongs to the package, and a pnpm install is what would put the row back,
which is why this runs on every activation and login right after the install.

Usage: dsh-tui-liangshen-prune.py <agent.cordis.yml>

Idempotent and conservative: a file without the row — or one that lost the
replacement row too, where the fallback would be the live one again — is left
untouched. The rewrite is atomic (temp file + rename), so a hard-linked pnpm
store copy is never written through.
"""

import os
import re
import sys
import tempfile

ROW_ID = "workflow-worker-thread"
ROW_PLUGIN = "@deepseek-ai/dsh-workflow-worker-thread"
REPLACEMENT_PLUGIN = "@deepseek-ai/dsh-workflow-ptc"
ROW_START = re.compile(rf"^(?P<indent> *)- id: {re.escape(ROW_ID)}\s*$")


def row_span(lines):
    """Span of the retired row's YAML block, or None when it is absent.

    The block runs from its `- id:` line to the next item at the same indent (or
    a line indented further left); a same-indent comment does not end it, since
    cutting there would leave the block's remaining keys dangling. Trailing
    blank lines stay with the next item.
    """
    for index, line in enumerate(lines):
        match = ROW_START.fullmatch(line.rstrip("\n"))
        if match is None:
            continue
        indent = len(match.group("indent"))
        end = len(lines)
        for following in range(index + 1, len(lines)):
            candidate = lines[following]
            if not candidate.strip():
                continue
            current = len(candidate) - len(candidate.lstrip(" "))
            if current < indent or (
                current == indent and candidate.lstrip(" ").startswith("- ")
            ):
                end = following
                break
        while end > index + 1 and not lines[end - 1].strip():
            end -= 1
        return index, end
    return None


def write_atomic(path, text):
    directory = os.path.dirname(path) or "."
    mode = os.stat(path).st_mode & 0o7777
    handle, temporary = tempfile.mkstemp(
        dir=directory, prefix=".dsh-liangshen-prune-", suffix=".tmp"
    )
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as opened:
            opened.write(text)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def main(argv):
    if len(argv) != 2:
        print(
            f"usage: {os.path.basename(argv[0])} <agent.cordis.yml>",
            file=sys.stderr,
        )
        return 2
    path = argv[1]
    if not os.path.isfile(path):
        return 0
    with open(path, encoding="utf-8") as opened:
        text = opened.read()
    lines = text.splitlines(keepends=True)
    span = row_span(lines)
    if span is None:
        return 0
    start, end = span
    block = "".join(lines[start:end])
    if ROW_PLUGIN not in block:
        print(
            f"dsh-tui-ensure: {path}: '{ROW_ID}' does not name {ROW_PLUGIN}; left alone",
            file=sys.stderr,
        )
        return 0
    if REPLACEMENT_PLUGIN not in text:
        print(
            f"dsh-tui-ensure: {path}: the {REPLACEMENT_PLUGIN} replacement is missing; '{ROW_ID}' left alone",
            file=sys.stderr,
        )
        return 0
    pruned = lines[:start] + lines[end:]
    if pruned_is_rejected(pruned):
        return 1
    try:
        write_atomic(path, "".join(pruned))
    except OSError as error:
        print(
            f"dsh-tui-ensure: cannot rewrite {path}: {error}", file=sys.stderr
        )
        return 1
    print(f"dsh-tui-ensure: pruned the retired '{ROW_ID}' row from {path}")
    return 0


def pruned_is_rejected(lines):
    """Whether an optional parse check rejects the pruned document.

    PyYAML is only a convenience here (the caretaker must not depend on it): a
    missing module means "no opinion", a parse error means the cut was wrong.
    The entry list is full of `!!js` scalars — the loader evaluates nothing, it
    only has to accept the tag (the harness evaluates those at activation).
    """
    try:
        import yaml
    except ImportError:
        return False

    class Loader(yaml.SafeLoader):
        pass

    Loader.add_constructor(
        "tag:yaml.org,2002:js",
        lambda loader, node: loader.construct_scalar(node),
    )
    try:
        data = yaml.load("".join(lines), Loader=Loader)
    except yaml.YAMLError as error:
        print(
            f"dsh-tui-ensure: refusing to write an invalid preset: {error}",
            file=sys.stderr,
        )
        return True
    rows = [row for row in data or [] if isinstance(row, dict)]
    if any(row.get("id") == ROW_ID for row in rows):
        print(
            f"dsh-tui-ensure: refusing to write a preset that still names '{ROW_ID}'",
            file=sys.stderr,
        )
        return True
    return False


if __name__ == "__main__":
    sys.exit(main(sys.argv))
