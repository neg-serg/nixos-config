//! Rust port of `packages/local-bin/bin/cursor-stretch`.
//!
//! Toggles hyprdynamiccursors' stretch effect through `hyprctl eval`, because
//! the Lua config parser refuses legacy `keyword` writes. `hyprctl` and
//! `notify-send` stay subprocesses; the getoption JSON is parsed natively.

#![forbid(unsafe_code)]

use std::os::unix::ffi::OsStrExt;

use local_bin_desktop::env;
use local_bin_desktop::json::Json;
use local_bin_desktop::proc::{Cmd, Sink};
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let verb = arguments
        .next()
        .map(|value| value.as_bytes().to_vec())
        .unwrap_or_else(|| b"toggle".to_vec());

    let key = "plugin:dynamic_cursors:enabled";
    // `current=$(hyprctl -j getoption "$key" | jq -r '.bool')`. A missing
    // hyprctl makes jq read an empty input, so the value stays empty; a missing
    // `.bool` member prints `null` (jq's spelling), like the original.
    let option = Cmd::new("hyprctl")
        .args(["-j", "getoption", key])
        .stdout(Sink::Capture)
        .diag(&program, 25)
        .run();
    let current: Vec<u8> = match Json::parse(&option.stdout) {
        Ok(value) => match value.get("bool") {
            Some(flag) => flag.raw(),
            None => b"null".to_vec(),
        },
        Err(_) => Vec::new(),
    };

    let want = match verb.as_slice() {
        b"on" => "true",
        b"off" => "false",
        b"toggle" => {
            if current == b"true" {
                "false"
            } else {
                "true"
            }
        }
        b"status" => {
            let mut message = b"dynamic_cursors enabled=".to_vec();
            message.extend_from_slice(&current);
            message.push(b'\n');
            env::out(&message);
            std::process::exit(0);
        }
        _ => {
            let mut message = b"Usage: ".to_vec();
            message.extend_from_slice(text::basename(env::os_bytes(&argv0)));
            message.extend_from_slice(b" [on|off|toggle|status]\n");
            env::err(&message);
            std::process::exit(2);
        }
    };

    // The leading newline is part of the original snippet: `hyprctl eval`
    // would otherwise read a leading `--` as a flag.
    let snippet =
        format!("\nhl.config({{ plugin = {{ dynamic_cursors = {{ enabled = {want} }} }} }})");
    let evaluated = Cmd::new("hyprctl")
        .args(["eval", &snippet])
        .stdout(Sink::Null)
        .diag(&program, 44)
        .run();
    if evaluated.code != 0 {
        std::process::exit(evaluated.code);
    }

    // `command -v notify-send > /dev/null 2>&1 && notify-send ...`: with no
    // notification daemon in PATH the AND-list leaves status 1, which is the
    // script's exit status under `set -e`.
    if !env::which(b"notify-send") {
        std::process::exit(1);
    }
    let notice = format!("cursor stretch: {want}");
    let outcome = Cmd::new("notify-send")
        .args(["-t", "1200"])
        .arg(notice)
        .run();
    std::process::exit(outcome.code);
}
