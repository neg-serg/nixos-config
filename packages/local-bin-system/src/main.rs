//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! Every command name in the table is an `argv[0]` symlink to this binary
//! (`default.nix` `postInstall`). The dispatch itself lives in
//! `local_bin_core::multicall`, so all eight ports share one implementation.

use local_bin_core::multicall;

use local_bin_system::{
    dsh_statusline, dsh_url, main_menu, nix_updates, pdf2md, qr, shade, steam_cloud_fix, sw,
    upstream_radar, vsmlrt_models,
};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn())] = &[
    ("steam-cloud-fix", steam_cloud_fix::entry),
    ("dsh-statusline", dsh_statusline::entry),
    ("sw", sw::entry),
    ("shade", shade::entry),
    ("main-menu", main_menu::entry),
    ("dsh-url", dsh_url::entry),
    ("qr", qr::entry),
    ("pdf2md", pdf2md::entry),
    ("upstream-radar", upstream_radar::entry),
    ("vsmlrt-models", vsmlrt_models::entry),
    ("nix-updates", nix_updates::entry),
];

fn main() {
    multicall::dispatch("local-bin-system", COMMANDS);
}
