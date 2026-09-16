# dsh TUI: notifications when the agent waits for you

How the TUI tells you that a turn **blocked on a human** — the approval card and the structured
question — and why that is a plugin rather than a fourth `notifyOs` call site in the bundle patch.

## The gap

The bundled notifications are completion-only. `TuiApp` calls `notifyOs()` from exactly three
places, all of them "work finished":

| Trigger                | Title                       |
| ---------------------- | --------------------------- |
| a subagent run ends    | `dsh · <subagent finished>` |
| a workflow run ends    | `dsh · <workflow finished>` |
| a background task ends | `dsh · <task finished>`     |

The angle brackets are an English gloss: the shipped copy is Russian, and this document stays
English-only (see the repository language rule). The literal strings live in the TUI bundle and in
`lib/index.js` respectively.

Nothing fires for the two requests that *stop the turn*: `approval/request` (the approval card) and
`user-questions/request` (the question card). Those are exactly the moments when leaving the
terminal is safe — the agent cannot proceed without an answer, and the card just sits there.

## Why this is a plugin, not another `patch.mjs` fix

`patch.mjs` rewrites `notifyOs()` (`notify-osc`), so a fourth call site was the obvious move. It is
the wrong seam here for three reasons:

- **Anchors.** The approval and question paths live in the `app.ts` monolith and in
  `ApprovalController.handle` / `QuestionController`. Reporting from there means two more
  string-anchored bundle rewrites to keep alive across TUI upgrades — for behaviour the host event
  bus already exposes.
- **Ordering.** Both events are **waterfalls**, and the TUI's own handler does not call `next()` on
  the interactive branch: `ApprovalController.handle` returns a promise that stays pending while the
  card is up. A listener registered after the TUI therefore never runs for the case that matters.
  The plugin registers with `prepend: true` and continues the waterfall itself, so it observes every
  request without changing the outcome. It also registers `global: true`, the dispatch context
  filter the TUI's question handler opts out of the same way — without it a filtered dispatch can
  drop the listener entirely.
- **Lifetime.** A plugin is unmounted and remounted by the loader, so it survives a TUI reinstall
  without a bundle patch.

## How it decides

Per request the plugin arms one `graceMs` timer (default 3000 ms) and clears it as soon as the
request settles:

| Request state                                                            | `next()`                          | Outcome                          |
| ------------------------------------------------------------------------ | --------------------------------- | -------------------------------- |
| auto-approved — always-approve mode, session grant (`t`), allowed prefix | resolves on the next microtask    | timer cleared, **silent**        |
| already pending (a second request while a card is up)                    | resolves with the outer waterfall | silent in the common case        |
| waiting on a human                                                       | stays pending                     | **notification after the grace** |
| plain `emit` (no `next` argument)                                        | not applicable                    | **notification after the grace** |

The grace is what keeps always-approve (yolo) mode quiet: those requests never reach a card, so a
notification there would be noise. A human who answers within 3 s also never gets a notification —
also intended. It cuts the other way too: running ahead of the TUI's handler means requests the TUI
would ignore (another session's agent, a request that never reaches a card) also arm the timer, but
those settle instead of blocking, so nothing is reported for them either.

## Protocol

The sequence is written straight to the process stdout, so it is **just bytes on the pty**: no
session D-Bus, no subprocess, and it works over SSH. Both sequences are control-only — they never
touch the visible text grid, so interleaving them with the renderer is safe.

| Situation                                                               | Protocol | Emitted                     |
| ----------------------------------------------------------------------- | -------- | --------------------------- |
| `KITTY_WINDOW_ID` set, or `TERM` has kitty                              | OSC 99   | `\e]99;;<title — body>\e\\` |
| `TERM_PROGRAM` = `iTerm.app`/`WezTerm`/`ghostty`, or `TERM` has ghostty | OSC 9    | `\e]9;<title — body>\a`     |
| any other terminal                                                      | none     | nothing is written          |

The table mirrors the `notify-osc` patch deliberately, so both channels light up in the same
terminals. Payloads pass through the same sanitising rules (control characters clamped to spaces,
title ≤ 80, body ≤ 200), so an approval reason or a question can never inject its own escape
sequence.

## Copy

| Event                    | Title                            | Body                                                  |
| ------------------------ | -------------------------------- | ----------------------------------------------------- |
| `approval/request`       | `dsh · <approval needed>`        | tool name, plus `reason` when the request carries one |
| `user-questions/request` | `dsh · <agent awaits an answer>` | the first question, falling back to its `header`      |

## Switches

| Knob                        | Effect                                                                                                            |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `/config notify off`        | `prefs.notifyOs = false` in `~/.dsh-tui/prefs.json` — silences this plugin too (one switch for all notifications) |
| `DSH_TUI_SKIP_NOTIFY=1`     | environment kill-switch, same as the built-in path                                                                |
| `DSH_NOTIFY_INPUT=0`        | silences **this plugin only**, leaving the completion notifications alone                                         |
| `DSH_NOTIFY_OSC=0` / `=1`   | force the legacy path off / force OSC 9 even in an unrecognised terminal                                          |
| `graceMs` in the loader row | delay before a still-pending request is reported (default 3000)                                                   |

A missing or corrupt `prefs.json` defaults to enabled — notifications are an optimisation, never a
correctness dependency.

## Failure behaviour

The listener must never disturb the request path. Describing a payload or arming the timer is
wrapped, so a malformed request cannot break an approval; a throwing `next()` is disarmed and
re-thrown unchanged; a `write()` failure is swallowed. Unloading the plugin clears every armed
timer.

## Where it lives / how to verify

- Plugin: `modules/user/nix-maid/apps/dsh-notify-input/lib/index.js`; mounted through the
  `tuiPlugins` list in `dsh-tui.nix`, which generates the loader row (the row id is the package
  name) and seeds the package into the profile.
- Test: `node modules/user/nix-maid/apps/dsh-notify-input/test.mjs` — 71 assertions: the protocol
  table and forced-override cases, the gate matrix (prefs / env / TTY / unknown terminal), the copy
  shapes, and the waterfall semantics (auto-approved request stays silent, pending request notifies
  exactly once, a throwing `next()` propagates, unloading clears the timer).
- Manual check: start a turn that triggers an approval card, leave the Sway/GNOME session idle for
  more than the grace, and the terminal's notification appears. Then answer within 3 s on a second
  request and confirm it does not.

## Limits

- **OSC only.** An unrecognised terminal gets nothing — there is deliberately no `notify-send`
  fallback, because shelling out re-introduces the D-Bus/SSH problem the `notify-osc` patch removed.
  The completion notifications cover that case through the old path; this one is additive.
- **zellij pass-through is unverified** (same caveat as the completion notifications). If
  notifications stop appearing inside zellij, set `DSH_NOTIFY_OSC=0`; unlike the built-in path there
  is no local fallback, so the plugin simply goes quiet.
- The plugin owns notifications only. It does not render, keybind, or change the request outcome.
