//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this binary:
//! `pb`, `any`, `v`, `sclang-pwj` and `renoise-pwj`. Running the binary under any
//! other name prints the list of commands.

use std::ffi::OsStr;
use std::path::Path;

use local_bin_misc::{any, pb, renoise_pwj, sclang_pwj, v};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn())] = &[
    ("pb", pb::entry),
    ("any", any::entry),
    ("v", v::entry),
    ("sclang-pwj", sclang_pwj::entry),
    ("renoise-pwj", renoise_pwj::entry),
];

fn main() {
    let argv0 = std::env::args_os().next().unwrap_or_default();
    let name = Path::new(&argv0)
        .file_name()
        .map(OsStr::to_owned)
        .unwrap_or_default();

    for (command, run) in COMMANDS {
        if OsStr::new(command) == name {
            run();
            return;
        }
    }

    let mut usage = String::from("local-bin-misc: invoke one of these names:\n");
    for (command, _) in COMMANDS {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    std::process::exit(2);
}
