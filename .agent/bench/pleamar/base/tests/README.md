# files/pleamar/tests — verification harness

Harness v0 for the pleamar shell (superplan PH0-T3). Everything here is produced by the three
scripts in `files/pleamar/scripts/`; nothing is hand-edited except the committed `*.describe.txt`
snapshots, which are only rewritten through `pleamar-describe-snap --update`.

While `pleamar-wm` is not installed, `pleamar-smoke` still runs its compile matrix and
`pleamar-describe-snap`/`pleamar-measure` refuse a hermetic scene run with a clear message (exit 2)
instead of touching the live session.

## Scripts

### `pleamar-smoke` — headless render matrix

Compiles every scene under `shells/*/*.plm` with `pleamar --check` and renders one PNG per scene
without using the live session: `pleamar-wm headless` when available, otherwise a nested headless
wlroots compositor (`sway` or `cage`) with `grim`. Files whose first lines declare `part` are
includes and are skipped.

```sh
pleamar-smoke                    # every scene
pleamar-smoke --scene proof      # one scene
pleamar-smoke --require-render --seconds 8
pleamar-smoke --out /tmp/shots --min-bytes 2048
```

Flags: `--scene NAME`, `--seconds N` (headless session length, default 8), `--out DIR`,
`--require-render`, `--min-bytes N`, `--live`, `--keep-tmp`, `--soft`, `-h/--help`.
`PLEAMAR_HEADLESS_INPUT` is passed through to `pleamar-wm`. Without a renderer the compile matrix
still runs and the script exits 0 with `RENDER=no-renderer`; `--require-render` turns that into exit
2\. A failed compile, a missing/truncated PNG or a non-zero renderer exit is exit 1.

Artifacts: `tests/shots/<YYYY-MM-DD>/<scene>.png` plus `<scene>.log` (set `--out` to change the base
directory). A stale PNG is deleted before each render, so a failure can never be masked by an older
shot.

### What an empty shot looks like (measured 2026-11-01)

`pleamar-smoke` counts a PNG above `--min-bytes` (1024 by default) as a render, so a scene that
draws nothing at rest passes exactly like one that draws its bar. The empty frame on this host is
**2759 B, 1280x720, one colour** — worth knowing before reading a green matrix.

Run on 2026-11-01 with `sway` from the store on `PATH`, `--require-render --seconds 6`: 10 scenes
checked, 10 rendered, and the sizes split cleanly in two.

| draws content | bytes | colours | nothing at rest | bytes |
| ------------- | ----- | ------- | --------------- | ----- |
| `preview`     | 62824 | —       | `launcher`      | 2759  |
| `lock`        | 25804 | —       | `notifications` | 2759  |
| `bar`         | 10769 | 685     | `overlay`       | 2759  |
| `proof`       | 7671  | —       | `overview`      | 2759  |
|               |       |         | `panels`        | 2759  |
|               |       |         | `toast`         | 2759  |

The six are blank **on purpose**: `panels`, `notifications` and `overview` hold a 1x1 keeper while
their drawers are closed, `overlay` and `toast` have no surface at rest, and the launcher waits for
its shortcut. A scene in that group that starts drawing *something* is worth a look too — the point
is that the matrix cannot tell you either way.

### Shooting a drawer without the live session (verified 2026-10-31)

`pleamar-smoke` renders each scene in its default state, so a drawer — the thing most pixel work is
about — never appears in its shots. One can be shot the same way by hand: a headless wlroots
compositor, the scene on it, the drawer opened through IPC, `grim` of that display.

- **`sway` works; `cage` cannot.** cage 0.3.1 has no layer-shell and the scene exits with
  `panicked at src/platform/wayland.rs:1590: the compositor has no layer-shell: NotPresent`. Neither
  binary is on `PATH` on this host; both are in the store (`sway-1.12`, `cage-0.3.1`) and the store
  path can be used directly.
- The scene registers its IPC socket in `/run/user/1000/pleamar/<scene>.sock` whichever display it
  is on, so `pleamar --say panels 'fact drawer media'` reaches it — the answer names the display.
- **Two scenes of one name may not run at once**: the second takes the socket while the first keeps
  drawing on its own display, which is how a shot came out empty.
- `--seconds N` bounds the run; the compositor and the scene both have to be killed afterwards.
- The palette a scene draws with is the `theme.plm` next to the tree it was started from: the repo
  copy when it is started from `shells/`, the generated one under `~/.config/pleamar` when started
  from there. So a *look* is rehearsed by editing the repo copy and never the user's file — but note
  that `skin.light` is only a flag: flipping it does not turn the repo's dark values into a light
  palette, which takes `pleamar-theme --mode light`.
- A light background for the compositor makes glass legible in the shot:
  `printf 'output * bg #ffffff solid_color\n' > sway.conf` and `sway -c sway.conf`.

### `pleamar-describe-snap` — agent-tree snapshots

Starts one scene hermetically, waits until its socket answers `pleamar --say NAME describe` (retry
until `--timeout`, default 15 s), reads the tree until two reads agree (the socket answers before
the zones are built — one run in four used to capture a bar with its header only), captures it into
`tests/<scene>.describe.txt`, then kills what it started. Without `--update` it diffs the captured
tree against the committed snapshot and fails with a human-readable drift summary (changed top-level
keys plus the first changed lines).

```sh
pleamar-describe-snap proof            # verify
pleamar-describe-snap --update proof   # rewrite snapshot
pleamar-describe-snap --scene proof --timeout 30
```

