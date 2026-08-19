#!/usr/bin/env python3
"""Patch dsh 0.1.0-rc.6 compiled tool bundles for dsh-widgets.

Two additions, both staged server-side (they take effect after a dsh rebuild):

1. dsh-tool-subagent: an optional `model` parameter on the subagent tool that
   is merged into the child's agentOptions. The subagent provider already
   resolves the child model as `request.agentOptions?.model ?? parent.options.model`
   (dsh-subagent/lib/index.js), so this is a pure pass-through — the model can
   now delegate to a cheaper/faster model (e.g. deepseek-v4-flash) per call.

2. presentationMeta on the subagent / workflow / ralph tools: each attaches a
   compact `{ kind, … }` descriptor to the persisted tool/result meta, so a
   capable client renders a structured card from logged data (replay-stable)
   instead of regex-parsing the rendered text. The dsh-widgets client cards
   still parse text today; the meta is the hardening path.

Exact-string replacements with count assertions: a failed match (wrong dsh
version, formatting drift) fails the build loudly instead of silently producing
a half-patched tree.
"""

import sys

ROOT = sys.argv[1]  # .../node_modules/@deepseek-ai


def patch_file(rel, replacements):
    path = f"{ROOT}/{rel}"
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for old, new, expected in replacements:
        n = src.count(old)
        if n != expected:
            raise SystemExit(
                f"patch-widgets: {rel}: pattern found {n} time(s), expected {expected}: "
                f"{old[:90]!r}"
            )
        src = src.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print(f"patch-widgets: patched {rel}")


SUBAGENT = "dsh-tool-subagent/lib/index.js"
patch_file(
    SUBAGENT,
    [
        # 1a. add the optional `model` parameter after the run_in_background spread.
        (
            "} } : {}\n\t\t\t},\n\t\t\toutput: {",
            "} } : {},\n"
            "\t\t\t\tmodel: {\n"
            '\t\t\t\t\ttype: "string",\n'
            '\t\t\t\t\tdescription: "Optional model override for the delegated child (e.g. '
            "deepseek-v4-flash). Falls back to the parent's model when omitted.\"\n"
            "\t\t\t\t}\n"
            "\t\t\t},\n"
            "\t\t\toutput: {",
            1,
        ),
        # 1b. merge the model into the child request's agentOptions.
        (
            "\t\t\t\t\t...config.agentOptions !== void 0 ? { agentOptions: config.agentOptions } : {},",
            "\t\t\t\t\tagentOptions: {\n"
            "\t\t\t\t\t\t...(config.agentOptions ?? {}),\n"
            "\t\t\t\t\t\t...args.model !== void 0 ? { model: args.model } : {}\n"
            "\t\t\t\t\t},",
            1,
        ),
        # 2a. subagent presentationMeta (sibling of render inside output).
        (
            ": outputValueText(value.output)\n"
            "\t\t\t\t}]\n"
            "\t\t\t},\n"
            "\t\t\tisConcurrencySafe: () => true,",
            ": outputValueText(value.output)\n"
            "\t\t\t\t}],\n"
            '\t\t\t\tpresentationMeta: (_args, value) => ({ kind: "subagent", result: value })\n'
            "\t\t\t},\n"
            "\t\t\tisConcurrencySafe: () => true,",
            1,
        ),
    ],
)

WORKFLOW = "dsh-tool-workflow/lib/index.js"
patch_file(
    WORKFLOW,
    [
        # 2b. workflow presentationMeta.
        (
            "text: renderResult(args.meta.name, value.agentsStarted, value.result, maxResultChars)\n"
            "\t\t\t}]\n"
            "\t\t},\n"
            "\t\tasync execute(args, exec) {",
            "text: renderResult(args.meta.name, value.agentsStarted, value.result, maxResultChars)\n"
            "\t\t\t}],\n"
            "\t\t\tpresentationMeta: (args, value) => ({\n"
            '\t\t\t\tkind: "workflow",\n'
            "\t\t\t\trunId: value.runId,\n"
            "\t\t\t\tagentsStarted: value.agentsStarted,\n"
            "\t\t\t\tresult: value.result\n"
            "\t\t\t})\n"
            "\t\t},\n"
            "\t\tasync execute(args, exec) {",
            1,
        ),
    ],
)

RALPH = "dsh-tool-ralph/lib/index.js"
patch_file(
    RALPH,
    [
        # 2c. ralph presentationMeta.
        (
            "text: renderResult(value.result, resolved.maxResultChars)\n"
            "\t\t\t}]\n"
            "\t\t},\n"
            "\t\tasync execute(args, exec) {",
            "text: renderResult(value.result, resolved.maxResultChars)\n"
            "\t\t\t}],\n"
            "\t\t\tpresentationMeta: (_args, value) => ({\n"
            '\t\t\t\tkind: "ralph",\n'
            "\t\t\t\trunId: value.runId,\n"
            "\t\t\t\tagentsStarted: value.agentsStarted,\n"
            "\t\t\t\tresult: value.result\n"
            "\t\t\t})\n"
            "\t\t},\n"
            "\t\tasync execute(args, exec) {",
            1,
        ),
    ],
)

print("patch-widgets: all patches applied cleanly")
