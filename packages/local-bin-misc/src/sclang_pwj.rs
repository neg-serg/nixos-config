//! Rust port of `packages/local-bin/bin/sclang-pwj`.
//!
//! `pw-jack sclang "$@"` is exec'd with the same `LD_LIBRARY_PATH` prefix the
//! shell wrapper exports, so scsynth can load SuperCollider's libraries under
//! PipeWire-JACK.

#![forbid(unsafe_code)]

use std::env;
use std::ffi::OsString;
use std::os::unix::process::CommandExt;
use std::process::Command;

use local_bin_misc::{exec_failure, invocation_name, raw_args};

const SYSTEM_LIB: &str = "/run/current-system/sw/lib";

/// `"/run/current-system/sw/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"`:
/// an unset or empty inherited value contributes no separator.
fn library_path() -> OsString {
    let mut value = OsString::from(SYSTEM_LIB);
    if let Some(inherited) = env::var_os("LD_LIBRARY_PATH") {
        if !inherited.is_empty() {
            value.push(":");
            value.push(inherited);
        }
    }
    value
}

fn main() {
    let error = Command::new("pw-jack")
        .arg("sclang")
        .args(raw_args())
        .env("LD_LIBRARY_PATH", library_path())
        .exec();
    exec_failure(&invocation_name(), 8, "pw-jack", &error);
}
