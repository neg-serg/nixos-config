//! Rust ports of the desktop/media helpers in `packages/local-bin/bin`.
//!
//! Every binary keeps the observable behaviour of its shell original: the same
//! argument handling, the same help/usage bytes, the same stdout/stderr split,
//! the same exit codes, the same environment defaults and the same argv for the
//! external tools, which all stay subprocesses. Pure logic (argument parsing,
//! path handling, formatting, JSON, state files) is native.
//!
//! Shared pieces:
//!
//! * [`env`] — PATH lookup, invocation names, bash-style diagnostics.
//! * [`proc`] — one-shot subprocess helper with the shell's stdio shape.
//! * [`json`] — jq-compatible reader/writer (parsing, `-r` spelling, layout).
//! * [`text`] — the coreutils filters the originals used (`basename`, `head`,
//!   `cut`, `tr`, command-substitution newline stripping).
//! * [`helptext`] — the literal help/usage blocks the scripts printed from
//!   their own comment headers.

#![forbid(unsafe_code)]

pub mod env;
pub mod helptext;
pub mod json;
pub mod proc;
pub mod text;
