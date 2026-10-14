#!/usr/bin/env python3
"""Close the interrupted turn a steering splice restarts, so v3 logs migrate.

Released 0.1.x abandons a running turn in some steering races: a user message
is queued through `agent/inbox/spliced` and the next `turn/start` opens
`turn/N+1` while `turn/N` was never closed. The v3->v4 migration already
repairs that shape: `observeRestart` synthesizes the missing `turn/end`
(reason `interrupted`) before the restarting `turn/start`. But the repair
required the splice to be the *immediately preceding* event, while real
artifacts interleave the events that settle the aborted turn
(`assistant/attempt`, `step/end`) between the splice and the restart — the flag
was cleared, no `turn/end` was emitted, and the transformed artifact failed the
target v4 lifecycle check at
dsh-session-format-v3-to-v4/lib/index.js:747 ("turn/start does not open the
expected turn"). The migration then refused the log and every session-search
observation of that history failed (recall reported "session-search
persistence observation failed ... source v3 artifact remains unchanged").

Two corrections, both driven by the deployed corpus (19 abandoned turns over
the 688 v3 logs, every one with a splice pending at the restart):

1. Hold the splice flag until a turn boundary — the restarting `turn/start`
   consumes it, a real `turn/end` discards it — instead of resetting it on
   every event. A splice already consumed inside the aborted turn does not
   erase the evidence either: the turn still needs its synthetic close to
   become readable.
2. Accept `next-step` as well as `next-turn` splices: 0.1.x uses the same
   restart mechanism for messages queued at either boundary (one corpus log
   queues for `next-step` and restarts the turn).

Drop this script once upstream's v3->v4 stage repairs an abandoned turn
regardless of the events between the splice and its restart (the released
v1->v2/v3 readers have the same immediate-predecessor restriction and refuse
the same artifacts).

Exact-string + count-asserted: a dsh upgrade that drifts the anchor fails the
build loudly instead of shipping unreadable history again.

Usage: patch-session-migration.py <node_modules/@deepseek-ai dir>
"""

import sys
from functools import partial

from patchlib import patch_file

ROOT = sys.argv[1]  # .../node_modules/@deepseek-ai

patch = partial(patch_file, ROOT, prog="patch-session-migration")

SPLICE_OLD = '\t\tthis.nextTurnSpliced = event.type === "agent/inbox/spliced" && isSessionFormatJsonObject(data) && data["target"] === "next-turn" && Array.isArray(data["inserted"]) && data["inserted"].length > 0;'
SPLICE_NEW = """\t\t/* A steering splice is consumed by the restarting turn/start; the events
\t\t * that settle the aborted turn (assistant/attempt, step/end) must not clear
\t\t * it, or the synthetic turn/end below is skipped and the v4 reader refuses
\t\t * the artifact. Reset on the next turn boundary instead. */
\t\tif (event.type === "agent/inbox/spliced" && isSessionFormatJsonObject(data) && (data["target"] === "next-turn" || data["target"] === "next-step") && Array.isArray(data["inserted"]) && data["inserted"].length > 0) this.nextTurnSpliced = true;
\t\telse if (event.type === "turn/start" || event.type === "turn/end") this.nextTurnSpliced = false;"""

patch(
    "dsh-session-format-v3-to-v4/lib/index.js",
    [(SPLICE_OLD, SPLICE_NEW, "v3->v4 interrupted-restart splice flag")],
)

print(
    "patch-session-migration: v3->v4 abandoned turns after a next-turn/next-step "
    "splice now synthesize their missing turn/end and migrate"
)
