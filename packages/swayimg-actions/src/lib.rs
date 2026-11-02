//! Rust port of `packages/local-bin/bin/swayimg-actions.sh`.
//!
//! The binary keeps the shell helper's contract:
//!
//! ```text
//! swayimg-actions <action> <file> [dest]
//! ```
//!
//! Actions: rotate-left/right/180/ccw (mogrify), copyname (wl-copy plus the
//! optional ~/.local/bin/pic-notify toast), mv/cp (vicinae dmenu destination
//! picker, remembered last destination, zoxide, IPC `next_file` before mv),
//! wall-mono/fill/full/tile/center/cover (ImageMagick render + swww), and the
//! range actions (anchor in $XDG_DATA_HOME/swayimg/range_mark).
//!
//! Shell quirks retained:
//! - `repeat` is dispatched by `files/gui/swayimg/init.lua` but the shell never
//!   had a `repeat` case, so it is an unknown action here too;
//! - the wallpaper list is written through zsh's `echo`, including escapes;
//! - `range-cp`'s regular path does not create the destination directory,
//!   unlike every other copy/move path.
//!
//! Fixed against the shell: `_range_files` never set `c_line`, so its sed
//! expression was invalid and every range action acted on an empty path. The
//! port locates both ends of the slice (see `range.rs`).
//!
//! The helper is synchronous; `files/gui/swayimg/init.lua` backgrounds it with
//! `&`. There is no sync mode, debug log or status overlay (the old howto
//! described features the script never had).

use std::io::Write;
use std::os::unix::ffi::OsStrExt;

mod actions;
mod bytes;
mod env;
mod ipc;
mod picker;
mod range;
mod screen;
mod tools;

const HELP: &str = include_str!("help.txt");

pub fn run() -> i32 {
    let mut arguments = std::env::args_os();
    let _program = arguments.next();
    let action = arguments.next().unwrap_or_default();
    let file = arguments.next().unwrap_or_default();
    let dest = arguments.next().unwrap_or_default();

    // The help text is lines 2-7 of the old script, extracted verbatim before
    // the script was removed; it is intentionally shell syntax, not prose.
    if action.as_bytes() == b"-h" || action.as_bytes() == b"--help" {
        let _ = std::io::stdout().write_all(HELP.as_bytes());
        return 0;
    }

    let paths = env::Paths::from_env();
    paths.create();
    let _cleanup = env::Cleanup::new(&paths);
    actions::dispatch(&paths, action.as_bytes(), file.as_bytes(), dest.as_bytes())
}
