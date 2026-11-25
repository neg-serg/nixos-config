//! Multicall entry point: the command is selected by `argv[0]`.
//!
//! `default.nix` installs one symlink per command name pointing at this binary.
//! Running the binary under any other name prints the list of commands.
//!
//! `pic-ocr` is the one command whose `entry` returns an [`ExitCode`] instead of
//! exiting from inside, so it is dispatched separately.

use std::ffi::OsStr;
use std::path::Path;
use std::process::ExitCode;

use local_bin_desktop::{
    clip, cursor_stretch, hypr_resize_proportional, kitty_font_zoom, pic_dirs_list, pic_info,
    pic_notify, pic_ocr, pngoptim, screenrec, screenshot_toast, unlock, wl_restore,
};

/// Commands that end the process themselves.
const COMMANDS: &[(&str, fn())] = &[
    ("pic-notify", pic_notify::entry),
    ("screenrec", screenrec::entry),
    ("clip", clip::entry),
    ("screenshot-toast", screenshot_toast::entry),
    ("pic-info", pic_info::entry),
    ("pic-dirs-list", pic_dirs_list::entry),
    ("wl-restore", wl_restore::entry),
    ("unlock", unlock::entry),
    ("kitty-font-zoom", kitty_font_zoom::entry),
    ("cursor-stretch", cursor_stretch::entry),
    ("pngoptim", pngoptim::entry),
    ("hypr-resize-proportional", hypr_resize_proportional::entry),
];

/// Every command name, in usage order.
const NAMES: &[&str] = &[
    "pic-notify",
    "screenrec",
    "clip",
    "screenshot-toast",
    "pic-info",
    "pic-ocr",
    "pic-dirs-list",
    "wl-restore",
    "unlock",
    "kitty-font-zoom",
    "cursor-stretch",
    "pngoptim",
    "hypr-resize-proportional",
];

fn main() -> ExitCode {
    let argv0 = std::env::args_os().next().unwrap_or_default();
    let name = Path::new(&argv0)
        .file_name()
        .map(OsStr::to_owned)
        .unwrap_or_default();

    if name == "pic-ocr" {
        return pic_ocr::entry();
    }
    for (command, run) in COMMANDS {
        if OsStr::new(command) == name {
            run();
            return ExitCode::SUCCESS;
        }
    }

    let mut usage = String::from("local-bin-desktop: invoke one of these names:\n");
    for command in NAMES {
        usage.push_str("  ");
        usage.push_str(command);
        usage.push('\n');
    }
    eprint!("{usage}");
    ExitCode::from(2)
}
