//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this binary:
//! `gh-issues-export`, `mpd_del_album`, `sx`, `sys-relief`, `vol` and `win-vm`.
//! Running the binary under any other name prints the list of commands.

use std::ffi::OsStr;
use std::path::Path;

use local_bin_zsh_extra::{gh_issues_export, mpd_del_album, sx, sys_relief, vol, win_vm};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn())] = &[
    ("gh-issues-export", gh_issues_export::entry),
    ("mpd_del_album", mpd_del_album::entry),
    ("sx", sx::entry),
    ("sys-relief", sys_relief::entry),
    ("vol", vol::entry),
    ("win-vm", win_vm::entry),
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

    let mut usage = String::from("local-bin-zsh-extra: invoke one of these names:\n");
    for (command, _) in COMMANDS {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    std::process::exit(2);
}
