//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this binary:
//! `gen-unbound-hosts`, `fetch-covers`, `ren`, `menu-search`, `paths`,
//! `window-activate`, `surfingkeys-server` and `dsh-worktree`. Running the
//! binary under any other name prints the list of commands.

use std::ffi::OsStr;
use std::path::Path;
use std::process::ExitCode;

use local_bin_tools::{
    dsh_worktree, fetch_covers, gen_unbound_hosts, menu_search, paths, ren, surfingkeys_server,
    window_activate,
};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn() -> ExitCode)] = &[
    ("gen-unbound-hosts", gen_unbound_hosts::entry),
    ("fetch-covers", fetch_covers::entry),
    ("ren", ren::entry),
    ("menu-search", menu_search::entry),
    ("paths", paths::entry),
    ("window-activate", window_activate::entry),
    ("surfingkeys-server", surfingkeys_server::entry),
    ("dsh-worktree", dsh_worktree::entry),
];

fn main() -> ExitCode {
    let argv0 = std::env::args_os().next().unwrap_or_default();
    let name = Path::new(&argv0)
        .file_name()
        .map(OsStr::to_owned)
        .unwrap_or_default();

    for (command, run) in COMMANDS {
        if OsStr::new(command) == name {
            return run();
        }
    }

    let mut usage = String::from("local-bin-tools: invoke one of these names:\n");
    for (command, _) in COMMANDS {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    ExitCode::from(2)
}
