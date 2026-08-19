#!/usr/bin/env python3
"""Rewrite shipped agent-preset metadata (preset.yml) from Chinese to English.

The user's de-Chinese rule covers UI copy, and the preset picker + slash
commands (/mode) render these names/descriptions. The strings below are the
exact upstream literals; a dsh upgrade that drifts any of them fails this
script loudly instead of silently shipping Chinese again.

Usage: patch-preset-names.py <dsh-package-root>
"""
import pathlib
import sys

PRESETS_DIR = pathlib.Path(sys.argv[1]) / "config" / "agent-presets"

# id -> { old literal: new literal }, each old string must occur exactly once.
REWRITES = {
    "code": {
        "name: PTC 模式": "name: PTC mode",
        "description: 具备标准模式的全部能力，并通过 Code Mode SDK 呈现工具，让模型用一个 TypeScript 程序组合多步操作。": "description: All the capabilities of the standard mode; tools are presented through the Code Mode SDK so the model composes multi-step operations in a single TypeScript program.",
    },
    "minimal": {
        "name: 极简模式": "name: Minimal mode",
        "description: 仅提供持久 bash 与 str_replace_editor 的双工具编码 Agent。": "description: A two-tool coding agent: persistent bash and str_replace_editor only.",
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
