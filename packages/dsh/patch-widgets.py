#!/usr/bin/env python3
"""Patch dsh 0.1.5-rc.1 compiled tool bundles for dsh-widgets.

The per-call subagent `model` parameter this script used to inject was
upstreamed in 0.1.5-rc.1: the delegation tools now take `provider` /
`model` / `reasoning_effort` and fold them into the child's agentOptions
themselves (gated on the tool config `modelSelectionSettings`).

The remaining additions are staged server-side (they take effect after a dsh
rebuild):

1. presentationMeta on the subagent / workflow / ralph tools: each attaches a
   compact `{ kind, … }` descriptor to the persisted tool/result meta, so a
   capable client renders a structured card from logged data (replay-stable)
   instead of regex-parsing the rendered text. The dsh-widgets client cards
   still parse text today; the meta is the hardening path.

2. dsh-session `Session.append`: accept `{ ignorable: true }` in the surface
   opts and carry it on the event envelope. the harness otherwise cannot mark plugin
   events ignorable, and the history reader refuses logs with unknown
   non-ignorable event types (SessionFormatUnsupportedError) — the
   dsh-widgets `bash_live` stream events used to kill their session on every
   run. dsh-widgets passes the option for `tool/bash-live-*` events; the
   read side already accepts the envelope key.

Exact-string replacements with count assertions: a failed match (wrong dsh
version, formatting drift) fails the build loudly instead of silently producing
a half-patched tree.
"""

import sys
from functools import partial

from patchlib import patch_file

ROOT = sys.argv[1]  # .../node_modules/@deepseek-ai

patch = partial(patch_file, ROOT, prog="patch-widgets", announce=True)


SUBAGENT = "dsh-tool-subagent/lib/index.js"
patch(
    SUBAGENT,
    [
        # 1a/1b (optional `model` parameter + agentOptions pass-through) are
        # gone — see the module docstring.
        #
        # 2a. subagent presentationMeta (sibling of render inside output).
        (
            (
                ": outputValueText(value.output)\n"
                "\t\t\t\t\t\t}]\n"
                "\t\t\t\t\t},\n"
                "\t\t\t\t\tisConcurrencySafe: () => true,"
            ),
            (
                ": outputValueText(value.output)\n"
                "\t\t\t\t\t\t}],\n"
                '\t\t\t\t\tpresentationMeta: (_args, value) => ({ kind: "subagent", result: value })\n'
                "\t\t\t\t\t},\n"
                "\t\t\t\t\tisConcurrencySafe: () => true,"
            ),
            1,
        ),
    ],
)

WORKFLOW = "dsh-tool-workflow/lib/index.js"
patch(
    WORKFLOW,
    [
        # 2b. workflow presentationMeta.
        (
            (
                "text: renderResult(args.meta.name, value.agentsStarted, value.result, maxResultChars)\n"
                "\t\t\t}]\n"
                "\t\t},\n"
                "\t\tasync execute(args, exec) {"
            ),
            (
                "text: renderResult(args.meta.name, value.agentsStarted, value.result, maxResultChars)\n"
                "\t\t\t}],\n"
                "\t\t\tpresentationMeta: (args, value) => ({\n"
                '\t\t\t\tkind: "workflow",\n'
                "\t\t\t\trunId: value.runId,\n"
                "\t\t\t\tagentsStarted: value.agentsStarted,\n"
                "\t\t\t\tresult: value.result\n"
                "\t\t\t})\n"
                "\t\t},\n"
                "\t\tasync execute(args, exec) {"
            ),
            1,
        ),
    ],
)

RALPH = "dsh-tool-ralph/lib/index.js"
patch(
    RALPH,
    [
        # 2c. ralph presentationMeta.
        (
            (
                "text: renderResult(value.result, resolved.maxResultChars)\n"
                "\t\t\t}]\n"
                "\t\t},\n"
                "\t\tasync execute(args, exec) {"
            ),
            (
                "text: renderResult(value.result, resolved.maxResultChars)\n"
                "\t\t\t}],\n"
                "\t\t\tpresentationMeta: (_args, value) => ({\n"
                '\t\t\t\tkind: "ralph",\n'
                "\t\t\t\trunId: value.runId,\n"
                "\t\t\t\tagentsStarted: value.agentsStarted,\n"
                "\t\t\t\tresult: value.result\n"
                "\t\t\t})\n"
                "\t\t},\n"
                "\t\tasync execute(args, exec) {"
            ),
            1,
        ),
    ],
)

SESSION = "dsh-session/lib/index.js"
patch(
    SESSION,
    [
        # 3. Session.append: accept `{ ignorable: true }` in the surface opts
        #    and carry it on the event envelope. rc.6 has no other way to mark
        #    a plugin event ignorable, and the history reader refuses logs
        #    containing unknown non-ignorable event types
        #    (SessionFormatUnsupportedError) — dsh-widgets `bash_live` used to
        #    kill its session on every run. The read side already validates the
        #    envelope key (`case "ignorable": break`, value must be exactly
        #    true), so this is the missing write-side half.
        (
            (
                "\t\tconst surfaceMetadata = {\n"
                "\t\t\t...surfaceOpts?.sourceEventSeqs === void 0 ? {} : { sourceEventSeqs: surfaceOpts.sourceEventSeqs },\n"
                "\t\t\t...surfaceOpts?.surfaceOp === void 0 ? {} : { surfaceOp: surfaceOpts.surfaceOp }\n"
                "\t\t};"
            ),
            (
                "\t\tconst surfaceMetadata = {\n"
                "\t\t\t...surfaceOpts?.sourceEventSeqs === void 0 ? {} : { sourceEventSeqs: surfaceOpts.sourceEventSeqs },\n"
                "\t\t\t...surfaceOpts?.surfaceOp === void 0 ? {} : { surfaceOp: surfaceOpts.surfaceOp },\n"
                "\t\t\t...surfaceOpts?.ignorable === true ? { ignorable: true } : {}\n"
                "\t\t};"
            ),
            1,
        ),
    ],
)

print("patch-widgets: all patches applied cleanly")
