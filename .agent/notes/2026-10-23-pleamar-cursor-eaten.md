# Hand-over to the pleamar session: pleamar eats the mouse cursor

Reported by the user through another agent session (qs-wallpaperpicker) on
2026-10-23. Translated from Russian; in the user's own words the point is that
pleamar "eats the cursor when it appears, unlike quickshell", that this must
stop, and that the difference is an inconsistency rather than a preference.

What is observed: when a pleamar scene appears (the launcher, the panels), the
mouse cursor disappears. The Quickshell config does not behave that way.

## What the tree says

- `files/pleamar/shells/launcher/launcher.plm:75` — `keyboard: exclusive while open`;
  the comment above it (lines 66-68) explains that exclusive focus is what makes
  type-to-filter work without a click first.
- `files/pleamar/shells/lock/lock.plm:70` — `keyboard: exclusive while locked`.
- `files/pleamar/shells/lock/preview.plm:42` — `keyboard: on_demand` (the preview).
- The Quickshell config (`files/quickshell/**`) never requests keyboard focus at
  all: neither `WlrKeyboardFocus` nor `keyboardFocus` appears there, so the bar's
  layer surfaces never take it.

## Hypothesis to check

The hiding correlates with `keyboard: exclusive` on a layer surface: a compositor
treats such a surface as the input owner and hides the cursor while it is
focused. Two ways out, to be measured rather than guessed:

1. `keyboard: on_demand` — focus on click; verify that the launcher's
   type-to-filter still works without a click first.
2. keep `exclusive` and restore the cursor explicitly (a scene-level cursor shape
   if pleamar supports one).

Verify on the live system: open the scene, look at the cursor, then repeat with
`on_demand`. This session changed nothing in pleamar's files.
