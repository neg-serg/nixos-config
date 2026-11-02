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
//! `_range_files` declared `c_line` but never assigned it, so the shell's
//! `sed -n "<a_line>,p"` expression was invalid and the range actions acted on
//! an empty path. This port fixes that: both the anchor and the current file
//! are located in the listing, and the inclusive slice between their positions
//! (in either order) is returned. A current file that is absent from the image
//! listing is reported instead of silently producing an empty range.

use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;

use crate::bytes::{os_owned, strip_trailing_newlines};
use crate::tools::{self, Call};

/// `_range_files` writes to stderr and returns 1 on its guarded failures.
/// Returns the inclusive `[anchor, current]` slice of the image listing
/// (newest ctime first), followed by a trailing newline per file.
pub fn range_slice(anchor: &[u8], current: &[u8]) -> Result<Vec<u8>, ()> {
    if anchor.is_empty() {
        return fail(b"swayimg-actions: no range mark set (range_mark is empty)\n");
    }

    let directory = crate::bytes::dirname(current);
    let listing = list_images(&directory);

    // a_resolved="$(realpath "$anchor" 2>/dev/null)" || { ... }
    let Some(resolved_anchor) = tools::realpath(anchor, true) else {
        let mut message = b"swayimg-actions: range anchor not found (was deleted?): ".to_vec();
        message.extend_from_slice(anchor);
        message.push(b'\n');
        return fail(&message);
    };
    let Some(anchor_position) = listing.iter().position(|path| path == &resolved_anchor) else {
        return fail(b"Range mark not found in current directory\n");
    };

    // c_resolved="$(realpath "$current" 2>/dev/null)" (the shell never looked
    // its line up; the fix needs both ends of the slice).
    let Some(resolved_current) = tools::realpath(current, true) else {
        let mut message = b"swayimg-actions: current file not found: ".to_vec();
        message.extend_from_slice(current);
        message.push(b'\n');
        return fail(&message);
    };
    let Some(current_position) = listing.iter().position(|path| path == &resolved_current) else {
        let mut message =
            b"swayimg-actions: current file not found in the image listing: ".to_vec();
        message.extend_from_slice(current);
        message.push(b'\n');
        return fail(&message);
    };

    let (start, end) = if anchor_position <= current_position {
        (anchor_position, current_position)
    } else {
        (current_position, anchor_position)
    };
    // Command substitution strips trailing newlines; `apply_lines` adds the
    // final one, so the slice is joined without a trailing separator.
    let mut slice = Vec::new();
    for (index, path) in listing[start..=end].iter().enumerate() {
        if index > 0 {
            slice.push(b'\n');
        }
        slice.extend_from_slice(path);
    }
    Ok(slice)
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
