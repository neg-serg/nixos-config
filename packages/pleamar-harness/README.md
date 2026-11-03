# pleamar-harness

The pleamar developer harnesses as one standalone Rust crate with four binaries. Three are ported from
`files/pleamar/scripts/`; `pleamar-rig` is new here (the idea comes from the sibling pleamar shell
Vitreus, which runs it as `dev/rig`):

| binary                  | original                   |
| ----------------------- | -------------------------- |
| `pleamar-measure`       | `scripts/measure.sh`       |
| `pleamar-describe-snap` | `scripts/describe-snap.sh` |
| `pleamar-smoke`         | `scripts/smoke.sh`         |
| `pleamar-rig`           | — (new; see below)         |

The CLI, stdout/stderr text, exit codes and artifact layout are the shell scripts' own. Usage texts
keep the `*.sh` names for byte parity with `--help`; the binary names are the three above.

## Repository root (the one structural deviation)

The scripts derived `PROJECT_DIR` from `BASH_SOURCE`. A binary in the Nix store has no such path, so
`src/repo.rs` resolves the pleamar tree (`files/pleamar`, the directory holding `shells/` and
`tests/`) in this order:

1. `PLEAMAR_ROOT`, when set. It may point either at the pleamar tree itself
   (`/etc/nixos/files/pleamar`) or at the repository root containing `files/pleamar`.
1. Otherwise, walk up from the current directory to the first directory with a `flake.nix`, and use
   `<that directory>/files/pleamar`.

`--help` needs neither. When neither rule finds the tree, the harness prints
`<tool>: error: cannot locate the pleamar tree from ...; set PLEAMAR_ROOT ...` and exits 2.

## Environment

Same variables as the scripts:

- `PLEAMAR_BIN` (default `pleamar`), `PLEAMAR_WM_BIN` (default `pleamar-wm`);
- `PLEAMAR_TMPDIR` (default `/tmp`) for the per-run sandbox;
- `PLEAMAR_SOFT_ICD` for `--soft`;
- `PLEAMAR_SOCKETS` is discovered/exported by `pleamar-describe-snap` exactly when the shell did it;
- `PLEAMAR_HEADLESS_INPUT` passes through to `pleamar-wm` untouched;
- `VK_ICD_FILENAMES` is honoured when already set; `--soft` never overrides it.

One test seam is added and documented here: `PLEAMAR_CGROUP_ROOT` (default `/sys/fs/cgroup`) lets
the hermetic tests point `measure --unit` at a fixture cgroup. It is unset in every normal run,
where the path is the script's hardcoded one.

## Artifacts

- `measure`: `<out>/<YYYY-MM-DD>-<scene>.tsv`, `.md`, `.log`; default
  `files/pleamar/tests/evidence`;
- `describe-snap`: `<project>/tests/<scene>.describe.txt`;
- `smoke`: `<out>/<YYYY-MM-DD>/<scene>.png` and `.log`; default `files/pleamar/tests/shots`.

`--out`, `--keep-tmp`, `--live`, `--soft`, `--systemd` (describe), `--unit` (measure),
`--require-render`/`--min-bytes` (smoke) keep their defaults and messages.

## pleamar-rig

A copy of the shell in a headless `pleamar-wm`, to look at and poke without touching the desktop in
use:

```sh
pleamar-rig start [--scene bar] [--seconds 900] [--png shot.png] [--at 5] [--input "900,40@2000 down@2500"]
pleamar-rig sync                 # copy the edited tree into the running copy (the shell reloads it)
pleamar-rig say bar describe     # pleamar --say against the rig's socket
pleamar-rig log [40]             # the end of the rig's log
pleamar-rig stop                 # end it and remove the copy
```

The rig root is `$RIG` (default `/tmp/pleamar-rig`): its own `HOME`, `XDG_CONFIG_HOME`,
`XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`, `XDG_RUNTIME_DIR`, `PLEAMAR_CONFIG` and log.
`WAYLAND_DISPLAY`, `WAYLAND_SOCKET`, `DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE` are cleared, so the
copy runs under `pleamar-wm`'s paths; the compositor is started through `setsid`, so `stop` can TERM
the whole group. `--png`/`--at`/`--input` are `PLEAMAR_HEADLESS_PNG`/`_AT`/`_INPUT`; the last one is
inherited when the flag is not given.

What the copy shares with the desktop: the fonts, the network and any program the shell runs by name.
What it cannot show: anything that needs Hyprland (gaps, borders, the glass's blur) — there is no
compositor to ask.

## Deliberate differences

- The repository root comes from `PLEAMAR_ROOT`/the flake instead of the script path (above).
- A flag that is missing its value (`--scene` at the end of argv) is reported by the harness as
  `<tool>: error: --scene needs ...` (exit 2); bash itself printed `line N: 2: ...` and exited 1.
  Every other usage error keeps the shell's text and exit code.
- Signal handling: the shell's `trap cleanup EXIT INT TERM` is a cleanup on normal and error exits
  here; a SIGINT/SIGTERM kills the process without the Rust cleanup, so `--keep-tmp` semantics under
  an interactive Ctrl-C are the one place the scripts were stricter. No unsafe code or
  signal-handler crate is pulled in for it.
- `find` (describe's socket lookup) is in-process; `head`, `tail`, `wc`, `sed`, `awk`, `grep`,
  `cmp`, `cp`, `mv`, `rm`, `mkdir`, `chmod`, `basename`, `dirname`, `tr` and `od` are in-process
  too. None of them is part of the harness contract, and the artifacts/output are byte-identical.
- The renderer's resolved path is used for `grim` (the shell used `$GRIM`), and the resolved `jq` is
  used for the drift key walk. The scripts already did this with their variables; the port had to
  keep the resolved path rather than re-invoking the bare name.

## Tests

```sh
cargo test --locked
```

- `tests/measure.rs`, `tests/describe_snap.rs`, `tests/smoke.rs`, `tests/rig.rs` — end-to-end runs with fake
  external tools (argv logged), temp repos, a zombie scene pid, temp XDG sandbox and no real
  session/network/cgroup. They cover every flag, failure path, output format, cgroup columns (via
  the test seam), PNG verification, renderer fallbacks and the snapshot update/diff paths.
- `tests/parity.rs` — runs the unmodified originals in `tests/parity/original/` (see that
  directory's README) against the same fake tools and compares exit code, stdout, stderr, every
  artifact byte and the sorted argv multisets of the contract commands. It needs `bash`, `jq`,
  `diff`, `sort`, `perl` and coreutils on `PATH`; the Nix check provides them.
- Unit tests in `src/text.rs` pin the masking, `head`/`tail` and diff-summary primitives.

`tests/support/mod.rs` is the shared fixture: it symlinks the standard host tools into a private
directory, so the host's real `pleamar`, `grim`, `sway` or `systemctl` cannot leak into a test
through `PATH`.
