//! Rust port of `packages/local-bin/bin/pic-dirs-list`.
//!
//! Keeps a zoxide index of the directories under `$XDG_PICTURES_DIR` and
//! refreshes it when inotify reports a directory event. `inotifywait` and
//! `zoxide` stay subprocesses with the original argv; the `find -maxdepth 3`
//! walk (and its `.git` exclusion) is native.

#![forbid(unsafe_code)]

use std::ffi::OsStr;
use std::io::{BufRead, BufReader};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::{Command, Stdio};

use local_bin_desktop::env;
use local_bin_desktop::helptext::PIC_DIRS_LIST_HELP;
use local_bin_desktop::proc::Cmd;
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let first = arguments
        .next()
        .map(|value| value.as_bytes().to_vec())
        .unwrap_or_default();

    // `help_from_header 2 2 "$@"` prints the single usage line and exits 0.
    if matches!(first.as_slice(), b"-h" | b"--help") {
        env::out_str(PIC_DIRS_LIST_HELP);
        std::process::exit(0);
    }

    let pictures = match env::var_nonempty("XDG_PICTURES_DIR") {
        Some(value) => value,
        None => std::process::exit(0),
    };
    if !env::which(b"inotifywait") {
        std::process::exit(0);
    }
    let dir = text::strip_one_trailing_slash(&pictures).to_vec();

    index_directories(&program, &dir, 18);

    // `inotifywait -q -m -e create -e delete "$dir" | while read -r _ events _`
    let child = Command::new("inotifywait")
        .args(["-q", "-m", "-e", "create", "-e", "delete"])
        .arg(OsStr::from_bytes(&dir))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(error) => {
            if error.kind() == std::io::ErrorKind::NotFound {
                env::err(&env::not_found_message(&program, 21, b"inotifywait"));
            }
            std::process::exit(0);
        }
    };
    if let Some(stdout) = child.stdout.take() {
        for line in BufReader::new(stdout).lines() {
            let line = match line {
                Ok(line) => line,
                Err(_) => break,
            };
            let fields = text::words(line.as_bytes());
            if fields.len() >= 2 && contains(fields[1], b"ISDIR") {
                index_directories(&program, &dir, 27);
            }
        }
    }
    let _ = child.wait();
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    text::find(haystack, needle).is_some()
}

/// `find DIR -maxdepth 3 -type d ! -path DIR/.git ! -path 'DIR/.git/*'`, then
/// `zoxide add --` for every directory when zoxide is in PATH.
fn index_directories(program: &[u8], dir: &[u8], line: u32) {
    let root = Path::new(OsStr::from_bytes(dir));
    let mut directories: Vec<std::path::PathBuf> = Vec::new();
    collect(root, 0, &mut directories);
    let mut git = dir.to_vec();
    git.extend_from_slice(b"/.git");
    let mut git_prefix = git.clone();
    git_prefix.push(b'/');
    for path in directories {
        let bytes = path.as_os_str().as_bytes();
        if bytes == git.as_slice() || bytes.starts_with(&git_prefix) {
            continue;
        }
        if !env::which(b"zoxide") {
            continue;
        }
        let _ = Cmd::new("zoxide")
            .args(["add", "--"])
            .arg(path.as_os_str())
            .diag(program, line)
            .run();
    }
}

fn collect(directory: &Path, depth: usize, out: &mut Vec<std::path::PathBuf>) {
    out.push(directory.to_path_buf());
    if depth >= 3 {
        return;
    }
    let entries = match std::fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let is_directory = entry
            .file_type()
            .map(|file_type| file_type.is_dir())
            .unwrap_or(false);
        if is_directory {
            collect(&entry.path(), depth + 1, out);
        }
    }
}
