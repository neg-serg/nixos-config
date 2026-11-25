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

pub use local_bin_core::env;
pub use local_bin_core::helptext;
pub use local_bin_core::json;
pub use local_bin_core::proc;
pub use local_bin_core::text;

// The commands are modules of this crate; `src/main.rs` dispatches on argv[0].
// They live in `src/bin/` because that is where the per-command sources have
// always been, so each module needs an explicit path.
#[path = "bin/audio_diag.rs"]
pub mod audio_diag;
#[path = "bin/flacspec.rs"]
pub mod flacspec;
#[path = "bin/jam.rs"]
pub mod jam;
#[path = "bin/midi_bridge.rs"]
pub mod midi_bridge;
#[path = "bin/mp.rs"]
pub mod mp;
#[path = "bin/nb.rs"]
pub mod nb;
#[path = "bin/qe.rs"]
pub mod qe;
#[path = "bin/renoise_osc_config.rs"]
pub mod renoise_osc_config;
#[path = "bin/sc_live.rs"]
pub mod sc_live;
#[path = "bin/sc_record.rs"]
pub mod sc_record;
#[path = "bin/shabda.rs"]
pub mod shabda;
#[path = "bin/synth.rs"]
pub mod synth;
