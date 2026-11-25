//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! Every command name in the table is an `argv[0]` symlink to this binary
//! (`default.nix` `postInstall`). The dispatch itself lives in
//! `local_bin_core::multicall`, so all eight ports share one implementation.

use local_bin_core::multicall;

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
    multicall::dispatch("local-bin-scripts", COMMANDS);
}
