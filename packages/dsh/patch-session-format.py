#!/usr/bin/env python3
"""Make the v0->v3 Session migration read logs written by the released 0.1.x line.

Three incompatible shapes in the released-v0 inventory reject artifacts that
0.1.1 actually wrote, so pre-upgrade Sessions refuse to migrate and the web UI
cannot open their history ("Failed to load history: ... refuses this format v0
Session"). Each is an ordinary legacy normalizer, the same kind the migration
already carries for other retired shapes:

1. `permission/preset` carried `origin` (0.1.1's permission-presets wrote
   `{ preset, origin }` with origin: default | inferred | selection) while the
   frozen inventory admits only `preset` -> strip the obsolete member.

2. `subagent/descriptor` carried version 2 (SUBAGENT_DESCRIPTOR_VERSION was 2
   in 0.1.1, 3 in 0.1.5) while the frozen inventory demands version 3 -> bump
   the stamp. v3 only added the optional `agentReasoningEffort` field, so no
   value is invented.

3. Plugin-owned events the installed vocabulary does not know (e.g.
   dsh-widgets' `tool/bash-live-*`, written with `ignorable: true`) are refused
   by a v0 migration "even when ignorable", while the current v1/v3 READ side
   already tolerates exactly this shape -> let the migration admit and pass
   them through unchanged (dropping them would leave seq gaps in the target
   artifact, which the format rejects).

Exact-string + count-asserted: a dsh upgrade that drifts any anchor fails the
build loudly instead of silently shipping unopenable history again. Drop this
script once upstream's released-v0 inventory matches what 0.1.x actually wrote.

Usage: patch-session-format.py <node_modules/@deepseek-ai dir>
"""

import sys
from functools import partial

from patchlib import normalizer, patch_file

ROOT = sys.argv[1]  # .../node_modules/@deepseek-ai

patch = partial(patch_file, ROOT, prog="patch-session-format")


PERMISSION_DOC = """/**
* Drop the legacy `origin` member from a `permission/preset` payload: released
* v0 (0.1.1) wrote { preset, origin } while the frozen inventory admits only
* `preset`, which made every such Session refuse to migrate.
*/"""
PERMISSION_BODY = """function normalizeLegacyPermissionPreset(event) {
\tif (event.type !== "permission/preset") return event;
\tconst data = event.data;
\tif (data === null || typeof data !== "object" || Array.isArray(data) || !Object.hasOwn(data, "origin")) return event;
\tconst { origin: _origin, ...preset } = data;
\treturn {
\t\t...event,
\t\tdata: preset
\t};
}"""
PERMISSION_ANCHOR = "function normalizeLegacyTurnStart(event, sessionId) {"
PERMISSION_CHAIN_OLD = "normalizeLegacyTurnStart(named, sessionId)"
PERMISSION_CHAIN_NEW = "normalizeLegacyTurnStart(normalizeLegacyPermissionPreset(named), sessionId)"

DESCRIPTOR_DOC = """/**
* Promote a legacy v2 `subagent/descriptor` payload to the current v3
* vocabulary: v3 only added the optional `agentReasoningEffort` field, so the
* version stamp is the whole delta. 0.1.1 stamped v2 and the frozen v0
* inventory demands v3, so every Session holding a subagent descriptor refused
* to migrate.
*/"""
DESCRIPTOR_BODY = """function normalizeLegacySubagentDescriptor(event) {
\tif (event.type !== "subagent/descriptor") return event;
\tconst data = event.data;
\tif (data === null || typeof data !== "object" || Array.isArray(data) || data.version !== 2) return event;
\treturn {
\t\t...event,
\t\tdata: {
\t\t\t...data,
\t\t\tversion: 3
\t\t}
\t};
}"""
DESCRIPTOR_ANCHOR = "function normalizeReleasedV0Event(event, sessionId, state) {\n\tconst named = normalizeLegacyCompactionType(event);"
DESCRIPTOR_ANCHOR_NEW = (
    "function normalizeReleasedV0Event(event, sessionId, state) {\n"
    "\tconst named = normalizeLegacyCompactionType(normalizeLegacySubagentDescriptor(event));"
)

IGNORABLE_OLD = '\t\tconst ignorableCurrent = !allowLegacySteering && !currentKnown && record["ignorable"] === true;'
IGNORABLE_NEW = '\t\tconst ignorableCurrent = !currentKnown && record["ignorable"] === true;'

