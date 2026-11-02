//! The range machinery: image listing (`_list_images`) and the anchor/current
//! slice (`_range_files`).
//!
//! `_list_images` was
//! `find -L "$dir" -type f -printf '%C@ %p\n' | sort -rn | cut -d ' ' -f 2- |
//!  ug/grep -Ei '\.(jpe?g|...)$'`.
//! Here the walk follows symlinks (`-L`), the ctime ordering is compared as
//! seconds+nanoseconds (GNU sort's numeric comparison, with the full-line
//! last-resort comparison reproduced as a descending byte comparison of the
//! path for exactly equal ctimes), and the extension filter is case-insensitive
//! on the file name. The `ug`/`grep` choice disappears; on this host the system
//! `ug` wrapper is currently broken (readable config, but ugrep >= 7.8 rejects
//! `--config` for non-root), which the shell could not work around.
//!
//! `_range_files` has a real bug that the port must keep: `c_line` is declared
//! but never assigned, so `end` is always empty and the slice is always
//! `sed -n "<a_line>,p"` — GNU sed rejects that expression. The shell printed
//! sed's diagnostic, captured no files, then its caller ran one `mv`/`cp` with
//! an empty path (the command substitution produced an empty string, and
//! `printf '%s\n' ""` still yields one empty line). `range_slice` therefore
//! deliberately spawns that same sed invocation on the listing and returns its
//! stdout; the empty-path calls are made by the action loops.

use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;

use crate::bytes::{os_owned, strip_trailing_newlines};
use crate::tools::{self, Call};

/// `_range_files` writes to stderr and returns 1 on its two guarded failures.
pub fn range_slice(anchor: &[u8], current: &[u8]) -> Result<Vec<u8>, ()> {
    if anchor.is_empty() {
        return fail(b"swayimg-actions: no range mark set (range_mark is empty)\n");
    }

    let directory = crate::bytes::dirname(current);
    let listing = list_images(&directory);

    // The shell wrote the listing to a mktemp file and ran sed on it; feeding
    // the same bytes on stdin preserves sed's diagnostics byte-for-byte while
    // dropping the temp file.
    let mut listing_text = Vec::new();
    for (index, path) in listing.iter().enumerate() {
        if index > 0 {
            listing_text.push(b'\n');
        }
        listing_text.extend_from_slice(path);
    }
    if !listing.is_empty() {
        listing_text.push(b'\n');
    }

    // a_resolved="$(realpath "$anchor" 2>/dev/null)" || { ... }
    let Some(resolved) = tools::realpath(anchor, true) else {
        let mut message = b"swayimg-actions: range anchor not found (was deleted?): ".to_vec();
        message.extend_from_slice(anchor);
        message.push(b'\n');
        return fail(&message);
    };

    // a_line="$(grep -nFx "$a_resolved" "$tmp" | cut -d: -f1)"
    let Some(position) = listing.iter().position(|path| path == &resolved) else {
        return fail(b"Range mark not found in current directory\n");
    };
    let a_line = position + 1;

    // c_line is never set in the shell; `end` is empty and this expression is
    // "N,p", which sed rejects.
    let expression = format!("{a_line},p");
    let outcome = Call::new("sed")
        .argument("-n")
        .argument(expression)
        .input(listing_text)
        .capture_stdout()
        .run();
    // `sed ...; rm -f "$tmp"` — the rm made the function succeed even when sed
    // failed, so the caller sees an empty file list rather than a failure.
    Ok(strip_trailing_newlines(outcome.stdout))
}

fn fail(message: &[u8]) -> Result<Vec<u8>, ()> {
    use std::io::Write;
    let _ = std::io::stderr().write_all(message);
    Err(())
}

