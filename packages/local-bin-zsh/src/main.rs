//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this binary:
//! `iommu-info`, `music-rename`, `read_documents`, `pl` and `music-tui`. Running
//! the binary under any other name prints the list of commands.

use std::ffi::OsStr;
use std::path::Path;

use local_bin_zsh::{iommu_info, music_rename, music_tui, pl, read_documents};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn())] = &[
    ("iommu-info", iommu_info::entry),
    ("music-rename", music_rename::entry),
    ("read_documents", read_documents::entry),
    ("pl", pl::entry),
    ("music-tui", music_tui::entry),
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

    let mut usage = String::from("local-bin-zsh: invoke one of these names:\n");
    for (command, _) in COMMANDS {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    std::process::exit(2);
}