STAGE_OLD = """\ttransformEvent(event, context) {
\t\tconst normalized = normalizeReleasedV0Event(event, this.input.sourceHeader.id, this.state);"""
STAGE_NEW = """\ttransformEvent(event, context) {
\t\t/* A plugin-owned event the frozen v0 inventory does not know, written
\t\t * with `ignorable: true`, is passed through unchanged: the current
\t\t * read side already tolerates that shape, and dropping it here would
\t\t * leave a seq gap the target artifact rejects. */
\t\tif (event["ignorable"] === true && RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) {
\t\t\tcontext.emitEvent(event);
\t\t\treturn;
\t\t}
\t\tconst normalized = normalizeReleasedV0Event(event, this.input.sourceHeader.id, this.state);"""

V1_ADMISSION_OLD = "\tif (RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) throw refusal(`format v1 contains unknown event type ${JSON.stringify(event.type)} at seq ${event.seq}`);"
V1_ADMISSION_NEW = """\tif (RELEASED_V0_EVENT_DISPOSITIONS[event.type] === void 0) {
\t\t/* A plugin-owned event the frozen inventory does not know, written with
\t\t * `ignorable: true`, is passed through unchanged; the v2/v3 admission
\t\t * already tolerates that shape. */
\t\tif (event["ignorable"] === true) {
\t\t\temitSource(state, event, context);
\t\t\treturn;
\t\t}
\t\tthrow refusal(`format v1 contains unknown event type ${JSON.stringify(event.type)} at seq ${event.seq}`);
\t}"""

V23_ADMISSION_OLD = '\tif (disposition === void 0 && !feedback) throw new SessionFormatUnsupportedMigrationError("format v2 to v3 cannot safely transform unclassified event " + event.type);'
V23_ADMISSION_NEW = """\tif (disposition === void 0 && !feedback) {
\t\t/* A plugin-owned `ignorable` event this stage cannot classify is opaque,
\t\t * not a failure — the same tolerance the v3 admission already has. */
\t\tif (event["ignorable"] === true) return;
\t\tthrow new SessionFormatUnsupportedMigrationError("format v2 to v3 cannot safely transform unclassified event " + event.type);
\t}"""

# Per-file replacement tables. Every entry asserts its own occurrence count so
# an upstream drift fails this script (and the build) loudly.
FILES = [
    (
        "dsh-session-format-v0-to-v1/lib/index.js",
        [
            (
                PERMISSION_ANCHOR,
                normalizer(PERMISSION_DOC, PERMISSION_BODY, PERMISSION_ANCHOR),
                "permission/preset origin normalizer",
            ),
            (
                PERMISSION_CHAIN_OLD,
                PERMISSION_CHAIN_NEW,
                "permission/preset normalizer chain",
            ),
            (
                DESCRIPTOR_ANCHOR,
                normalizer(
                    DESCRIPTOR_DOC, DESCRIPTOR_BODY, DESCRIPTOR_ANCHOR_NEW
                ),
                "subagent/descriptor v2 normalizer",
            ),
            (
                IGNORABLE_OLD,
                IGNORABLE_NEW,
                "ignorable-unknown coordinate admission",
            ),
            (STAGE_OLD, STAGE_NEW, "ignorable-unknown pass-through"),
        ],
    ),
    (
        "dsh-session-format-v1-to-v2/lib/index.js",
        [
            (
                V1_ADMISSION_OLD,
                V1_ADMISSION_NEW,
                "format v1 unknown-event admission",
            )
        ],
    ),
    (
        "dsh-session-format-v2-to-v3/lib/index.js",
        [
            (
                V23_ADMISSION_OLD,
                V23_ADMISSION_NEW,
                "format v2 unclassified-event admission",
            )
        ],
    ),
    (
        # The persistence backend runs its migration off-thread through this
        # bundled copy of the same source, so the normalizers must exist there
        # too (the coordinate validator with `ignorableCurrent` does not).
        "dsh-session-persistence-jsonl/lib/worker.cjs",
        [
            (
                PERMISSION_ANCHOR,
                normalizer(PERMISSION_DOC, PERMISSION_BODY, PERMISSION_ANCHOR),
                "permission/preset origin normalizer",
            ),
            (
                PERMISSION_CHAIN_OLD,
                PERMISSION_CHAIN_NEW,
                "permission/preset normalizer chain",
            ),
            (
                DESCRIPTOR_ANCHOR,
                normalizer(
                    DESCRIPTOR_DOC, DESCRIPTOR_BODY, DESCRIPTOR_ANCHOR_NEW
                ),
                "subagent/descriptor v2 normalizer",
            ),
            (
                V1_ADMISSION_OLD,
                V1_ADMISSION_NEW,
                "format v1 unknown-event admission",
            ),
            (
                V23_ADMISSION_OLD,
                V23_ADMISSION_NEW,
                "format v2 unclassified-event admission",
            ),
        ],
    ),
]

for rel, replacements in FILES:
    patch(rel, replacements)

print(
    "patch-session-format: released-0.1.x payloads (permission/preset origin, "
    "descriptor v2, ignorable plugin events) now migrate"
)
