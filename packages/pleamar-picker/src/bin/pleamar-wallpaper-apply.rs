//! `pleamar-wallpaper-apply` entry point: the caches, the wallpaper command
//! and matugen for a new wallpaper.

use std::process::ExitCode;

fn main() -> ExitCode {
    ExitCode::from(pleamar_picker::apply::run() as u8)
}
