//! `pleamar-wallpaper-apply FILE [COMMAND]` — everything a new wallpaper sets
//! besides the picture, ported from `files/pleamar/scripts/helpers/wallpaper-apply`.
//!
//! The cache files, in the shell's order:
//!
//! - `~/.cache/pleamar/wallpaper-path` — the still, the producer path the
//!   theme pipeline watches;
//! - `~/.cache/current_wallpaper_source` — a symlink to FILE, what is on
//!   screen;
//! - `~/.cache/current_wallpaper` — a symlink to the still;
//! - `~/.local/state/wl/last-good` — the still, wl-daemon's fallback;
//!
//! then the wallpaper command (`COMMAND`, `{}` replaced by the quoted FILE or
//! the path appended), then matugen on the still through `nice -n 19`.
//!
//! The still comes from the helper beside this binary — `pleamar-wallpaper-still`
//! first, the legacy `wallpaper-still` name second — and without one an image
//! is its own still. The helper's stdout is captured and its trailing newlines
//! stripped, exactly like the shell's `$(…)`.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::Path;
use std::process::{Command, Stdio};

use crate::{env, file, proc, quote, text};

pub fn run() -> i32 {
    let arguments: Vec<OsString> = std::env::args_os().collect();
    let wallpaper = arguments.get(1).cloned().unwrap_or_default();

    // `file=${1:-}`: an absent or empty FILE is usage, not "not found".
    if wallpaper.is_empty() {
        text::write_stderr(&[b"wallpaper-apply: no FILE\n"]);
        return 2;
    }
    let path = Path::new(&wallpaper);
    if !file::is_regular(path) {
        text::write_stderr(&[
            b"wallpaper-apply: '",
            wallpaper.as_bytes(),
            b"' not found\n",
        ]);
        return 1;
    }

    let template = arguments.get(2).cloned().unwrap_or_default();
    let argv0 = arguments.first().cloned().unwrap_or_default();
    let here = file::dirname(&argv0);

    let mut still = OsString::new();
    for name in ["pleamar-wallpaper-still", "wallpaper-still"] {
        let candidate = here.join(name);
        if !file::is_executable(&candidate) {
            continue;
        }
        match helper_still(&candidate, &wallpaper) {
            Some(output) => {
                still = output;
                break;
            }
            None => {
                text::write_stderr(&[
                    b"wallpaper-apply: no still image for '",
                    wallpaper.as_bytes(),
                    b"'\n",
                ]);
                return 1;
            }
        }
    }
    if still.is_empty() {
        still = wallpaper.clone();
    }

    // `set -u` guards HOME on the state path even when XDG_CACHE_HOME is set.
    let Some(home) = env::home() else {
        text::write_stderr(&[b"wallpaper-apply: HOME is not set\n"]);
        return 1;
    };
    let cache = env::cache_with_home(&home);
    let pleamar_cache = cache.join("pleamar");
    let state = env::wl_state(&home);

    // `mkdir -p "$cache/pleamar" "$HOME/.local/state/wl"`; each failure was
    // reported and the shell carried on, so this does too.
    create_directory(&pleamar_cache);
    create_directory(&state);

    // `ln -sfn "$file"` then `ln -sfn "$still"`, both before the text files.
    force_symlink(&wallpaper, &cache.join("current_wallpaper_source"));
    force_symlink(&still, &cache.join("current_wallpaper"));

    // `printf '%s\n'` to the two files, in the shell's order. There used to be a
    // third, `~/.cache/quickshell-wallpaper-path`, kept for the shell that wrote it
    // and its readers; both are gone (the shell on 2026-11-02, the last reader
    // `wl-greeter-sync` on 2026-11-03), so the canonical path above is the only one.
    write_line(&pleamar_cache.join("wallpaper-path"), &still);
    write_line(&state.join("last-good"), &still);

    // The painter: detached in its own session, so it outlives this process.
    if !template.is_empty() {
        let command = wallpaper_command(&template, &wallpaper);
        let status = Command::new("setsid")
            .arg("-f")
            .arg("sh")
            .arg("-c")
            .arg(proc::arg_of(&command))
            .stdin(Stdio::inherit())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        if !matches!(status, Ok(status) if status.success()) {
            text::write_stderr(&[
                b"wallpaper-apply: the wallpaper command failed: ",
                template.as_bytes(),
                b"\n",
            ]);
        }
    }

    // matugen is optional: no matugen on PATH is a clean exit 0. `nice` is the
    // shell's argv too, so a fake can observe the exact command line.
    if proc::command_v("matugen").is_none() {
        return 0;
    }
    match Command::new("nice")
        .args(["-n", "19", "matugen", "image"])
        .arg(&still)
        .args(["--source-color-index", "0"])
        .status()
    {
        Ok(status) => proc::exit_code(status),
        Err(_) => 127,
    }
}

