//! Rust port of `packages/local-bin/bin/hypr-resize-proportional`.
//!
//! Resizes the active floating window by a percentage while preserving its
//! aspect ratio. `hyprctl` and `bc` stay subprocesses with the original argv
//! (`bc` is the original's numeric evaluator, so a host without it keeps the
//! original's behaviour); the JSON access, the clamping and bash's arithmetic
//! diagnostics are native. The arithmetic diagnostics carry the original line
//! numbers, because bash prints them for values bc cannot turn into integers.

#![forbid(unsafe_code)]

use std::os::unix::ffi::OsStrExt;

use local_bin_desktop::env;
use local_bin_desktop::json::{self, Json};
use local_bin_desktop::proc::{Cmd, Input, Sink};
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let percentage = match arguments.next() {
        Some(value) if !value.as_bytes().is_empty() => value.as_bytes().to_vec(),
        _ => env::parameter_error(
            &program,
            7,
            b"1",
            b"Usage: hypr-resize-proportional [+/-]PERCENT",
        ),
    };

    let window = Cmd::new("hyprctl")
        .args(["activewindow", "-j"])
        .stdout(Sink::Capture)
        .diag(&program, 9)
        .run();
    if window.code != 0 {
        std::process::exit(1);
    }
    let window_value = Json::parse(&window.stdout).ok();

    // `jq -r '.floating'`: an invalid document prints nothing, a missing member
    // prints `null`; both are "not true".
    let floating = raw_member(&window_value, &["floating"]);
    if floating != b"true" {
        std::process::exit(0);
    }

    let current_width = raw_member(&window_value, &["size", "0"]);
    let current_height = raw_member(&window_value, &["size", "1"]);

    let factor = bc(&program, 20, &percentage, b"1.0 + ", b" / 100.0");
    let new_width = bc_parts(&program, 21, &current_width, &factor);
    let new_height = bc_parts(&program, 22, &current_height, &factor);

    let monitors = Cmd::new("hyprctl")
        .args(["monitors", "-j"])
        .stdout(Sink::Capture)
        .diag(&program, 25)
        .run();
    let monitor = Json::parse(&monitors.stdout)
        .ok()
        .and_then(|value| value.index(0).cloned());
    let monitor_width = match &monitor {
        Some(value) => floor_division(value.get("width"), value.get("scale")),
        None => Vec::new(),
    };
    let monitor_height = match &monitor {
        Some(value) => floor_division(value.get("height"), value.get("scale")),
        None => Vec::new(),
    };

    // Clamp to minimum 200x150 and maximum monitor size.
    let mut width = new_width;
    let mut height = new_height;
    if let Some(value) = arithmetic_or_report(&program, 29, true, &width, None) {
        if value.0 < 200 {
            width = b"200".to_vec();
        }
    }
    if let Some(value) = arithmetic_or_report(&program, 30, true, &height, None) {
        if value.0 < 150 {
            height = b"150".to_vec();
        }
    }
    if let Some(value) = arithmetic_or_report(&program, 31, true, &width, Some(&monitor_width)) {
        if value.0 > value.1 {
            width = monitor_width.clone();
        }
    }
    if let Some(value) = arithmetic_or_report(&program, 32, true, &height, Some(&monitor_height)) {
        if value.0 > value.1 {
            height = monitor_height.clone();
        }
    }

    // Resize: delta from the current size.
    let delta_width = arithmetic_or_report(&program, 35, false, &width, Some(&current_width))
        .map(|value| value.0 - value.1);
    let delta_height = arithmetic_or_report(&program, 36, false, &height, Some(&current_height))
        .map(|value| value.0 - value.1);

    let mut geometry = Vec::new();
    if let Some(value) = delta_width {
        geometry.extend_from_slice(value.to_string().as_bytes());
    }
    geometry.push(b' ');
    if let Some(value) = delta_height {
        geometry.extend_from_slice(value.to_string().as_bytes());
    }

    let outcome = Cmd::new("hyprctl")
        .args(["dispatch", "resizeactive"])
        .arg_bytes(&geometry)
        .diag(&program, 38)
        .run();
    std::process::exit(outcome.code);
}

/// `bc <<< EXPR` with the expression on stdin, as the herestring does.
fn bc(program: &[u8], line: u32, value: &[u8], prefix: &[u8], suffix: &[u8]) -> Vec<u8> {
    let mut expression = prefix.to_vec();
    expression.extend_from_slice(value);
    expression.extend_from_slice(suffix);
    expression.push(b'\n');
    let outcome = Cmd::new("bc")
        .stdin(Input::Bytes(&expression))
        .stdout(Sink::Capture)
        .diag(program, line)
        .run();
    text::strip_trailing_newlines(&outcome.stdout).to_vec()
}

/// `bc <<< "$A * $B / 1"`.
fn bc_parts(program: &[u8], line: u32, left: &[u8], right: &[u8]) -> Vec<u8> {
    let mut expression = left.to_vec();
    expression.extend_from_slice(b" * ");
    expression.extend_from_slice(right);
    expression.extend_from_slice(b" / 1\n");
    let outcome = Cmd::new("bc")
        .stdin(Input::Bytes(&expression))
        .stdout(Sink::Capture)
        .diag(program, line)
        .run();
    text::strip_trailing_newlines(&outcome.stdout).to_vec()
}

/// `jq -r` on a path: missing members and missing documents both read as
/// `null` / empty the way jq and `// empty` spell them.
fn raw_member(value: &Option<Json>, path: &[&str]) -> Vec<u8> {
    let Some(root) = value else {
        return Vec::new();
    };
    let mut current = root;
    for member in path {
        let next = match member.parse::<usize>() {
            Ok(index) => current.index(index),
            Err(_) => current.get(member),
        };
        match next {
            Some(next) => current = next,
            None => return b"null".to_vec(),
        }
    }
    current.raw()
}

/// `jq -r '.width / .scale | floor'`; jq prints nothing when the division is
/// invalid (missing or non-numeric members).
fn floor_division(width: Option<&Json>, scale: Option<&Json>) -> Vec<u8> {
    let (Some(width), Some(scale)) = (
        width.and_then(Json::as_number),
        scale.and_then(Json::as_number),
    ) else {
        return Vec::new();
    };
    if scale == 0.0 {
        return Vec::new();
    }
    json::number_text((width / scale).floor())
}

/// Evaluate one or two arithmetic operands with bash's diagnostics. Each
/// failing operand is reported exactly once at its own line, and the caller
/// keeps the shell's control flow (an error leaves the variable unset).
fn arithmetic_or_report(
    program: &[u8],
    line: u32,
    conditional: bool,
    left: &[u8],
    right: Option<&[u8]>,
) -> Option<(i64, i64)> {
    let left_value = match env::bash_int(left) {
        Ok(value) => value,
        Err(error) => {
            env::err(&env::arithmetic_message(program, line, conditional, &error));
            return None;
        }
    };
    let right_value = match right {
        Some(right) => match env::bash_int(right) {
            Ok(value) => value,
            Err(error) => {
                env::err(&env::arithmetic_message(program, line, conditional, &error));
                return None;
            }
        },
        None => 0,
    };
    Some((left_value, right_value))
}

/// Keeps the `OsStrExt` import meaningful for the file-path helpers above.
#[allow(dead_code)]
fn path_bytes(path: &std::path::Path) -> &[u8] {
    path.as_os_str().as_bytes()
}
