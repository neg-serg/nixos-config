//! Rust port of `packages/local-bin/bin/renoise-pwj`.
//!
//! The system `renoise` wrapper already runs under `pw-jack`; this entry point
//! only forwards its argv (and its stdin/stdout/stderr/exit status) through an
//! exec, exactly like the shell original.

#![forbid(unsafe_code)]

use std::os::unix::process::CommandExt;
use std::process::Command;

use crate::{exec_failure, invocation_name, raw_args};

pub fn entry() {
    let error = Command::new("renoise").args(raw_args()).exec();
    exec_failure(&invocation_name(), 7, b"renoise", &error);
}
