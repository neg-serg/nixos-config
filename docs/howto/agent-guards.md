# Agent guards: recovery from loops and stops

A port from the **omp (Oh My Pi)** and **oh-my-opencode (oh-my-openagent)** prompts. Goal: treat the
most frequent real agent failure — "going quiet" and loops (repeated tool calls, repeated reasoning,
"I'll do it now" without action) — as well as abrupt context switches by the user.

## How to use

Guards are short injections into the agent stream when the harness/wrapper detects a condition. They
are inserted as a system message (the `<system-interrupt>` / `<system-injection>` /
`<system-notice>` markers — the agent must treat them as system text, not as user text). Order:
detector → specific guard → the agent continues with one concrete step.

______________________________________________________________________

## 1. Tool-call loop (omp: tool-call-loop-redirect)

Detector: N identical calls of the same tool with the same arguments in a row.

```
<system-interrupt reason="tool_call_loop_detected">
You called {{tool_name}} {{count}} times in a row with the same arguments:
{{arguments_summary}}

Last result (truncated): {{result_summary}}

STOP calling {{tool_name}} with these arguments in this turn.
Use different arguments, a different tool, or wrap up and finish if it is done.
</system-interrupt>
```

______________________________________________________________________

## 2. Reasoning loop (omp: thinking-loop-redirect)

Detector: nearly identical reasoning/replies repeat without progress.

```
<system-interrupt reason="thinking_loop_detected">
Repeating the same plan/summary/intention is looping again. Break the pattern:
- STOP describing planned actions. Make one concrete tool call — the smallest real next step.
- Stuck between options → pick the most boring one that works; act, do not keep deliberating.
- The task is actually finished → give the final answer instead of yet another reasoning.
Do something different from the loop. Act, do not re-plan.
</system-interrupt>
```

______________________________________________________________________

## 3. Unexpected-stop classifier (omp: unexpected-stop-classifier)

Detector: a message promises action but ends without any. Classify with a single word YES/NO.

**This is an unexpected stop (YES):**

- "Need to do the same for the JS worker. Doing it now."
- "Next I will run the tests."
- "I will fix this now."
- "Should I do this for you?"

**This is not a stop (NO):**

- "Task done."
- "Can I help with anything else?"
- "Fix ready, tests pass."

Classifier prompt:

```
Classify whether this assistant message is an unexpected stop: it says it will act/continue/call a tool
and ends without doing so.

Message:
{{message}}

Answer with a single word: YES if it is an unexpected stop; NO otherwise.
```

On YES — insert guard 4.

______________________________________________________________________

## 4. Empty stop — continue (omp: empty-stop-retry)

```
<system-injection>
Stop without a result; the task is not done. Continue: a final answer to the user
or the next mandatory tool call.
Attempt #{{retryCount}}/{{maxRetries}}
</system-injection>
```

______________________________________________________________________

## 5. Intent continuation (omp: auto-continue)

After a session is collapsed/restarted:

```
Resume the user's last intent. Re-read the recent messages above the summary to confirm the last
request. If it cancels earlier plans — follow it. If no work remains — say so briefly; do not invent
work.
```

______________________________________________________________________

## 6. Boulder: uncompleted todos (oh-my-opencode: todo-continuation-enforcer)

The exact injection text from `hooks/todo-continuation-enforcer/constants.ts` (CONTINUATION_PROMPT),
inserted on the `session.idle` event when tasks remain open:

```
[system-directive todo_continuation]
Incomplete tasks remain in your todo list. Continue working on the next pending task.
- Proceed without asking for permission
- Mark each task complete when finished
- Do not stop until all tasks are done
- If you believe all work is already complete, the system is questioning your completion claim.
  Critically re-examine each todo item from a skeptical perspective, verify the work was actually
  done correctly, and update the todo list accordingly.
```

Mechanics (for automation): 2s countdown (toast 900ms, grace 500ms, abort window 3s); exponential
backoff: base 30s, ×2 per failure, max 5 in a row, then a 5 min pause; 5s cooldown; stagnation
detection (max 3). Do not inject while waiting for a user answer (pending-question-detection) or
right after a fresh compaction (compaction-guard, 60s).

______________________________________________________________________

## 7. User interruption (omp: user-interjection)

A user message arrived while working — priority:

```
<system-notice>
User interruption while working: it has priority; it cancels conflicting earlier instructions.
Re-read and make sure the current work reflects the user's intent.
</system-notice>
{{message}}
```

______________________________________________________________________

## 8. Ephemeral side question (omp: btw-user)

The user asked a short side question:

```
<btw>
Ephemeral side question of the current interactive session.
Answer briefly and directly; use the existing conversation context.
NEVER use tools.
NEVER ask clarifying questions.
Question: {{question}}
</btw>
```

______________________________________________________________________

## 9. User is annoyed — a rule for the future (omp: omfg-user)

The user complains about repeating agent behavior. Instead of promises — write one concrete filter
rule (TTSR): a regex condition on the output/tool-argument stream + a narrow scope + a short
correction guide. The condition must catch exactly the offensive output from the current
conversation, not be a broad catch-all.

______________________________________________________________________

## Rollout rules

- Guards 1–4 and 6 are candidates for automation (hooks/wrappers), the rest on a case-by-case basis.
- After any guard the agent must take **one concrete step**, not re-plan.
- Do not insert guards in conflict with a real final answer (classifier #3).
