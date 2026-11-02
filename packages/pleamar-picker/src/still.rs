//! `pleamar-wallpaper-still FILE` — the still image of a wallpaper, ported
//! from `files/pleamar/scripts/helpers/wallpaper-still`.
//!
//! An image is its own still (a GIF too: matugen reads its first frame). A
//! video's frame is grabbed with ffmpeg into
//! `$XDG_CACHE_HOME/pleamar/wallpaper-frames/<md5-16>.jpg` and grabbed again
//! when the video is newer. A second in, past any fade from black; the first
//! frame for a clip shorter than that. Nothing to show exits 1 silently.
//!
//! The cache frame is written to `<out>.<pid>.jpg` and renamed into place,
//! like the shell's `mv -f`: a reader never sees a partial frame. The shell's
//! second ffmpeg attempt (`-ss 0`) runs whenever the first did not leave a
//! non-empty file, including the case where ffmpeg exited non-zero but wrote
//! one — the post-loop `[ -s ]` then moves that leftover frame into the cache,
//! and so does this port.

use std::ffi::OsString;
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::{env, file, md5, text};

/// The suffixes the shell matched case-insensitively after `${file,,}`.
const VIDEO_EXTENSIONS: [&[u8]; 5] = [b".mp4", b".webm", b".mkv", b".mov", b".m4v"];

pub fn run() -> i32 {
    let arguments: Vec<OsString> = std::env::args_os().collect();
    let wallpaper = arguments.get(1).cloned().unwrap_or_default();
    let path = Path::new(&wallpaper);

    // `[[ -f $file ]] || exit 1` — an unset FILE is the empty string, and it
    // is not a file, so there is no usage line.
    if !file::is_regular(path) {
        return 1;
    }

    if !is_video(&wallpaper) {
        print_path(&wallpaper);
        return 0;
    }

    let cache = env::cache_lenient();
    let directory = cache.join("pleamar").join("wallpaper-frames");
    let key = md5::hex16(wallpaper.as_bytes());
    let frame = directory.join(format!("{key}.jpg"));

    if file::is_nonempty(&frame) && !file::is_newer_than(path, &frame) {
        print_path(frame.as_os_str());
        return 0;
    }

    // A failed mkdir is not reported by this command in the shell either: the
    // ffmpeg attempts fail next and the exit code is 1.
    let _ = fs::create_dir_all(&directory);
    let temporary = temporary_path(&frame);

    for at in ["1", "0"] {
        let status = Command::new("ffmpeg")
            .args(["-nostdin", "-loglevel", "error", "-y", "-ss", at, "-i"])
            .arg(&wallpaper)
            .args(["-frames:v", "1", "-pix_fmt", "yuvj420p", "-q:v", "2"])
            .arg(&temporary)
            .status();
        if let Ok(status) = status {
            if status.success() && file::is_nonempty(&temporary) {
                break;
            }
        }
    }

    if file::is_nonempty(&temporary) {
        // `mv -f`; a failed rename still leaves the shell printing the path.
        let _ = fs::rename(&temporary, &frame);
        print_path(frame.as_os_str());
        0
    } else {
        let _ = fs::remove_file(&temporary);
        1
    }
}

fn print_path(path: &std::ffi::OsStr) {
    text::write_stdout(&[path.as_bytes(), b"\n"].concat());
}

/// Case-insensitive `*.mp4|webm|mkv|mov|m4v`, the shell's `case ${file,,}`.
fn is_video(path: &std::ffi::OsStr) -> bool {
    let lower: Vec<u8> = path
        .as_bytes()
        .iter()
        .map(|byte| byte.to_ascii_lowercase())
        .collect();
    VIDEO_EXTENSIONS
        .iter()
        .any(|extension| lower.ends_with(extension))
}

/// `$out.$$.jpg`: the output path, the process id, and `.jpg` again.
fn temporary_path(frame: &Path) -> PathBuf {
    let mut bytes = frame.as_os_str().as_bytes().to_vec();
    bytes.extend_from_slice(format!(".{}.jpg", std::process::id()).as_bytes());
    PathBuf::from(OsString::from_vec(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn video_matching_ignores_case() {
        assert!(is_video(std::ffi::OsStr::new("/w/a.mp4")));
        assert!(is_video(std::ffi::OsStr::new("/w/a.MP4")));
        assert!(is_video(std::ffi::OsStr::new("clip.MoV")));
        assert!(!is_video(std::ffi::OsStr::new("/w/a.png")));
        assert!(!is_video(std::ffi::OsStr::new("/w/mp4")));
    }

    #[test]
    fn temporary_name_keeps_the_cache_prefix() {
        let temporary = temporary_path(Path::new("/c/abc.jpg"));
        let displayed = temporary.display().to_string();
        assert!(displayed.starts_with("/c/abc.jpg."));
        assert!(displayed.ends_with(".jpg"));
    }
}
