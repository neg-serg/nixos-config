#!/usr/bin/env python3
"""Expose parsed tool arguments under `exec.args` for pre-execute hooks.

The 0.2.0 tool registry mints every execution with `arguments` (parsed,
frozen model arguments) and `tools/pre-execute` listeners receive that object —
while the deployment's own hooks still read the pre-0.2 `exec.args` shape:

* modules/user/nix-maid/apps/dsh-plan-format-validator reads `exec.args.plan`
  and therefore saw every exit_plan_mode plan as an empty string, denying all
  of them with the "empty plan" reason; plan mode could not be left through
  the tool at all.
* modules/user/nix-maid/apps/dsh-notepad-write-guard reads `exec.args` too and
  silently never matched.

The alias keeps both hooks working until their sources move to `arguments`
(the proper fix, which lives outside this package). It is added next to the
canonical field, so tools/execute and later pipeline stages see it as well; no
existing consumer reads `args`, so the addition cannot shadow anything.

Exact-string + count-asserted: a dsh upgrade that drifts the anchor fails the
build loudly instead of silently disabling the hook again.

Usage: patch-tool-exec-args.py <node_modules/@deepseek-ai dir>
"""

import sys
from functools import partial

from patchlib import patch_file

ROOT = sys.argv[1]  # .../node_modules/@deepseek-ai

patch = partial(patch_file, ROOT, prog="patch-tool-exec-args")

EXEC_OLD = """\t\t\tconst execution = {
\t\t\t\t...base,
\t\t\t\targuments: deepFreeze(detached)
\t\t\t};"""
EXEC_NEW = """\t\t\tconst execution = {
\t\t\t\t...base,
\t\t\t\targuments: deepFreeze(detached),
\t\t\t\t/* Pre-0.2 alias read by this deployment's tools/pre-execute hooks
\t\t\t\t * (dsh-plan-format-validator, dsh-notepad-write-guard). */
\t\t\t\targs: deepFreeze(detached)
\t\t\t};"""

patch(
    "dsh-tools/lib/index.js",
    [(EXEC_OLD, EXEC_NEW, "tool execution exec.args alias")],
)

print("patch-tool-exec-args: exec.args now aliases the parsed tool arguments")
