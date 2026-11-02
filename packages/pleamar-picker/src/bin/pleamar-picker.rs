//! `pleamar-picker` entry point: the wallpaper deck's command line.

use std::process::ExitCode;

fn main() -> ExitCode {
    ExitCode::from(pleamar_picker::picker::run() as u8)
}