/// `still=$("$cand" "$file")`: stdout captured, stderr passed through, and
/// `None` for a non-zero exit (the shell's `||` error path).
fn helper_still(candidate: &Path, wallpaper: &OsStr) -> Option<OsString> {
    let output = Command::new(candidate)
        .arg(wallpaper)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .ok()?
        .wait_with_output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(OsString::from_vec(
        text::trim_trailing_newlines(&output.stdout).to_vec(),
    ))
}

/// The template with every `{}` replaced by the quoted FILE, or FILE appended
/// with a space when there is no placeholder.
fn wallpaper_command(template: &OsStr, wallpaper: &OsStr) -> Vec<u8> {
    let quoted = quote::quote(wallpaper.as_bytes());
    let template = template.as_bytes();
    let has_placeholder = template.windows(2).any(|window| window == b"{}");
    if has_placeholder {
        text::replace_all(template, b"{}", &quoted)
    } else {
        let mut command = template.to_vec();
        command.push(b' ');
        command.extend_from_slice(&quoted);
        command
    }
}

fn create_directory(path: &Path) {
    if let Err(error) = fs::create_dir_all(path) {
        text::write_stderr(&[
            b"wallpaper-apply: cannot create '",
            path.as_os_str().as_bytes(),
            b"': ",
            error.to_string().as_bytes(),
            b"\n",
        ]);
    }
}

fn force_symlink(target: &OsStr, link: &Path) {
    if let Err(error) = file::force_symlink(Path::new(target), link) {
        text::write_stderr(&[
            b"wallpaper-apply: cannot link '",
            link.as_os_str().as_bytes(),
            b"': ",
            error.to_string().as_bytes(),
            b"\n",
        ]);
    }
}

fn write_line(path: &Path, contents: &OsStr) {
    if let Err(error) = file::write_line(path, contents.as_bytes()) {
        text::write_stderr(&[
            b"wallpaper-apply: cannot write '",
            path.as_os_str().as_bytes(),
            b"': ",
            error.to_string().as_bytes(),
            b"\n",
        ]);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_replaces_every_placeholder_with_the_quoted_path() {
        let command = wallpaper_command(OsStr::new("wl img {} --x {}"), OsStr::new("/w/a b.png"));
        assert_eq!(command, b"wl img /w/a\\ b.png --x /w/a\\ b.png".to_vec());
    }

    #[test]
    fn command_appends_the_path_without_a_placeholder() {
        let command = wallpaper_command(OsStr::new("swaybg -i"), OsStr::new("/w/a.png"));
        assert_eq!(command, b"swaybg -i /w/a.png".to_vec());
    }

    #[test]
    fn command_quotes_shell_specials() {
        let command = wallpaper_command(OsStr::new("wl img {}"), OsStr::new("/w/a'b $c.png"));
        assert_eq!(command, b"wl img /w/a\\'b\\ \\$c.png".to_vec());
    }
}
