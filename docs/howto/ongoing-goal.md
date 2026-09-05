# ongoing Goal — a long-running goal in dsh (how to set one up)

The “ongoing Goal” mechanic is already deployed in the base DSH web profile — no separate plugin or
Nix module is needed. This document covers how it is wired up and how to start/manage a goal.

## What it is

One long-running goal per session (same-session goal): an objective plus a round budget
`maxGoalRounds`, automatic continuation of rounds while the goal is active and armed, and
cards/chips in the GUI. The implementation lives in the base packages of the profile (rows in
`cordis.patch.yml`):

| Patch row             | Package                                | Role                                                       |
| --------------------- | -------------------------------------- | ---------------------------------------------------------- |
| `goal`                | `@deepseek-ai/dsh-goal`                | goal service (`ctx.goals`), event-sourcing from `goal/change` |
| `goal-round-driver`   | `@deepseek-ai/dsh-goal-round-driver`   | auto-continuation of rounds (`agent.followup`) when armed + active |
| `command-goal`        | `@deepseek-ai/dsh-command-goal`        | human command `/goal`                                      |
| `ui-goal`             | `@deepseek-ai/dsh-client-ui-goal`      | GoalBar in the input dock (progress “rounds N/M”)          |
| `tool-goal`           | `@deepseek-ai/dsh-tool-goal`           | model-facing tools (served through Gateway Remote)         |

Goal shape:
`{id, revision, objective, phase, activation (armed/disarmed), roundsStarted, maxGoalRounds, blockedReason}`.
Phases: `active | paused | complete | blocked`. To check the live state, `get_goal` from the session
returns `{goal: null}` when there is no goal.

## How to start

1. In chat, ask the agent to set a long-running goal: the agent calls `create_goal` (`objective` +
   optionally `max_goal_rounds`). Directly from the GUI: `/goal <objective>` creates one;
   `/goal edit <new text>` changes the objective.
1. The goal is created in phase `active` with its activation armed. While it stays armed + active,
   the round-driver continues rounds on its own within the same session (a round = the agent’s next
   turn, `roundsStarted + 1`; the budget is never exceeded).
1. Progress is visible in the GoalBar (chip “rounds N/M”) and in the result card of
   `create_goal`/`get_goal`/`update_goal` (rendered by the dsh-widgets plugin).

## Managing

| Action            | Tool / command                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------- |
| Create            | `create_goal` or `/goal <objective>`                                                        |
| Inspect           | `get_goal` (also `/goal` without arguments)                                                 |
| Change objective  | `update_goal edit` (or `/goal edit <text>`); `maxGoalRounds` stays unchanged                |
| Pause / resume    | `update_goal pause` / `update_goal resume`                                                  |
| Complete          | `update_goal complete`                                                                      |
| Block             | `update_goal blocked` (after the minimum round count; reason in `blockedReason`)            |
| Clear             | `/goal clear` (only while the goal is active/paused)                                        |

After a session resume/fork, an active goal arrives disarmed — re-arm it with `update_goal resume`
(or simply say “continue” — the agent re-arms it itself).

## Limitations

- One goal per session; a new goal on top of an unfinished one is only possible via `/goal clear` or
  `update_goal complete`.
- Editing changes only the objective; `maxGoalRounds` is not changed by `update_goal edit`.
- Rounds run within a single session; the goal is not carried across sessions (disarmed).
- Verified on odin 2026-08-20: `get_goal` responds, the service is alive; no plugin is needed for
  this.