/// `_list_images <dir>`: recursive, follows symlinks, only regular image files,
/// newest ctime first.
pub fn list_images(dir: &[u8]) -> Vec<Vec<u8>> {
    let root = PathBuf::from(os_owned(dir));
    let mut found: Vec<(i64, i64, Vec<u8>)> = Vec::new();
    let mut ancestors: Vec<PathBuf> = Vec::new();
    walk(&root, dir, &mut ancestors, &mut found);
    // sort -rn on "<seconds>.<fraction> <path>": descending ctime, and for an
    // exact tie the whole line's byte comparison (the path) descending too.
    found.sort_by(|a, b| {
        b.0.cmp(&a.0)
            .then_with(|| b.1.cmp(&a.1))
            .then_with(|| b.2.cmp(&a.2))
    });
    found
        .into_iter()
        .map(|(_, _, path)| path)
        .filter(|path| is_image(path))
        .collect()
}

fn walk(
    path: &std::path::Path,
    display: &[u8],
    ancestors: &mut Vec<PathBuf>,
    found: &mut Vec<(i64, i64, Vec<u8>)>,
) {
    // `-L`: type checks follow symlinks, broken links simply do not match
    // -type f and are skipped.
    let Ok(metadata) = fs::metadata(path) else {
        return;
    };
    if metadata.is_file() {
        found.push((metadata.ctime(), metadata.ctime_nsec(), display.to_vec()));
        return;
    }
    if !metadata.is_dir() {
        return;
    }

    // A symlink loop makes GNU find print "File system loop detected" and skip
    // the branch; the port skips it silently (the diagnostic is the only part
    // of that path the actions never depended on).
    let canonical = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    if ancestors.contains(&canonical) {
        return;
    }
    ancestors.push(canonical);
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let mut child_display = display.to_vec();
            if !child_display.ends_with(b"/") {
                child_display.push(b'/');
            }
            child_display.extend_from_slice(name.as_bytes());
            walk(&entry.path(), &child_display, ancestors, found);
        }
    }
    ancestors.pop();
}

const IMAGE_EXTENSIONS: &[&[u8]] = &[
    b".jpg", b".jpeg", b".png", b".gif", b".svg", b".webp", b".tiff", b".heif", b".heic", b".avif",
    b".ico", b".bmp",
];

fn is_image(path: &[u8]) -> bool {
    let name_start = path
        .iter()
        .rposition(|&byte| byte == b'/')
        .map(|index| index + 1)
        .unwrap_or(0);
    let name = &path[name_start..];
    let mut lower = Vec::with_capacity(name.len());
    lower.extend(name.iter().map(u8::to_ascii_lowercase));
    IMAGE_EXTENSIONS
        .iter()
        .any(|extension| lower.ends_with(extension))
}

/// `anchor="$(cat "$range_file" 2>/dev/null)"`: absent/unreadable file means
/// "no mark", while an existing empty file is a mark with an empty path.
pub fn read_mark(range_file: &[u8]) -> Option<Vec<u8>> {
    let data = fs::read(crate::env::path(range_file)).ok()?;
    Some(strip_trailing_newlines(data))
}

/// `[ ! -e "$anchor" ] && [ ! -L "$anchor" ]`: the stale-anchor guard. A
/// dangling symlink still counts as present (`-L`), so it is not cleared here:
/// range-mark stores the dangling target path, and that path is stale only on a
/// later request (when the symlink itself is gone).
pub fn is_stale(anchor: &[u8]) -> bool {
    let path = crate::env::path(anchor);
    let exists = fs::metadata(&path).is_ok();
    let is_symlink = fs::symlink_metadata(&path).is_ok();
    !exists && !is_symlink
}

#[cfg(test)]
mod tests {
    use super::is_image;

    #[test]
    fn extension_filter_matches_the_shell_regex() {
        assert!(is_image(b"/pic/a.jpg"));
        assert!(is_image(b"/pic/a.JPEG"));
        assert!(is_image(b"/pic/a.PnG"));
        assert!(is_image(b"/pic/a.tiff"));
        assert!(is_image(b"/pic/a.heic"));
        assert!(!is_image(b"/pic/a.tif"));
        assert!(!is_image(b"/pic/a.jpg.txt"));
        assert!(!is_image(b"/pic/a"));
        assert!(!is_image(b"/pic.jpg/file"));
    }
}
