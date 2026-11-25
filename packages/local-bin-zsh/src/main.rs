//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! Every command name in the table is an `argv[0]` symlink to this binary
//! (`default.nix` `postInstall`). The dispatch itself lives in
//! `local_bin_core::multicall`, so all eight ports share one implementation.

use local_bin_core::multicall;

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
    multicall::dispatch("local-bin-zsh", COMMANDS);
}
