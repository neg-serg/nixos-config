//! Filesystem helpers shared by both binaries: path scanning, `~` expansion,
//! lexical path arithmetic and temporary directories.
//!
//! The behaviours here mirror the Python payload (`Path.rglob`, `Path.expanduser`,
//! `os.path.relpath`) rather than the most convenient Rust equivalents, because
//! the cache keys and the MPD queue URIs are derived from the resulting strings.

use std::ffi::OsString;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::py::path_str;

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

/// `Path.home()`: `$HOME`, falling back to `/`.
pub fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

/// `Path.expanduser()` for the `~` and `~/...` spellings.
///
/// `~user` expansion is not implemented: the Python payloads only ever use the
/// current user, and resolving another user's home would need a passwd lookup.
pub fn expand_user(path: &Path) -> PathBuf {
    let text = path_str(path);
    if text == "~" {
        return home_dir();
    }
    if let Some(rest) = text.strip_prefix("~/") {
        return home_dir().join(rest);
    }
    path.to_path_buf()
}

/// All regular files below `root` with one of `exts`, sorted by path text.
///
/// Matches `sorted(root.rglob("*"))` filtered by `is_file()`: hidden files are
/// included, file symlinks are followed, directory symlinks are not.
pub fn scan(root: &Path, exts: &[&str]) -> Vec<PathBuf> {
    let mut files = Vec::new();
    walk(root, exts, &mut files);
    files.sort_by(|a, b| path_str(a).cmp(&path_str(b)));
    files
}

fn walk(dir: &Path, exts: &[&str], files: &mut Vec<PathBuf>) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        match entry.file_type() {
            Ok(kind) if kind.is_dir() => walk(&path, exts, files),
            Ok(kind) if kind.is_file() => {
                if has_audio_extension(&path, exts) {
                    files.push(path);
                }
            }
            Ok(kind) if kind.is_symlink() => {
                // `is_file()` follows the link; a linked directory is not
                // traversed (Path.rglob does not follow directory symlinks).
                if fs::metadata(&path).map(|m| m.is_file()).unwrap_or(false)
                    && has_audio_extension(&path, exts)
                {
                    files.push(path);
                }
            }
            _ => {}
        }
    }
}

fn has_audio_extension(path: &Path, exts: &[&str]) -> bool {
    match path.extension() {
        Some(extension) => {
            let extension = extension.to_string_lossy().to_ascii_lowercase();
            exts.iter().any(|candidate| *candidate == extension)
        }
        None => false,
    }
}

/// Resolve `~`, then make the path absolute and lexically normalised.
pub fn lexical_absolute(path: &Path) -> PathBuf {
    let joined = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("/"))
            .join(path)
    };
    let mut absolute = false;
    let mut parts: Vec<OsString> = Vec::new();
    for component in joined.components() {
        match component {
            Component::Prefix(_) | Component::RootDir => absolute = true,
            Component::CurDir => {}
            Component::ParentDir => {
                parts.pop();
            }
            Component::Normal(part) => parts.push(part.to_os_string()),
        }
    }
    let mut out = if absolute {
        PathBuf::from("/")
    } else {
        PathBuf::new()
    };
    for part in parts {
        out.push(part);
    }
    out
}

/// `os.path.relpath(path, start)` for lexically normalised paths.
pub fn relative_path(path: &Path, start: &Path) -> String {
    let path = lexical_absolute(path);
    let start = lexical_absolute(start);
    let path_parts: Vec<String> = path
        .components()
        .filter_map(|component| match component {
            Component::Normal(part) => Some(part.to_string_lossy().into_owned()),
            _ => None,
        })
        .collect();
    let start_parts: Vec<String> = start
        .components()
        .filter_map(|component| match component {
            Component::Normal(part) => Some(part.to_string_lossy().into_owned()),
            _ => None,
        })
        .collect();

    let mut common = 0;
    while common < path_parts.len()
        && common < start_parts.len()
        && path_parts[common] == start_parts[common]
    {
        common += 1;
    }
    if common == path_parts.len() && common == start_parts.len() {
        return ".".to_string();
    }
    let mut parts: Vec<String> = Vec::new();
    for _ in common..start_parts.len() {
        parts.push("..".to_string());
    }
    parts.extend(path_parts[common..].iter().cloned());
    parts.join("/")
}

/// A unique token for temporary file names.
pub fn unique_tag(prefix: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos())
        .unwrap_or(0);
    let counter = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}-{}-{counter}-{nanos}", std::process::id())
}

/// A temporary directory removed on drop (the Rust stand-in for
/// `tempfile.TemporaryDirectory`).
pub struct TempDir {
    path: PathBuf,
}

impl TempDir {
    pub fn new(prefix: &str) -> io::Result<Self> {
        for _ in 0..64 {
            let path = std::env::temp_dir().join(unique_tag(prefix));
            match fs::create_dir(&path) {
                Ok(()) => return Ok(Self { path }),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "cannot create a unique temporary directory",
        ))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::os::unix::fs::symlink;

    fn touch(path: &Path, contents: &[u8]) {
        let mut file = fs::File::create(path).unwrap();
        file.write_all(contents).unwrap();
    }

    #[test]
    fn scan_sorts_and_filters() {
        let temp = TempDir::new("scan-test").unwrap();
        let root = temp.path().join("music");
        fs::create_dir_all(root.join("album")).unwrap();
        touch(&root.join("b.FLAC"), b"");
        touch(&root.join("a.mp3"), b"");
        touch(&root.join("notes.txt"), b"");
        touch(&root.join("album").join("c.opus"), b"");
        symlink(root.join("a.mp3"), root.join("link.mp3")).unwrap();
        symlink(root.join("album"), root.join("album-link")).unwrap();

        let found: Vec<String> = scan(&root, crate::AUDIO_EXTS)
            .iter()
            .map(|path| path_str(path))
            .collect();
        let base = path_str(&root);
        assert_eq!(
            found,
            vec![
                format!("{base}/a.mp3"),
                format!("{base}/album/c.opus"),
                format!("{base}/b.FLAC"),
                format!("{base}/link.mp3"),
            ]
        );
    }

    #[test]
    fn relative_path_matches_os_path_relpath() {
        assert_eq!(
            relative_path(
                Path::new("/home/neg/music/album/a.flac"),
                Path::new("/home/neg/music")
            ),
            "album/a.flac"
        );
        assert_eq!(
            relative_path(Path::new("/home/neg/music"), Path::new("/home/neg/music")),
            "."
        );
        assert_eq!(
            relative_path(
                Path::new("/home/neg/other/a.flac"),
                Path::new("/home/neg/music")
            ),
            "../other/a.flac"
        );
        assert_eq!(
            relative_path(
                Path::new("/home/neg/music/../music/a.flac"),
                Path::new("/home/neg/music")
            ),
            "a.flac"
        );
    }

    #[test]
    fn lexical_absolute_normalises() {
        assert_eq!(
            lexical_absolute(Path::new("/a/./b/../c")),
            PathBuf::from("/a/c")
        );
        assert_eq!(lexical_absolute(Path::new("/../x")), PathBuf::from("/x"));
    }

    #[test]
    fn expand_user_replaces_home() {
        let home = home_dir();
        assert_eq!(expand_user(Path::new("~")), home);
        assert_eq!(expand_user(Path::new("~/music")), home.join("music"));
        assert_eq!(
            expand_user(Path::new("/absolute/path")),
            PathBuf::from("/absolute/path")
        );
    }
}
