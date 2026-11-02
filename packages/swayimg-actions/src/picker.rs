//! `choose_dest` from the shell, with the find/zoxide/sed/awk/sort pipeline
//! replaced by native code.
//!
//! The picker still receives exactly the same entries in exactly the same
//! (byte-wise) order: every directory under `$XDG_PICTURES_DIR` down to depth
//! 3, zoxide entries under `$HOME` or `/mnt/one` (dot paths excluded), and the
//! current file's directory. `$HOME` is rewritten to `~` for the picker and the
//! selection is rewritten back. `~`-expansion and byte-order sorting are the
//! only points where the port cannot follow the shell's environment: the shell's
//! `sort -u` used the ambient locale, the port always sorts bytes (the C locale).

use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use crate::bytes::{contains, home_rewrite, os_owned, output_lines, tilde_expand};
use crate::env::Paths;
use crate::tools::{self, Call};

pub fn choose_dest(paths: &Paths, prompt: &str, file: &[u8]) -> Vec<u8> {
    let mut entries: Vec<Vec<u8>> = Vec::new();

    // "Always include all subdirs of pics_dir (fresh scan)":
    // find "$pics_dir" -maxdepth 3 -type d 2>/dev/null
    for directory in picture_directories(&paths.pictures) {
        entries.push(home_rewrite(&directory, &paths.home));
    }

    // zoxide query -l | grep -E "^($HOME|/mnt/one)" | grep -v '/\.' |
    // sed "s:^$HOME:~:"
    if tools::program_exists("zoxide") {
        let outcome = Call::new("zoxide")
            .argument("query")
            .argument("-l")
            .capture_stdout()
            .quiet_stderr()
            .run();
        for line in output_lines(&outcome.stdout) {
            if !line.starts_with(paths.home.as_slice()) && !line.starts_with(b"/mnt/one") {
                continue;
            }
            if contains(&line, b"/.") {
                continue;
            }
            entries.push(home_rewrite(&line, &paths.home));
        }
    }

    // "Current file's parent dir": dirname "$(realpath "$file")" |
    // sed "s:^$HOME:~:". A failed realpath leaves dirname("") == ".".
    if !file.is_empty() {
        let resolved = tools::realpath(file, true).unwrap_or_default();
        entries.push(home_rewrite(&crate::bytes::dirname(&resolved), &paths.home));
    }

    // awk 'NF' | sort -u
    entries.retain(|line| line.iter().any(|byte| *byte != b' ' && *byte != b'\t'));
    entries.sort();
    entries.dedup();

    // printf '%s\n' "$entries" | vicinae dmenu -p "⟬$prompt⟭ ❯>"
    let mut input: Vec<u8> = Vec::new();
    for (index, entry) in entries.iter().enumerate() {
        if index > 0 {
            input.push(b'\n');
        }
        input.extend_from_slice(entry);
    }
    // printf always terminates its output, even when `entries` is empty, so
    // the picker reads a single empty line and returns nothing on cancel.
    input.push(b'\n');

    let prompt_bytes = format!("⟬{prompt}⟭ ❯>");
    let outcome = Call::new("vicinae")
        .argument("dmenu")
        .argument("-p")
        .argument(prompt_bytes)
        .input(input)
        .capture_stdout()
        .run();

    // sed "s:^~:$HOME:" (per line) followed by command substitution, which
    // stripped the trailing newlines.
    let selected_lines: Vec<Vec<u8>> = output_lines(&outcome.stdout)
        .into_iter()
        .map(|line| tilde_expand(&line, &paths.home))
        .collect();
    let mut selected = Vec::new();
    for (index, line) in selected_lines.iter().enumerate() {
        if index > 0 {
            selected.push(b'\n');
        }
        selected.extend_from_slice(line);
    }
    selected
}

/// `find "$pics_dir" -maxdepth 3 -type d 2>/dev/null`, without following
/// symlinks: the root itself (only when it is a real directory), then every
/// real directory at depth 1..=3. Read errors are silent, like the `2>/dev/null`.
fn picture_directories(root: &[u8]) -> Vec<Vec<u8>> {
    let mut found = Vec::new();
    let root_path = PathBuf::from(os_owned(root));
    match fs::symlink_metadata(&root_path) {
        Ok(metadata) if metadata.is_dir() => {}
        _ => return found,
    }
    found.push(root.to_vec());
    collect_subdirectories(&root_path, 1, 3, &mut found);
    found
}

fn collect_subdirectories(directory: &Path, depth: u32, max_depth: u32, found: &mut Vec<Vec<u8>>) {
    if depth > max_depth {
        return;
    }
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        // file_type() is lstat: a symlink to a directory is a symlink here,
        // matching find's default -P.
        if !file_type.is_dir() {
            continue;
        }
        let path = entry.path();
        found.push(path.as_os_str().as_bytes().to_vec());
        collect_subdirectories(&path, depth + 1, max_depth, found);
    }
}
