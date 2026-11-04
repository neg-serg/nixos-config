# files/pleamar — the pleamar desktop shell

Port of the Quickshell desktop shell (deleted on 2026-11-02; its QML is in git history, and
`docs/PARITY.md` maps each ported behaviour to the file and line it came from) to
[pleamar](https://github.com/k4ditano/pleamar): a Rust desktop runtime with a declarative `.plm`
scene language and optional sandboxed Luau logic. One scene per shell area (bar, notifications,
panels, lock, ...), each scene independently runnable, restartable and measurable. The plan with
phases, gates and budgets is `/etc/nixos/.agent/plans/2026-10-16-pleamar-superplan.xml` — read it
before writing scenes.

Frozen interfaces for every scene author — scene/IPC catalog, palette and capsule APIs, settings
schema, helper protocol, label/role policy — live in `docs/INTERFACES.md`; read it before writing a
scene, and treat it as the contract the bar, panels, notifications and lock scenes share.

## Layout

- `lib/` — shared scene libraries (palette, capsule, menu, icons). Strict, no scene-specific
  behaviour.
- `shells/<scene>/<scene>.plm` (+ optional `<scene>.luau`) — one directory per scene; directory
  name, scene name and IPC name are the same string.
- `scripts/` — headless smoke render matrix, agent-tree snapshots, and budget measurement wrappers.
- `tests/` — committed expected artifacts: `*.describe.txt` snapshots, golden screenshots, budget
  tables.

## Run one scene by hand

```sh
pleamar --scene files/pleamar/shells/bar/bar.plm --no-hud
```

`--no-hud` leaves out pleamar's own debug/HUD overlay, so what is on screen is the scene. Runtime
settings are read from `~/.local/share/pleamar/<scene>/` — never from this repository.

## Check

```sh
pleamar --check files/pleamar/shells/bar/bar.plm   # one scene
just pleamar-check                                 # every tracked .plm file
just pleamar-geometry                              # the running bar's rects, against its invariants
```

`pleamar --check` is the compiler and the only authority on valid scene syntax: run it after every
edit (see `AGENTS.md`). `just lint` runs the same gate repo-wide via `scripts/dev/check-plm.sh`;
while the pleamar binary is not in `PATH`, the gate prints a skip notice and exits 0.

`just pleamar-geometry` reads `pleamar --say bar describe` and holds the live strip to the rules the
scenes are written by — the 25 px band, the symmetric 4 px side insets, the 7 px gaps, no overlaps —
without asserting any width: widths are content-sized (`vol.w`, `mic.w`, `ws.w`, `weather.w`), so a
table of numbers would be stale within a day. It skips with a notice when the bar is not running,
and `scripts/dev/check-pleamar-geometry.sh --describe FILE` checks a saved run instead.

## Preview and measure

- `pleamar --docs reference|guide|recipes|logic|measuring` and `pleamar --grammar` — the language
  and tooling reference. Never guess a keyword.
- `pleamar --report` — timing report with the late-frame breakdown; `pleamar --record` — per-frame
  TSV for A/B comparisons.
- Headless rendering uses `PLEAMAR_WM_AUTOSTART` plus `PLEAMAR_HEADLESS_AT`, `PLEAMAR_HEADLESS_PNG`
  and `PLEAMAR_HEADLESS_INPUT` (synthetic input), so a scene can be previewed and screenshotted
  without a session.
- `pleamar-smoke` (PNG matrix), `pleamar-describe-snap` (`pleamar --say NAME describe` snapshots)
  and `pleamar-measure` (`--report` + cgroup numbers into `tests/evidence/`) wrap this. They are
  hermetic by default (temp HOME/XDG sandbox); `--soft` renders on Mesa lavapipe when the GPU is not
  reachable (agent sandboxes).
- `just pleamar-cpu` (`scripts/dev/pleamar-login-cpu.sh`) — what the shell spent on CPU at login. A
  scene's `CPUUsageNSec` is cumulative from its unit's start, so the first minute is the only time
  the login burst (compiling the `.plm`, spawning the workers, the first frames) is still the whole
  number. `pleamar-login-cpu.timer` records every pleamar unit's counters a minute after the session
  target, one file per login under `~/.local/state/pleamar/login-cpu/`; the command prints that
  window next to the live counters (CPU seconds, % of one core, RSS and peak, restarts) and takes
  `--json` or `--watch SECONDS` for a script or for right now.
