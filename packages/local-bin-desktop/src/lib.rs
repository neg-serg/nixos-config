//! Rust ports of the desktop/media helpers in `packages/local-bin/bin`.
//!
//! Every binary keeps the observable behaviour of its shell original: the same
//! argument handling, the same help/usage bytes, the same stdout/stderr split,
//! the same exit codes, the same environment defaults and the same argv for the
//! external tools, which all stay subprocesses. Pure logic (argument parsing,
//! path handling, formatting, JSON, state files) is native.
//!
//! Shared pieces:
//!
//! * [`env`] — PATH lookup, invocation names, bash-style diagnostics.
//! * [`proc`] — one-shot subprocess helper with the shell's stdio shape.
//! * [`json`] — jq-compatible reader/writer (parsing, `-r` spelling, layout).
//! * [`text`] — the coreutils filters the originals used (`basename`, `head`,
//!   `cut`, `tr`, command-substitution newline stripping).
//! * [`helptext`] — the literal help/usage blocks the scripts printed from
//!   their own comment headers.

#![forbid(unsafe_code)]

pub use local_bin_core::env;
pub use local_bin_core::helptext;
pub use local_bin_core::json;
pub use local_bin_core::proc;
pub use local_bin_core::text;

// The commands are modules of this crate; `src/main.rs` dispatches on argv[0].
// They live in `src/bin/` because that is where the per-command sources have
// always been, so each module needs an explicit path.
#[path = "bin/clip.rs"]
pub mod clip;
#[path = "bin/cursor_stretch.rs"]
pub mod cursor_stretch;
#[path = "bin/hypr_resize_proportional.rs"]
pub mod hypr_resize_proportional;
#[path = "bin/kitty_font_zoom.rs"]
pub mod kitty_font_zoom;
#[path = "bin/pic_dirs_list.rs"]
pub mod pic_dirs_list;
#[path = "bin/pic_info.rs"]
pub mod pic_info;
#[path = "bin/pic_notify.rs"]
pub mod pic_notify;
#[path = "bin/pic_ocr.rs"]
pub mod pic_ocr;
#[path = "bin/pngoptim.rs"]
pub mod pngoptim;
#[path = "bin/screenrec.rs"]
pub mod screenrec;
#[path = "bin/screenshot_toast.rs"]
pub mod screenshot_toast;
#[path = "bin/unlock.rs"]
pub mod unlock;
#[path = "bin/wl_restore.rs"]
pub mod wl_restore;