`SCENE` is a scene name (`shells/<name>/<name>.plm`) or a `.plm` path; with no SCENE and exactly one
scene in the tree it is selected automatically. The snapshot is canonicalised with `jq -S` when the
output is JSON and `jq` is available, so committed and fresh output are compared in the same shape.
Missing snapshot or drift is exit 1. Other flags: `--update`, `--timeout N` (socket wait, default 15
s), `--live`, `--keep-tmp`, `--soft`, `-h/--help`.

Flags of `pleamar-describe-snap`: `--update`, `--scene NAME`, `--timeout N`, `--live`, `--systemd`,
`--keep-tmp`, `--soft`, `-h/--help`.

`--systemd` runs the scene as a transient `--user` unit (`systemd-run`) with the same hermetic
HOME/XDG sandbox, pointed at the live compositor. It exists for agent sandboxes, which cannot open
`/dev/dri` or create Wayland buffers themselves (Vulkan falls back to llvmpipe and the renderer
panics on `get_image_drm_format_properties_ext`); the scene does draw on the real screen for the
second or two it lives. Measured 2026-10-26, it is how the committed snapshots were regenerated.

A snapshot is the tree, not the content the labels hold: the clock's minute, the track that is
playing, the weather, the speakers' level and the media capsule's width follow the host, so
`canonicalize` masks them (`HH:MM`, `«Media: …»`, `«Weather …»`, `"-NN dB"`, `at …,NN …×NN`).

### `pleamar-measure` — budget table

Runs one scene for N seconds and collects, into a TSV: `ps`-based RSS/CPU/ threads, instantaneous
CPU from `/proc/<pid>/stat` deltas, PSS from `smaps_rollup`, and cgroup
`memory.current`/`memory.peak`/`cpu.stat` when `--unit NAME` names the systemd unit running the
scene. In the same window it runs `pleamar --report <scene> --seconds N --out <date>-<scene>.md`.

```sh
pleamar-measure proof --seconds 30
pleamar-measure --scene proof --seconds 60 --interval 2
pleamar-measure --scene bar --unit pleamar-bar.service --seconds 60
pleamar-measure --scene proof --out /tmp/evidence
```

Flags: `--scene NAME`, `--seconds N` (default 20), `--interval N` (default 1), `--unit NAME`,
`--out DIR`, `--live`, `--keep-tmp`, `--soft`, `-h/--help`.

Artifacts: `tests/evidence/<YYYY-MM-DD>-<scene>.tsv` (samples), `.md` (the report) and `.log`
(runner/report output). The table is printed to stdout too. A scene that dies mid-measurement or a
failed `--report` is exit 1; the partial table is kept.

## Committed vs generated

| Path | Kind | | ----------------------------- |
\------------------------------------------------------------------------------------------------------
| | `tests/<scene>.describe.txt` | committed agent-tree snapshot; regenerate with `--update`, review
the diff as a behaviour change | | `tests/shots/**` | generated by `pleamar-smoke`, date-stamped;
promote a reviewed shot deliberately if a golden file is wanted | | `tests/evidence/**` | generated
by `pleamar-measure`, date-stamped; commit only a reviewed baseline, not every run |

## Hermetic environment

By default each script creates a per-run sandbox under `/tmp`
(`mktemp -d /tmp/pleamar-<tool>.XXXXXX`) and points `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
`XDG_CACHE_HOME`, `XDG_STATE_HOME`, `XDG_RUNTIME_DIR` and `PLEAMAR_CONFIG` at it, and clears
`WAYLAND_DISPLAY`/`WAYLAND_SOCKET`. Scenes, sockets and any state they write stay in the sandbox;
nothing lands under `~/.cache`, `~/.local/share` or the developer's session. The sandbox is removed
on exit (`--keep-tmp` keeps it for debugging).

`--live` opts out and keeps the ambient environment. For `pleamar-describe-snap` and
`pleamar-measure` that can start a real surface in the current session (killed afterwards);
`pleamar-smoke` stays headless either way. `pleamar-measure --unit NAME` necessarily uses the
ambient session to reach the unit's `pleamar --say` socket and never starts or stops the unit.

Only `--out`/`--live` targets outside the sandbox are written: the scripts otherwise write inside
`files/pleamar/tests/` and the temp dir only.

## Software Vulkan (`--soft`)

This agent sandbox denies `/dev/dri`, so a renderer here needs a software Vulkan driver. `--soft`
exports `VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json` (Mesa lavapipe)
when that file exists. An already-set `VK_ICD_FILENAMES` is always kept — the flag never overrides
it — and if the ICD file is missing the scripts print a clear warning and continue without it. It is
opt-in, so the developer's real sessions keep using the GPU driver. The path can be overridden with
`PLEAMAR_SOFT_ICD`.

## Missing tools

- `pleamar` missing: every script exits 2 with a message naming `PLEAMAR_BIN`. The harness never
  builds or installs anything.
- `pleamar-wm` missing: `pleamar-smoke` falls back to headless `sway`/`cage` with `grim`; if neither
  exists the render columns are `no-renderer` and `--require-render` fails. `pleamar-describe-snap`
  and `pleamar-measure` exit 2 for a hermetic run; use `--live` (current session) or, for
  `pleamar-measure`, `--unit NAME` (already-running unit).
- In this agent sandbox the built binary needs a wrapper, not a plain path:
  `PLEAMAR_BIN=/tmp/plm-recon/run-pleamar.sh scripts/pleamar-smoke`.

Exit codes, all three scripts: `0` success, `1` a check/render/drift/report failure, `2` bad usage
or a missing required tool/renderer.
