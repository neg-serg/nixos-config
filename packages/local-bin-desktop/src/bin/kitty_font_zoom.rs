//! Rust port of `packages/local-bin/bin/kitty-font-zoom`.
//!
//! Zooms the font of the focused kitty window over kitty's remote-control
//! socket. `hyprctl` and `kitten` stay subprocesses with the original argv;
//! the argument handling, the socket probe and the `set-user-vars` parsing are
//! native. The `font_zoom=font_zoom=off` argv of the off/on modes is kept
//! verbatim: it is the original script's (harmless) double prefix.

#![forbid(unsafe_code)]

use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::FileTypeExt;
use std::path::Path;

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
        .unwrap_or_default();

    enum Mode {
        Delta(Vec<u8>),
        Variable,
        Toggle,
    }

    let mode = match verb.as_slice() {
        b"up" => Mode::Delta(b"+0.5".to_vec()),
        b"down" => Mode::Delta(b"-0.5".to_vec()),
        b"reset" => Mode::Delta(b"0".to_vec()),
        b"off" | b"on" => Mode::Variable,
        b"toggle" => Mode::Toggle,
        _ => {
            let mut message = b"Usage: ".to_vec();
            message.extend_from_slice(text::basename(env::os_bytes(&argv0)));
            message.extend_from_slice(b" up|down|reset|off|on|toggle\n");
            env::err(&message);
            std::process::exit(2);
        }
    };

    // `win=$(hyprctl activewindow -j) || exit 0`
    let window = Cmd::new("hyprctl")
        .args(["activewindow", "-j"])
        .stdout(Sink::Capture)
        .diag(&program, 32)
        .run();
    if window.code != 0 {
        std::process::exit(0);
    }
    let pid = match Json::parse(&window.stdout) {
        Ok(value) => match value.get("pid") {
            Some(pid) => pid.raw_or_empty(),
            None => Vec::new(),
        },
        Err(_) => Vec::new(),
    };
    if pid.is_empty() {
        std::process::exit(0);
    }

    let mut socket = b"/tmp/kitty-".to_vec();
    socket.extend_from_slice(&pid);
    let is_socket = std::fs::metadata(Path::new(std::ffi::OsStr::from_bytes(&socket)))
        .map(|meta| meta.file_type().is_socket())
        .unwrap_or(false);
    if !is_socket {
        std::process::exit(0);
    }
    let mut target = b"unix:".to_vec();
    target.extend_from_slice(&socket);

    match mode {
        Mode::Delta(argument) => {
            let _ = Cmd::new("kitten")
                .args(["@", "--to"])
                .arg_bytes(&target)
                .args(["set-font-size", "--"])
                .arg_bytes(&argument)
                .stdout(Sink::Null)
                .stderr(Sink::Null)
                .run();
        }
        Mode::Variable => {
            // The original interpolates `font_zoom=$arg` where $arg is already
            // `font_zoom=<verb>`; the doubled prefix is kept on purpose.
            let argument = format!("font_zoom=font_zoom={}", String::from_utf8_lossy(&verb));
            let _ = Cmd::new("kitten")
                .args(["@", "--to"])
                .arg_bytes(&target)
                .args(["set-user-vars"])
                .arg(argument)
                .stdout(Sink::Null)
                .stderr(Sink::Null)
                .run();
        }
        Mode::Toggle => {
            // `set-user-vars` without arguments prints the active window's
            // variables; the first `font_zoom=` line wins.
            let listing = Cmd::new("kitten")
                .args(["@", "--to"])
                .arg_bytes(&target)
                .args(["set-user-vars"])
                .stdout(Sink::Capture)
                .stderr(Sink::Null)
                .run();
            let mut current: Vec<u8> = Vec::new();
            for line in listing.stdout.split(|byte| *byte == b'\n') {
                if let Some(rest) = line.strip_prefix(b"font_zoom=") {
                    current = rest.to_vec();
                    break;
                }
            }
            let next = if current == b"off" {
                "font_zoom=on"
            } else {
                "font_zoom=off"
            };
            let _ = Cmd::new("kitten")
                .args(["@", "--to"])
                .arg_bytes(&target)
                .args(["set-user-vars", next])
                .stdout(Sink::Null)
                .stderr(Sink::Null)
                .run();
        }
    }
}
