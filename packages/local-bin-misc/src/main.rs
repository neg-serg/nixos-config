//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! Every command name in the table is an `argv[0]` symlink to this binary
//! (`default.nix` `postInstall`). The dispatch itself lives in
//! `local_bin_core::multicall`, so all eight ports share one implementation.

use local_bin_core::multicall;

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
    multicall::dispatch("local-bin-misc", COMMANDS);
}
