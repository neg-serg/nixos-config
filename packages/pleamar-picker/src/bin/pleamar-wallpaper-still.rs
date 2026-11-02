//! `pleamar-wallpaper-still` entry point: the still image of a wallpaper.

use std::process::ExitCode;

fn main() -> ExitCode {
    ExitCode::from(pleamar_picker::still::run() as u8)
}
