//! The two external tools the pipeline keeps: ImageMagick and jq.
//!
//! The shell called `magick` for the 48x48 sample and `jq` for `--from-json`;
//! this port does the same, with the same arguments, so pixel values and JSON
//! string semantics cannot drift. Everything else the shell needed (awk,
//! bash, head, tr, date, mktemp, chmod, mv, diff, grep) is in the Rust code.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// `${VAR:-default}`: an unset *or empty* variable takes the default.
pub fn env_bin(variable: &str, default: &str) -> String {
    match std::env::var_os(variable) {
        Some(value) if !value.is_empty() => value.to_string_lossy().into_owned(),
        _ => default.to_string(),
    }
}

/// `command -v`: a name with a slash is a path, anything else is searched in
/// `PATH`; only a regular file with an execute bit counts.
pub fn which(name: &str) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    let direct = Path::new(name);
    if name.contains('/') {
        return is_executable(direct).then(|| direct.to_path_buf());
    }
    let path = std::env::var_os("PATH")?;
    for directory in std::env::split_paths(&path) {
        let directory = if directory.as_os_str().is_empty() {
            PathBuf::from(".")
        } else {
            directory
        };
        let candidate = directory.join(name);
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

fn is_executable(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// `[[ -r $path ]]`: a missing path is unreadable, a directory is readable
/// (the shell only checked access; the later tool decided whether it was an
/// image).
pub fn readable(path: &Path) -> bool {
    fs::metadata(path).is_ok() && fs::File::open(path).is_ok()
}

/// Run the shell's exact ImageMagick command and return its stdout plus
/// whether it succeeded. Its stderr is inherited, as it was in the pipeline;
/// the awk program ran on whatever stdout arrived, and the caller reproduces
/// the `pipefail` decision.
pub fn magick_dump(magick: &str, wallpaper: &Path) -> Option<(Vec<u8>, bool)> {
    let output = Command::new(magick)
        .arg("-define")
        .arg("jpeg:size=384x384")
        .arg(wallpaper)
        .arg("-auto-orient")
        .arg("-colorspace")
        .arg("sRGB")
        .arg("-thumbnail")
        .arg("48x48!")
        .arg("-alpha")
        .arg("off")
        .arg("-depth")
        .arg("8")
        .arg("txt:-")
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output()
        .ok()?;
    Some((output.stdout, output.status.success()))
}

/// `jq -er --arg k KEY '.[$k] | select(type == "string")' FILE`, with stderr
/// discarded and a non-zero status ignored, exactly like the shell's
/// `$(... 2>/dev/null || true)`. Returns the raw stdout on success.
pub fn jq_string(jq: &str, key: &str, file: &Path) -> Option<Vec<u8>> {
    let output = Command::new(jq)
        .arg("-er")
        .arg("--arg")
        .arg("k")
        .arg(key)
        .arg(".[$k] | select(type == \"string\")")
        .arg(file)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    Some(output.stdout)
}
