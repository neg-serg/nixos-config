//! Rust port of `packages/local-bin/bin/pngoptim`.
//!
//! Losslessly shrink a PNG with `oxipng -o max -z --strip safe`. The tool is
//! still a subprocess with the original argv; the checks, the `_localbin.sh`
//! help dispatch (`-h`, `--help`, `help`, `?` all print the usage on stderr and
//! exit 1) and the diagnostics are native.

#![forbid(unsafe_code)]

use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use local_bin_desktop::env;
use local_bin_desktop::helptext::PNGOPTIM_USAGE;
use local_bin_desktop::proc::Cmd;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let first = arguments
        .next()
        .map(|value| env::os_bytes(&value).to_vec())
        .unwrap_or_default();

    if matches!(first.as_slice(), b"-h" | b"--help" | b"help" | b"?") || first.is_empty() {
        env::err(PNGOPTIM_USAGE.as_bytes());
        std::process::exit(1);
    }

    if !Path::new(OsStr::from_bytes(&first)).is_file() {
        let mut message = b"pngoptim: no such file: ".to_vec();
        message.extend_from_slice(&first);
        message.push(b'\n');
        env::err(&message);
        std::process::exit(1);
    }

    if !(first.ends_with(b".png") || first.ends_with(b".PNG")) {
        let mut message = b"pngoptim: not a PNG: ".to_vec();
        message.extend_from_slice(&first);
        message.push(b'\n');
        env::err(&message);
        std::process::exit(1);
    }

    // `need oxipng` warns and keeps going, exactly like the shared helper.
    if !env::which(b"oxipng") {
        env::err_str("pngoptim: missing oxipng\n");
    }

    let outcome = Cmd::new("oxipng")
        .args(["-o", "max", "-z", "--strip", "safe", "--"])
        .arg_bytes(&first)
        .diag(&program, 26)
        .run();
    std::process::exit(outcome.code);
}
