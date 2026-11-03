//! Rust ports of the audio helpers in `packages/local-bin/bin`.
//!
//! Every binary keeps the observable behaviour of its shell original: the same
//! argument handling, the same help/usage bytes, the same stdout/stderr split,
//! the same exit codes, the same environment defaults and the same argv for the
//! external tools, which all stay subprocesses. Shell logic (option parsing,
//! parameter expansion, globbing, loops, arithmetic, text filters that used to
//! be `sed`/`awk`/`grep`/`sort`/`cut`/`wc`/`tr` pipelines, state files and the
//! renoise Config.xml rewrite that used to be a `python3` heredoc) is native.
//!
//! External vocabulary of the batch: PipeWire tools (`pw-link`, `wpctl`,
//! `pw-record`), ALSA (`aconnect`, `amixer`), `pgrep`, `systemctl`, JACK-aware
//! session helpers (`sc-live`, `midi-bridge`), Renoise, `sox`, `mpv`,
//! `vid-info`, `vivaldi`, `wl-copy`, `hyprctl`, `timeout`, `git`, `date`,
//! `mkdir`/`cp`/`mv`, `find`/`xargs`/`sort` and `grep`. All of them are spawned
//! with exactly the argv the script used.
//!
//! Shared pieces:
//!
//! * [`env`] — PATH lookup, invocation names, bash-style diagnostics, streams.
//! * [`proc`] — one-shot subprocess helper with the shell's stdio shape.
//! * [`text`] — the literal text filters the originals used.
//! * [`json`] — the small slice of JSON needed to read `hyprctl clients -j`
//!   without spawning `jq`.
//! * [`helptext`] — the usage blocks the scripts printed from their headers.
//!
//! Known deviations from the shell originals (all of them outside the paths the
//! scripts use in normal operation):
//!
//! * Locale collation: native glob/sort orders are byte orders (the C locale the
//!   tests run under); the shell used the ambient `LC_COLLATE`. Filenames and
//!   window-class lists in non-ASCII locales can therefore differ in order.
//! * `synth`: the `hyprctl clients -j | jq ...` filter is native JSON code, so a
//!   malformed JSON document no longer prints jq's parse diagnostic; the port
//!   falls back to "already running".
//! * `renoise-osc-config`: the rewrite that used to be a `python3` heredoc is
//!   native. Python's UnicodeDecodeError/IOError tracebacks are replaced by one
//!   concise diagnostic line (the exit status stays 1).
//! * Bash's job-control notification for a foreground child killed by SIGTERM
//!   (`Terminated   <source line>`) is not reproduced; the exit status
//!   (128 + signal) is. SIGINT/SIGKILL children behave like the shell.

#![forbid(unsafe_code)]

pub mod env;
pub mod helptext;
pub mod json;
pub mod proc;
pub mod text;
