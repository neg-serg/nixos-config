//! The pleamar developer harnesses, ported from `files/pleamar/scripts/`.
//!
//! Three binaries share this library:
//!
//! - `pleamar-measure` (`measure.sh`) — one scene for N seconds, a budget table
//!   and `pleamar --report`;
//! - `pleamar-describe-snap` (`describe-snap.sh`) — the agent tree captured,
//!   masked, diffed against `tests/<scene>.describe.txt`;
//! - `pleamar-smoke` (`smoke.sh`) — the headless compile/render matrix.
//!
//! The shell scripts found their project directory from `BASH_SOURCE`; the
//! binaries live in the Nix store, so [`repo::project_root`] uses
//! `PLEAMAR_ROOT` or walks up from the current directory to the flake. That is
//! the one deliberate deviation; everything else keeps the shell's argv, stdout
//! and stderr bytes, exit codes and artifact paths.
//!
//! External programs that carry behaviour stay subprocesses with the same argv:
//! `pleamar`, `pleamar-wm`, `ps`, `systemctl`, `systemd-run`, `grim`,
//! `sway`/`cage`, `timeout`, `setsid`, `kill`, `date`, `mktemp`, `getconf`,
//! `id`, `sleep`, `column`, `jq`, `diff`, `sort`, `pgrep` and `find` is
//! reimplemented (its only use was locating the scene socket under
//! `XDG_RUNTIME_DIR`). Coreutils used for formatting (`head`, `tail`, `sed`,
//! `awk`, `grep`, `wc`, `cmp`, `cp`, `mv`, `rm`, `mkdir`, `chmod`, `basename`,
//! `dirname`, `tr`, `od`) are in-process; none of them is part of the harness's
//! contract with the developer.

#![forbid(unsafe_code)]

pub mod ctx;
pub mod describe;
pub mod env;
pub mod measure;
pub mod proc;
pub mod repo;
pub mod scene;
pub mod smoke;
pub mod text;
pub mod usage;
