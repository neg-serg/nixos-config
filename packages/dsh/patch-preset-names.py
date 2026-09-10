#!/usr/bin/env python3
"""Rewrite shipped agent-preset metadata (preset.yml) from Chinese to English.

The user's de-Chinese rule covers UI copy, and the preset picker + slash
commands (/mode) render these names/descriptions. The strings below are the
exact upstream literals; a dsh upgrade that drifts any of them fails this
script loudly instead of silently shipping Chinese again.

Usage: patch-preset-names.py <dsh-agent-presets/presets dir>
"""

import pathlib
import sys

PRESETS_DIR = pathlib.Path(sys.argv[1])

# id -> { old literal: new literal }, each old string must occur exactly once.
REWRITES = {
    # 0.1.5-rc.1 renamed the `code` preset to `ptc` and reworded `minimal`;
    # `cordis` is unchanged. `standard` is deleted before this runs.
    "ptc": {
        "name: PTC 模式": "name: PTC mode",
        "description: 功能完整的编码 Agent，但默认不提供 workflow 工具；其他工具通过 PTC 模式 SDK 呈现，让模型用一个 TypeScript 程序组合多步操作。": "description: A fully capable coding agent that omits the workflow tool by default; the remaining tools are presented through the PTC mode SDK so the model composes multi-step operations in a single TypeScript program.",
    },
    "minimal": {
        "name: 极简模式": "name: Minimal mode",
        "description: 仅提供持久 shell 的单工具编码 Agent。": "description: A single-tool coding agent: persistent shell only.",
    },
    "cordis": {
        "name: 创造模式": "name: Creator mode",
        "description: 用于创建自定义 Agent preset：具备标准模式的全部能力，并提供运行时检查、插件实验和 preset 创作指导。": "description: For authoring custom agent presets: all standard capabilities plus runtime inspection, plugin experimentation, and preset-authoring guidance.",
    },
}

for preset_id, replacements in REWRITES.items():
    path = PRESETS_DIR / preset_id / "preset.yml"
    text = path.read_text(encoding="utf-8")
    for old, new in replacements.items():
        count = text.count(old)
        if count != 1:
            raise SystemExit(
                f"patch-preset-names: expected exactly 1 occurrence of {old!r} in {path}, found {count}"
            )
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")

print(
    "patch-preset-names: rewrote shipped preset names/descriptions to English"
)
