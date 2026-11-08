# Superiority matrix — PH4-V verification (2026-11-08)

Scope: the `superiority-matrix` rows M1–M14 of `.agent/plans/2026-10-16-pleamar-superplan.xml`,
measured on trantor against the live session, which has been the only shell since the 2026-11-02
cutover. The machine-readable rows are in `2026-11-08-superiority.tsv`; this note names every unmet
target and its cause.

## Method

- Units and caps:
  `systemctl --user show -p MemoryCurrent -p MemoryPeak -p CPUUsageNSec -p MemoryMax`.
- CPU: `CPUUsageNSec` sampled at t0 and t+60 s and divided by the window; this is the cgroup, so it
  includes the commands the scenes spawn, not just their own threads.
- Frames and the renderer's own cost: `pleamar --report bar` for 30 s at rest (360 frames, 12 fps,
  so the pointer was not on the strip during the window).
- Startup: the last `render · first frame N ms after starting` line per unit in the journal.
- Agent tree: `pleamar --say <scene> describe` timed five times; the committed snapshots under
  `files/pleamar/tests/*.describe.txt` are the durable form.
- Isolation: `systemctl --user kill -s KILL pleamar-osd`, polled with `is-active`; the other units
  and the bar's IPC were checked while it was down.
- Gates: `just pleamar-check` (25 scenes), `scripts/dev/check-plugin-sandbox.sh`.
- Memory ceilings: every scene unit carries `MemoryMax=512M`.

Caveats: the agent's own commands (five describe calls, systemctl reads) ran during the CPU window;
the renderer's own number is the `--report` figure. The session started 2026-11-06 17:59 and some
units were restarted during development on 2026-11-08 (the bar at 08:56, osd at 09:01), so this is a
snapshot of a long-lived session, not of a fresh login.

## Result

| Verdict      | Rows                                 |
| ------------ | ------------------------------------ |
| pass         | M3 (bar), M5, M6, M8, M12, M13, M14  |
| partial      | M9, M10, and M3's whole-session half |
| fail         | M1, M2                               |
| miss         | M7 (by 0.1 s)                        |
| not measured | M4, M11                              |

The port is clearly ahead on isolation (M7's other half), plugin safety (M12), agent-drivability
(M6), config safety (M5), the dev loop (M8), scene complexity (M14: the notifications scene is 1436
properties / 400 zones against the 19 151 / 4 168 it compiled to on 2026-10-16) and startup (M3: 236
ms to the bar's first frame). It is **not** ahead on idle memory or idle CPU.

### M1 — idle memory: 112.0 MB against the 60 MB target (hard ceiling 128 MB: within)

Total cgroup current across the five running scenes: bar 73.9 MB, notifications 19.9, launcher 9.1,
toast 4.6, osd 4.4; peaks 80/27/24/16/15. The bar's own RSS is 112 MB in `--report`, and the bar is
the whole story: its atlas, services and settings caches are one process.

Cause: the scenes are five processes by design (the plan's isolation requirement), and the bar
carries everything the reference split across Quickshell's shared process. For comparison, the
plan's 2026-10-16 baseline for Quickshell was 93.7 MiB cgroup current / 110.4 MB VmRSS; the port's
total is 112.0 MB cgroup, so the aggregate memory claim of the plan is **not met** — it is roughly
at parity with the shell it replaced, not 45 % below it. A larger share is the bar's picture/atlas
cache, which grew with the ported widgets since the 2026-10-16 dual-run number (bar 52.5 MB then).

### M2 — idle CPU: 6.75 % of a core against the 1 % target

Bar 5.86 %, launcher 0.28, notifications 0.27, toast 0.26, osd 0.08. The renderer is not the
problem: `--report` measures the scene's own process at 1 % of a core, with paint 0.06 ms and rules
0.04 ms per round at the 12 fps rest pace (the other 83 ms of each round is waiting for the screen).
The rest of the cgroup figure is child processes: the bar polls services every 1–4 s and several of
them spawn a command (`hyprctl devices`, `ps`-based sysmon, `ip`, `ping`, `mpc`, `playerctl`,
`genlc`, weather fetch), which is where the seconds go.

For comparison the plan records Quickshell at ~4 % of one core. The port's 6.75 % is worse, so the
"≤ 1 % idle" target is missed twice over: not met by the port, and not met by the reference either.

### M7 — crash isolation: 5101 ms against the 5 s target

`SIGKILL` on `pleamar-osd` brought it back after 5101 ms: `RestartSec=5` from the user-unit preset
plus a 46 ms first frame. The isolation half holds perfectly — bar, launcher, notifications and
toast stayed active, and `pleamar --say bar describe` answered while osd was down. The miss is the
systemd backoff, not the scene; a 2 s `RestartSec` for shell scenes would clear the target at the
cost of faster restart storms (five scenes share the preset).

### Blocked rows

- **M4** (animation while the logic is blocked): needs a test scene that blocks Luau and a frame
  capture; neither exists on this host.
- **M10** (headless render matrix) and **M11** (portability): `pleamar-smoke --require-render` exits
  2 with "no renderer available" — `pleamar-wm` is not installed and there is no nested
  `sway`/`cage` + `grim` in the closure. The compile matrix still covers 25/25 scenes and the
  describe snapshots are committed, so the rows are partial, not zero.

### The 24 h and shadow-run criteria

The shell has been the only shell since the 2026-11-02 cutover and the session has been up for 39
hours, but there was no dedicated 24 h undisturbed run, and the "alongside Quickshell" shadow run
cannot be re-established: the Quickshell tree was deleted at the cutover. Development restarts on
2026-11-08 reset the per-unit counters. This is a deviation from the plan's exit criterion: the
artifacts exist, the 24 h proof was replaced by a 39 h live session with documented restarts.

## What would close the unmet rows

1. M1: find the bar's atlas and service-cache cost (`--report` memory, then the scene's images),
   then either split the bar's picture cache or accept 112 MB and amend the budget; the 60 MB target
   predates the ported widget set.
1. M2: move the 1–4 s external polls into the runtime (or batch them in one helper), and measure the
   bar with the pointer off the strip again; the renderer is already at 1 %.
1. M7: `RestartSec=2` for scene units (a preset change), then re-run the SIGKILL test.
1. M4/M10/M11: install `pleamar-wm` (or a nested compositor + `grim`) and re-run
   `pleamar-smoke --require-render`; M4 additionally needs a logic-blocking fixture.
