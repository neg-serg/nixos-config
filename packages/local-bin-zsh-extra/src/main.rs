//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! Every command name in the table is an `argv[0]` symlink to this binary
//! (`default.nix` `postInstall`). The dispatch itself lives in
//! `local_bin_core::multicall`, so all eight ports share one implementation.

use local_bin_core::multicall;

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
    multicall::dispatch("local-bin-zsh-extra", COMMANDS);
}
