//! Rust port of `packages/local-bin/bin/sx`.
//!
//! Collects regular files below the given directories (following symlinks like
//! `find -L`), keeps the image extensions the original greps for, sorts them
//! by inode-change time newest-first and hands the list to swayimg in gallery
//! mode. `find | sort | cut | grep/ug` are native here; swayimg is still
//! spawned with `-c <config> -g -f <list>`.
//!
//! The shell's process substitution cannot be reproduced without a shell, so
//! the list is piped to swayimg's stdin and `-f` names `/proc/self/fd/0`: the
//! child opens that path like a regular file and reads the list from the pipe.
//! (`-f -` is not a stdin convention here — swayimg would look for a file
//! literally named `-`.)
//!
//! `find` diagnostics (missing paths, permission errors, directory loops) keep
//! the GNU wording under `LC_ALL=C`, and do not affect the exit status: the
//! original pipeline's status is swayimg's.

#![forbid(unsafe_code)]

use std::collections::HashSet;
use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use local_bin_zsh_extra::{
    err_line, is_executable, raw_args, report_spawn_failure, status_code, which_str, StdioMode,
};

const IMAGE_EXTENSIONS: [&[u8]; 12] = [
    b".jpg", b".jpeg", b".png", b".gif", b".svg", b".webp", b".tiff", b".heif", b".heic", b".avif",
    b".ico", b".bmp",
];

struct Entry {
    seconds: i64,
    nanoseconds: i64,
    path: Vec<u8>,
}

fn main() {
    let args = raw_args();
    if let Some(first) = args.first() {
        if first == "-h" || first == "--help" {
            err_line("Usage: sx [DIR...]");
            return;
        }
    }

    let directories: Vec<OsString> = if args.is_empty() {
        vec![OsString::from(".")]
    } else {
        args.clone()
    };

    let home = std::env::var_os("HOME").unwrap_or_default();
    let mut swayimg = PathBuf::from(&home).join(".local/bin/swayimg");
    if !is_executable(&swayimg) {
        swayimg = PathBuf::from("swayimg");
    }
    let found = if swayimg.as_os_str().as_bytes().contains(&b'/') {
        is_executable(&swayimg)
    } else {
        which_str("swayimg").is_some()
    };
    if !found {
        err_line("sx: swayimg not found in PATH or ~/.local/bin");
        std::process::exit(1);
    }

    let mut entries = Vec::new();
    let mut ancestors = HashSet::new();
    for directory in &directories {
        walk(Path::new(directory), &mut entries, &mut ancestors);
    }
    entries.retain(|entry| image_extension(&entry.path));
    entries.sort_by(|left, right| {
        right
            .seconds
            .cmp(&left.seconds)
            .then_with(|| right.nanoseconds.cmp(&left.nanoseconds))
            .then_with(|| right.path.cmp(&left.path))
    });

    let config_home = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(&home).join(".config"));
    let config = config_home.join("swayimg/init.lua");

    let mut list = Vec::new();
    for entry in &entries {
        list.extend_from_slice(&entry.path);
        list.push(b'\n');
    }

    let mut command = Command::new(&swayimg);
    command
        .arg("-c")
        .arg(&config)
        .arg("-g")
        .arg("-f")
        .arg("/proc/self/fd/0")
        .stdin(Stdio::piped());
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            let status = report_spawn_failure("sx", "swayimg", &error, StdioMode::Inherit);
            std::process::exit(status);
        }
    };
    if let Some(mut stdin) = child.stdin.take() {
        // A directory with more images than the pipe buffer must not block the
        // collector before swayimg starts reading.
        std::thread::spawn(move || {
            let _ = stdin.write_all(&list);
        });
    }
    let status = match child.wait() {
        Ok(status) => status_code(status),
        Err(_) => 1,
    };
    std::process::exit(status);
}

fn walk(path: &Path, entries: &mut Vec<Entry>, ancestors: &mut HashSet<(u64, u64)>) {
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => {
            report_find_error(path, &error);
            return;
        }
    };
    if metadata.is_file() {
        entries.push(Entry {
            seconds: metadata.ctime(),
            nanoseconds: metadata.ctime_nsec(),
            path: path.as_os_str().as_bytes().to_vec(),
        });
        return;
    }
    if !metadata.is_dir() {
        return;
    }

    let identity = (metadata.dev(), metadata.ino());
    if !ancestors.insert(identity) {
        err_line(&format!(
            "find: File system loop detected; '{}' is part of a cycle.",
            path.display()
        ));
        return;
    }

    match fs::read_dir(path) {
        Ok(read_dir) => {
            for entry in read_dir {
                match entry {
                    Ok(entry) => walk(&entry.path(), entries, ancestors),
                    Err(error) => report_find_error(path, &error),
                }
            }
        }
        Err(error) => report_find_error(path, &error),
    }
    ancestors.remove(&identity);
}

fn report_find_error(path: &Path, error: &std::io::Error) {
    let message = match error.kind() {
        std::io::ErrorKind::NotFound => "No such file or directory".to_string(),
        std::io::ErrorKind::PermissionDenied => "Permission denied".to_string(),
        _ => {
            let text = error.to_string();
            match text.find(" (os error ") {
                Some(position) => text[..position].to_string(),
                None => text,
            }
        }
    };
    err_line(&format!("find: '{}': {message}", path.display()));
}

fn image_extension(path: &[u8]) -> bool {
    let lower: Vec<u8> = path.iter().map(|byte| byte.to_ascii_lowercase()).collect();
    IMAGE_EXTENSIONS
        .iter()
        .any(|extension| lower.ends_with(extension))
}
