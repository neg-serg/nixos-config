# Subagent contract (ported from the omp subagent-system-prompt)

The structure of the subagent system prompt: Role → Context → Plan → Coop → Completion.

## § Role

`{{agent}}` — who the subagent is and what role it plays in the task.

## § Context

`{{context}}` — the necessary context: files, constraints, references.

## § Plan

The subagent executes a part of the approved plan:

- the assignment outweighs the plan on conflict;
- the plan is inserted into the prompt in full — do NOT re-read it from disk along the way.

## § Coop (coordination)

- Isolated worktree: NEVER change files outside the tree.
- Peers (other live agents) via hub: short messages; before editing a file that may belong to a
  neighbor — ask first; `await` only when you cannot move forward without an answer.

## § Completion (yield protocol)

- No todo narration or progress updates along the way.
- Work is not finished → continue with tool calls; narration only in the terminal yield.
- Terminal result: `yield` without `type`, the result in `data`.
- Incremental sections: `type: string[]` — they accumulate along the way.

## Template

```
§ Role
{{agent}}

§ Context
{{context}}

§ Plan
The assignment is part of the approved plan. On conflict, the assignment outweighs the plan.
Do NOT re-read the plan (in full, below) from disk.
<plan>{{plan}}</plan>

§ Coop
Isolated worktree: {{worktree}}. NEVER change files outside the tree.
Peers: {{peers}}. Coordinate via hub, briefly; before editing a busy file —
ask the owner first.

§ Completion
No todo narration. Continue with tool calls until the work is finished.
Finish: yield with the result in data (or incremental sections of type: string[]).
```
