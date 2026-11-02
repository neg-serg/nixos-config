//! The pleamar picker's commands, ported from the shell helpers in
//! `files/pleamar/scripts/helpers`:
//!
//! - `pleamar-wallpaper-apply` (`wallpaper-apply`) — everything a new
//!   wallpaper sets besides the picture: the cache files and symlinks, the
//!   wallpaper command, matugen;
//! - `pleamar-wallpaper-still` (`wallpaper-still`) — the still image of a
//!   wallpaper, a cached ffmpeg frame for a video;
//! - `pleamar-picker` (`picker-toggle.sh`) — the wallpaper deck's command
//!   line, `pleamar --say picker …` plus `systemctl --user`.
//!
//! The ports keep the shell's argv, stdout/stderr, exit codes and cache files
//! byte for byte. The one deliberate difference is in-process work where the
//! shell spawned a coreutil: `dirname`, `md5sum`/`cut`, `mkdir`, `ln`, `mv`,
//! `rm`, `printf` and `command -v` are reimplemented here (no new runtime
//! tool, and no argv for them to compare). External programs that carry
//! behaviour stay subprocesses with the same arguments: ffmpeg, the still
//! helper, `setsid -f sh -c`, matugen through `nice`, pleamar, systemctl,
//! `tail -n 1` and `sleep 0.1`.

#![forbid(unsafe_code)]

pub mod apply;
pub mod env;
pub mod file;
pub mod md5;
pub mod picker;
pub mod proc;
pub mod quote;
pub mod still;
pub mod text;
