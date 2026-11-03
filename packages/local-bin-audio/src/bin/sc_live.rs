//! Rust port of `packages/local-bin/bin/sc-live`.
//!
//! Opens the raw SuperCollider live scene in the `v` wrapper (nvim/scnvim) or
//! prints engine status. `pgrep` and `pw-link` stay subprocesses with the
//! original argv; the `status` word dispatch, the file check and the
//! `grep '^SuperCollider:out_1'` line test are native. The open path keeps the
//! shell's `exec`: the editor replaces the process, and a failing exec reports
//! bash's diagnostic with the original status.

use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

use local_bin_audio::env;
use local_bin_audio::proc::{Cmd, Sink};

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let first = arguments
        .next()
        .map(|value| env::os_bytes(&value).to_vec())
        .unwrap_or_default();

    if first == b"status" {
        status(&program);
        return;
    }

    let home = env::var_or_empty("HOME");
    let mut live = home.clone();
    live.extend_from_slice(b"/notes/music/supercollider/live.scd");
    if !Path::new(OsStr::from_bytes(&live)).is_file() {
        let mut message = b"live scene not found: ".to_vec();
        message.extend_from_slice(&live);
        message.push(b'\n');
        env::err(&message);
        std::process::exit(1);
    }

    // `"${1:-$LIVE}"`: an empty first argument falls back to the scene path.
    let target = if first.is_empty() { live } else { first };
    let mut editor = home;
    editor.extend_from_slice(b"/.local/bin/v");

    let error = Command::new(OsStr::from_bytes(&editor))
        .arg(OsStr::from_bytes(&target))
        .exec();
    env::exec_failure(&program, 40, &editor, &error);
}

fn status(program: &[u8]) {
    env::out_str("=== SuperCollider engine ===\n");
    if pgrep(program, b"scsynth -u 57110", 16) {
        env::out_str("  scsynth: running (port 57110)\n");
    } else {
        env::out_str("  scsynth: NOT running — start via <leader>sc + <leader>sb in live.scd\n");
    }
    if pgrep(program, b"sclang-pwj", 21) {
        env::out_str("  sclang:  running (scnvim session)\n");
    } else {
        env::out_str("  sclang:  not running\n");
    }
    env::out_str("=== PipeWire links ===\n");
    let links = Cmd::new("pw-link")
        .arg("-o")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(program, 27)
        .run();
    let present = links.code == 0
        && links
            .stdout
            .split(|byte| *byte == b'\n')
            .any(|line| line.starts_with(b"SuperCollider:out_1"));
    if present {
        env::out_str("  SuperCollider:out_1/2 -> present (linked by supercollider-link)\n");
    } else {
        env::out_str("  SuperCollider:out_1/2 -> NOT linked (engine off or link service down)\n");
    }
}

/// `pgrep -f PATTERN >/dev/null 2>&1`.
fn pgrep(program: &[u8], pattern: &[u8], line: u32) -> bool {
    Cmd::new("pgrep")
        .arg("-f")
        .arg_bytes(pattern)
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(program, line)
        .run()
        .code
        == 0
}
