# files/pleamar — the pleamar desktop shell

Port of the Quickshell desktop shell (`files/quickshell`, now legacy and read-only) to
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
- `tests/` — committed expected artifacts: `*.describe.json` snapshots, golden screenshots, budget
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
```

`pleamar --check` is the compiler and the only authority on valid scene syntax: run it after every
edit (see `AGENTS.md`). `just lint` runs the same gate repo-wide via `scripts/dev/check-plm.sh`;
while the pleamar binary is not in `PATH`, the gate prints a skip notice and exits 0.

## Preview and measure

- `pleamar --docs reference|guide|recipes|logic|measuring` and `pleamar --grammar` — the language
  and tooling reference. Never guess a keyword.
- `pleamar --report` — timing report with the late-frame breakdown; `pleamar --record` — per-frame
  TSV for A/B comparisons.
- Headless rendering uses `PLEAMAR_WM_AUTOSTART` plus `PLEAMAR_HEADLESS_AT`, `PLEAMAR_HEADLESS_PNG`
  and `PLEAMAR_HEADLESS_INPUT` (synthetic input), so a scene can be previewed and screenshotted
  without a session.
- `files/pleamar/scripts/smoke.sh` (PNG matrix), `describe-snap.sh` (`pleamar --say NAME describe`
  snapshots) and `measure.sh` (`--report` + cgroup numbers into `tests/evidence/`) wrap this. They
  are hermetic by default (temp HOME/XDG sandbox); `--soft` renders on Mesa lavapipe when the GPU is
  not reachable (agent sandboxes).
