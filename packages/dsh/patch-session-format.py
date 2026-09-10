#!/usr/bin/env python3
"""Teach the v0->v1 session migration about the legacy `permission/preset` payload.

dsh 0.1.1's permission-presets wrote `{ preset, origin }` (origin: default |
inferred | selection). 0.1.5-rc.1 dropped the member but froze its released-v0
inventory at `disposition(["preset"])`, so every session created before the
upgrade refuses to migrate:

    permission/preset 0 data has unexpected member "origin"

The web UI then cannot open that session's history at all ("Failed to load
history: ... refuses this format v0 Session") while the v0 artifact stays
untouched on disk.

Fix: strip the obsolete member during the migration — an ordinary legacy
normalizer in the same chain the other legacy shapes already go through — so
the strict inventory stays strict and the written v1 artifact matches the
current schema exactly. Drop this script once upstream admits `origin` in the
released-v0 disposition.

Exact-string + count-asserted: a dsh upgrade that drifts either string fails
the build loudly instead of silently shipping unopenable history again.

Usage: patch-session-format.py <node_modules/@deepseek-ai dir>
"""

import sys

ROOT = sys.argv[1]  # .../node_modules/@deepseek-ai
REL = "dsh-session-format-v0-to-v1/lib/index.js"
PATH = f"{ROOT}/{REL}"

ANCHOR = "function normalizeLegacyTurnStart(event, sessionId) {"
CHAIN_OLD = "normalizeLegacyTurnStart(named, sessionId)"
CHAIN_NEW = "normalizeLegacyTurnStart(normalizeLegacyPermissionPreset(named), sessionId)"

NORMALIZER = (
    """/**
* Drop the legacy `origin` member from a `permission/preset` payload: released
* v0 (0.1.1) wrote { preset, origin } while the frozen inventory admits only
* `preset`, which made every such Session refuse to migrate.
*/
function normalizeLegacyPermissionPreset(event) {
\tif (event.type !== "permission/preset") return event;
\tconst data = event.data;
\tif (data === null || typeof data !== "object" || Array.isArray(data) || !Object.hasOwn(data, "origin")) return event;
\tconst { origin: _origin, ...preset } = data;
\treturn {
\t\t...event,
\t\tdata: preset
\t};
}

"""
    + ANCHOR
)

with open(PATH, encoding="utf-8") as f:
    src = f.read()

for old, new, label in (
    (ANCHOR, NORMALIZER, "normalizeLegacyTurnStart anchor"),
    (CHAIN_OLD, CHAIN_NEW, "migration normalizer chain"),
):
    count = src.count(old)
    if count != 1:
        raise SystemExit(
            f"patch-session-format: {label} found {count} time(s) in {REL}, expected 1"
        )
    src = src.replace(old, new)

with open(PATH, "w", encoding="utf-8") as f:
    f.write(src)

print(
    "patch-session-format: legacy permission/preset `origin` member is stripped during v0->v1"
)
