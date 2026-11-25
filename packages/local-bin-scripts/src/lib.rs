//! Rust ports of the `packages/local-bin/scripts` helpers.
//!
//! The ports keep the observable behaviour of the shell/Python originals: the
//! same argument handling, stdout/stderr split, exit codes, file writes and
//! subprocess argv. Only the logic the originals implemented in their own
//! language (directory walks, sorting, JSON shaping, formatting) is native;
//! every external program is still spawned with the original arguments.
//!
//! All commands ship as one multicall binary dispatched by `argv[0]`; see
//! `src/main.rs`. The byte-level helpers moved to `local-bin-core` once the
//! other local-bin ports needed the same functions, and are re-exported here so
//! the command modules reach them through `crate::env`, `crate::json`, ...

#![forbid(unsafe_code)]

pub use local_bin_core::{env, json, pyfmt, text};

pub mod journal_clean;
pub mod music_highlevel;
pub mod pass_2col;
pub mod punzip;
pub mod pypath;
pub mod tty_log;
