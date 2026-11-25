//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this
//! binary, so `pass-2col`, `punzip`, `tty-log`, `journal-clean` and
//! `music-highlevel` behave exactly like the former per-command binaries
//! (including the program name they report in diagnostics). Running the binary
//! under any other name prints the list of commands.

use std::ffi::OsStr;
use std::path::Path;

use local_bin_scripts::{journal_clean, music_highlevel, pass_2col, punzip, tty_log};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn())] = &[
    ("pass-2col", pass_2col::entry),
    ("punzip", punzip::entry),
    ("tty-log", tty_log::entry),
    ("journal-clean", journal_clean::entry),
    ("music-highlevel", music_highlevel::entry),
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

    let mut usage = String::from("local-bin-scripts: invoke one of these names:\n");
    for (command, _) in COMMANDS {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    std::process::exit(2);
}
