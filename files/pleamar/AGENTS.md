# AGENTS usage for files/pleamar

Scope: everything under `files/pleamar`. The repo-root `AGENTS.md` still applies; the rules here win
where they conflict.

## Pleamar idioms

- Never guess a keyword, option, service field or event. Start with `pleamar --check <scene>`: the
  compiler is the source of truth, and for a typoed key its diagnostic names the fix. Only when the
  diagnostic is ambiguous, look the keyword up in `pleamar --grammar` / `pleamar --docs reference`,
  piping the stream through `rg`; a full `--docs guide|recipes` dump is for behavioural questions.
- Write in pleamar terms: springs, rules, services, Luau condition logic. This tree knows no QML: no
  QML names, types, imports or file structure. Port behaviour, do not transliterate Quickshell
  files.
- A scene passes `--check` on its own and survives its own restart; unknown or typoed keys are
  defects, not configuration.

## Scene naming

- One directory per scene: `shells/<scene>/<scene>.plm` (+ `<scene>.luau`). Directory name == scene
  name == IPC name (`pleamar --say <scene> ...`); do not introduce aliases.
- Shared code lives in `lib/` and is imported explicitly; scenes do not reach into each other's
  directories.

## Settings and state

- Per-scene settings live under `~/.local/share/pleamar/<scene>/`, never in this repository.
  Defaults and clamps belong in scene code, the user file is read/written at runtime.
- The repo holds scenes and libraries. Expected test artifacts live under `files/pleamar/tests/` and
  are written by the harness, not hand-edited.

## The reference the port was made from

- The Quickshell tree (`files/quickshell`) was deleted on 2026-11-02 — port complete, PARITY closed.
  It is **not** on disk any more, so do not look for it and do not write a path to it: the reference
  is git history (`git show 53a229862^:files/quickshell/greeter/lock/LockContent.qml`) and
  `docs/PARITY.md`, which names the QML file and line behind every ported behaviour. A scene comment
  that cites `LockContent.qml:244-253` is pointing there.
- Nix integration (package, per-scene units, `features.gui.pleamar.enable`, deployment) lives
  outside this subtree and is owned by the integration task; scene work does not edit `modules/`,
  `packages/` or the flake.
- English only in every file; comments included.

## Gates

- Per edit: `pleamar --check <file>`. For a compile defect that is the whole loop: fix, re-run, stop
  when it reports ok.
- Handoff gates (`just pleamar-check` for all tracked `.plm`, `just lint`) run at the end of the
  task, not after each fix.
- Behavioural harnesses (`pleamar-smoke`, `pleamar-describe-snap`) need `pleamar-wm`; when it is
  absent they cannot run — report that and stop, do not read their scripts to find a way around it.
- The bar's live geometry has its own gate: `just pleamar-geometry` (insets, band, gaps, overlaps,
  no widths — `docs/INTERFACES.md` §3.6). It needs the running scene and skips with a notice
  otherwise; `scripts/dev/check-pleamar-geometry.sh --describe FILE` checks a saved run.
- Commit scope: `[gui/pleamar] <Area>: <imperative summary>`.
