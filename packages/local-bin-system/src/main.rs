//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this binary:
//! `steam-cloud-fix`, `dsh-statusline`, `sw`, `shade`, `main-menu`,
//! `surfingkeys-extension-patch`, `dsh-url`, `qr`, `pdf2md`, `upstream-radar`,
//! `vsmlrt-models` and `nix-updates`. Running the binary under any other name
//! prints the list of commands.

use std::ffi::OsStr;
use std::path::Path;

use local_bin_system::{
    dsh_statusline, dsh_url, main_menu, nix_updates, pdf2md, qr, shade, steam_cloud_fix,
    surfingkeys_extension_patch, sw, upstream_radar, vsmlrt_models,
};

/// Every command name this binary answers to, in usage order.
const COMMANDS: &[(&str, fn())] = &[
    ("steam-cloud-fix", steam_cloud_fix::entry),
    ("dsh-statusline", dsh_statusline::entry),
    ("sw", sw::entry),
    ("shade", shade::entry),
    ("main-menu", main_menu::entry),
    (
        "surfingkeys-extension-patch",
        surfingkeys_extension_patch::entry,
    ),
    ("dsh-url", dsh_url::entry),
    ("qr", qr::entry),
    ("pdf2md", pdf2md::entry),
    ("upstream-radar", upstream_radar::entry),
    ("vsmlrt-models", vsmlrt_models::entry),
    ("nix-updates", nix_updates::entry),
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

    let mut usage = String::from("local-bin-system: invoke one of these names:\n");
    for (command, _) in COMMANDS {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    std::process::exit(2);
}
