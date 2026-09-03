//! Directory listing engine: depth-limited walk with mount-point and skip-dir
//! pruning, shallower entries first.
//!
//! Semantics mirror the Lua port: skip-dirs (pic,tmp), mount points and hidden
//! dot-dirs stay visible-but-untraversed (their own entry is listed, their
//! subtree is not walked into the results); hidden entries are dropped when
//! dots are not shown.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

use crate::glob;
use crate::mount;

/// Kind of a listed entry, mirroring what ls --color distinguishes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    File,
    Dir,
    Link,
    Socket,
    Pipe,
    Block,
    Char,
}

#[derive(Debug, Clone)]
pub struct Entry {
    pub name: String,
    /// Full path (used by later phases to open the file).
    #[allow(dead_code)]
    pub path: PathBuf,
    /// Label shown/scored by the picker: the path relative to the root.
    pub label: String,
    pub kind: FileKind,
    /// 1 = direct child of the root, 2 = one level deeper, etc.
    pub depth: u32,
}

pub struct Options {
    /// 1 = current directory only, 2 = plus one subdirectory level.
    pub depth: usize,
    pub skip_dirs: Vec<String>,
    pub follow_mounts: bool,
    pub show_dots: bool,
}

fn kind_of(e: &walkdir::DirEntry) -> FileKind {
    let ft = e.file_type();
    if ft.is_dir() {
        FileKind::Dir
    } else if ft.is_symlink() {
        FileKind::Link
    } else {
        // walkdir only exposes dir/file/symlink from the dirent d_type, so
        // sockets/pipes/devices fall through to File. They are unreachable in
        // practice: mount points (which is where such nodes live) are skipped.
        FileKind::File
    }
}

/// The label for an entry: its path relative to the root, '/' separated.
fn rel_label(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .to_string()
}

/// True when any proper ancestor directory of rel (e.g. "sub" or "sub/deep"
/// for "sub/deep/file.txt") is in the blocked set.
fn under_blocked(rel: &str, blocked: &HashSet<String>) -> bool {
    let comps: Vec<&str> = rel.split('/').collect();
    let mut prefix = String::new();
    for k in 0..comps.len().saturating_sub(1) {
        if k > 0 {
            prefix.push('/');
        }
        prefix.push_str(comps[k]);
        if blocked.contains(&prefix) {
            return true;
        }
    }
    false
}

fn is_skip_dir(name: &str, path: &Path, skip: &[String]) -> bool {
    for pat in skip {
        if pat.is_empty() {
            continue;
        }
        let expanded = glob::expand_tilde(pat);
        let full = path.to_string_lossy();
        if glob::wildcard_match(&expanded, name) || glob::wildcard_match(&expanded, &full) {
            return true;
        }
    }
    false
}

pub fn list(root: &Path, opts: &Options) -> Vec<Entry> {
    let mounts = if opts.follow_mounts {
        HashSet::new()
    } else {
        mount::mount_points()
    };
    let root_norm = mount::normalize(root.to_string_lossy());

    let mut blocked: HashSet<String> = HashSet::new();
    let mut entries: Vec<Entry> = Vec::new();

    for e in WalkDir::new(root)
        .min_depth(1)
        .max_depth(opts.depth)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let name = e.file_name().to_string_lossy().to_string();
        let rel = rel_label(root, e.path());
        if under_blocked(&rel, &blocked) {
            continue;
        }
        let hidden = name.starts_with('.');
        if hidden && !opts.show_dots {
            // Hidden dot-dir: neither listed nor traversed.
            if e.file_type().is_dir() {
                blocked.insert(rel);
            }
            continue;
        }
        let kind = kind_of(&e);
        if kind == FileKind::Dir {
            if is_skip_dir(&name, e.path(), &opts.skip_dirs) {
                blocked.insert(rel.clone()); // visible, but not traversed
            } else if !mounts.is_empty() {
                let p = mount::normalize(e.path().to_string_lossy());
                if p != root_norm && mounts.contains(&p) {
                    blocked.insert(rel.clone()); // visible, but not traversed
                }
            }
        }
        entries.push(Entry {
            name,
            path: e.path().to_path_buf(),
            label: rel,
            kind,
            depth: e.depth() as u32,
        });
    }

    // Shallower entries first, ties broken by name.
    entries.sort_by(|a, b| a.depth.cmp(&b.depth).then_with(|| a.name.cmp(&b.name)));
    entries
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn opts(depth: usize, skip: Vec<String>, show_dots: bool) -> Options {
        Options { depth, skip_dirs: skip, follow_mounts: false, show_dots }
    }

    #[test]
    fn depth_one_lists_children() {
        let dir = std::env::temp_dir().join("lusty_native_list_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("sub")).unwrap();
        fs::write(dir.join("a.txt"), b"x").unwrap();
        fs::write(dir.join("sub/b.txt"), b"y").unwrap();
        let entries = list(&dir, &opts(1, vec![], false));
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"a.txt"));
        assert!(names.contains(&"sub"));
        assert!(!names.contains(&"b.txt"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn depth_two_includes_subdir_files() {
        let dir = std::env::temp_dir().join("lusty_native_depth2_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("sub")).unwrap();
        fs::write(dir.join("a.txt"), b"x").unwrap();
        fs::write(dir.join("sub/b.txt"), b"y").unwrap();
        let entries = list(&dir, &opts(2, vec![], false));
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"b.txt"));
        // shallower first: a.txt (depth 1) before b.txt (depth 2)
        let a = entries.iter().position(|e| e.name == "a.txt").unwrap();
        let b = entries.iter().position(|e| e.name == "b.txt").unwrap();
        assert!(a < b);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn skip_dirs_visible_but_not_traversed() {
        let dir = std::env::temp_dir().join("lusty_native_skip_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("pic")).unwrap();
        fs::write(dir.join("pic/x.txt"), b"x").unwrap();
        let entries = list(&dir, &opts(2, vec!["pic".to_string()], false));
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"pic"), "skip dir stays visible");
        assert!(!names.contains(&"x.txt"), "skip dir contents not traversed");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn dots_hidden_by_default() {
        let dir = std::env::temp_dir().join("lusty_native_dots_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join(".hid")).unwrap();
        fs::write(dir.join(".hidden"), b"x").unwrap();
        let entries = list(&dir, &opts(2, vec![], false));
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(!names.contains(&".hidden"));
        assert!(!names.contains(&".hid"));
        assert!(!names.contains(&"marker.txt"), "hidden dir not traversed");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn labels_are_root_relative() {
        let dir = std::env::temp_dir().join("lusty_native_label_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("sub/deep")).unwrap();
        fs::write(dir.join("sub/deep/foo.txt"), b"x").unwrap();
        let entries = list(&dir, &opts(3, vec![], false));
        let labels: Vec<&str> = entries.iter().map(|e| e.label.as_str()).collect();
        assert!(labels.contains(&"sub"));
        assert!(labels.contains(&"sub/deep"));
        assert!(labels.contains(&"sub/deep/foo.txt"));
        let _ = fs::remove_dir_all(&dir);
    }
}
