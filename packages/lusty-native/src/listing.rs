//! Directory listing engine: parallel depth-limited walk with mount-point and
//! skip-dir pruning, shallower entries first.
//!
//! Semantics mirror the Lua port: skip-dirs (pic,tmp), mount points and
//! hidden dot-dirs stay visible-but-untraversed (their own entry is listed,
//! their subtree is not walked into the results); hidden entries are dropped
//! when dots are not shown.
//!
//! The walk is breadth-first over depth levels. Every directory of a level is
//! scanned in parallel on the rayon pool (RAYON_NUM_THREADS tunes it), each
//! scan produces the entries of its children plus the next level of
//! directories. Blocked subtrees are simply never queued, so no post-hoc
//! ancestor filtering is needed. Per-depth buckets are sorted by name at the
//! end, which makes the parallel collection order irrelevant.

use std::collections::HashSet;
use std::fs::FileType;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use rayon::prelude::*;

use crate::glob;
use crate::mount;

/// A directory queued for one walk level: its path and its label relative to
/// the root ("" for the root itself).
type DirTask = (PathBuf, String);

/// Parallelize a level only when it has at least this many directories;
/// smaller trees would pay more rayon scheduling than they gain.
const PAR_MIN_DIRS: usize = 16;

/// Default worker count for the walk pool. Measured on this machine
/// (Ryzen 9 9950X3D): /nix/store depth 2 (617k entries) walks in ~210ms
/// at 16 threads vs ~630ms single-threaded; 32 threads gains another ~3%
/// there but costs slightly more on small trees, so 16 is the default.
/// LUSTY_THREADS or RAYON_NUM_THREADS overrides it.
const DEFAULT_THREADS: usize = 16;

fn walk_pool() -> &'static rayon::ThreadPool {
    static POOL: OnceLock<rayon::ThreadPool> = OnceLock::new();
    POOL.get_or_init(|| {
        let n = std::env::var("LUSTY_THREADS")
            .ok()
            .or_else(|| std::env::var("RAYON_NUM_THREADS").ok())
            .and_then(|v| v.trim().parse::<usize>().ok())
            .unwrap_or(DEFAULT_THREADS)
            .max(1);
        rayon::ThreadPoolBuilder::new().num_threads(n).build().expect("walk pool")
    })
}

/// Kind of a listed entry, mirroring what ls --color distinguishes.
/// Socket/Pipe/Block/Char are unreachable with readdir d_type (it only
/// reports dir/file/symlink) but kept so colors.rs can map them if a future
/// backend supplies them.
#[allow(dead_code)]
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
    /// Label shown/scored by the picker: the path relative to the root.
    pub label: String,
    pub kind: FileKind,
    /// 1 = direct child of the root, 2 = one level deeper, etc.
    pub depth: u32,
    /// Lowercased first byte of the basename (ranking anchor); precomputed
    /// once so per-keystroke ranking never re-splits every label.
    pub name0: u8,
}

/// Last label component (the bare file/dir name).
pub fn basename(label: &str) -> &str {
    label.rsplit('/').next().unwrap_or(label)
}

impl Entry {
    /// Full path for this entry under `root` (labels are root-relative, so
    /// the path is root.join(label)); built only where actually needed.
    pub fn path(&self, root: &Path) -> PathBuf {
        root.join(&self.label)
    }

    /// Bare entry name (last label component).
    pub fn basename(&self) -> &str {
        basename(&self.label)
    }
}

pub struct Options {
    /// 1 = current directory only, 2 = plus one subdirectory level.
    pub depth: usize,
    pub skip_dirs: Vec<String>,
    pub follow_mounts: bool,
    pub show_dots: bool,
}

fn kind_of(ft: &FileType) -> FileKind {
    if ft.is_dir() {
        FileKind::Dir
    } else if ft.is_symlink() {
        FileKind::Link
    } else {
        // readdir d_type only exposes dir/file/symlink, so sockets/pipes/
        // devices fall through to File. They are unreachable in practice:
        // mount points (which is where such nodes live) are skipped.
        FileKind::File
    }
}

/// Precompiled skip pattern: (has_metachar, pattern) with '~' already
/// expanded. Literal patterns without '/' only need a case-insensitive name
/// compare; everything else falls back to the full path, built lazily.
fn is_skip_dir(name: &str, path: &Path, skip: &[(bool, String)]) -> bool {
    for (glob, pat) in skip {
        if !glob && !pat.contains('/') && name.eq_ignore_ascii_case(pat) {
            return true;
        }
    }
    if !skip.iter().any(|(glob, pat)| *glob || pat.contains('/')) {
        return false;
    }
    let full = path.to_string_lossy();
    for (glob, pat) in skip {
        if *glob {
            if glob::wildcard_match(pat, name) || glob::wildcard_match(pat, &full) {
                return true;
            }
        } else if pat.contains('/') && full.eq_ignore_ascii_case(pat) {
            return true;
        }
    }
    false
}

/// Scan one directory: list its children as entries at `depth` and queue the
/// subdirectories that should be traversed further (skip-dirs, mount points
/// and, when dots are hidden, dot-dirs are listed but not descended into).
fn scan_dir(
    dir: &Path,
    dir_rel: &str,
    depth: usize,
    max_depth: usize,
    skip: &[(bool, String)],
    mounts: &HashSet<String>,
    show_dots: bool,
) -> (Vec<Entry>, Vec<DirTask>) {
    let mut entries = Vec::new();
    let mut subdirs: Vec<DirTask> = Vec::new();
    let rd = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return (entries, subdirs),
    };
    for item in rd.flatten() {
        let Ok(ft) = item.file_type() else {
            continue;
        };
        let is_dir = ft.is_dir();
        let name = item.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') && !show_dots {
            continue; // dot-dir/dot-file: neither listed nor traversed
        }
        let rel = if dir_rel.is_empty() {
            name.clone()
        } else {
            format!("{dir_rel}/{name}")
        };
        let path = dir.join(&name);
        let mut descend = is_dir && depth < max_depth;
        if descend && is_skip_dir(&name, &path, skip) {
            descend = false;
        }
        if descend && !mounts.is_empty() {
            // readdir paths are clean absolute paths, so a direct lookup
            // against the (normalized) mount set suffices.
            if let Some(p) = path.to_str() {
                if mounts.contains(p) {
                    descend = false;
                }
            }
        }
        entries.push(Entry {
            label: rel.clone(),
            kind: kind_of(&ft),
            depth: depth as u32,
            name0: name.as_bytes().first().copied().unwrap_or(0).to_ascii_lowercase(),
        });
        if descend {
            subdirs.push((path, rel));
        }
    }
    (entries, subdirs)
}

pub fn list(root: &Path, opts: &Options) -> Vec<Entry> {
    if opts.depth == 0 || !root.is_dir() {
        return Vec::new();
    }
    let mounts = if opts.follow_mounts {
        HashSet::new()
    } else {
        mount::mount_points()
    };
    // Expand '~' and classify patterns once, not per directory.
    let skip: Vec<(bool, String)> = opts
        .skip_dirs
        .iter()
        .filter(|p| !p.is_empty())
        .map(|p| {
            let expanded = glob::expand_tilde(p);
            (expanded.contains('*') || expanded.contains('?'), expanded)
        })
        .collect();

    // buckets[level - 1] collects the entries of that depth level.
    let mut buckets: Vec<Vec<Entry>> = (0..opts.depth).map(|_| Vec::new()).collect();
    let mut level: Vec<DirTask> = vec![(root.to_path_buf(), String::new())];
    let mut depth = 1usize;
    while depth <= opts.depth && !level.is_empty() {
        let results: Vec<(Vec<Entry>, Vec<DirTask>)> = if level.len() >= PAR_MIN_DIRS {
            walk_pool().install(|| {
                level
                    .par_iter()
                    .map(|(p, rel)| scan_dir(p, rel, depth, opts.depth, &skip, &mounts, opts.show_dots))
                    .collect()
            })
        } else {
            level
                .iter()
                .map(|(p, rel)| scan_dir(p, rel, depth, opts.depth, &skip, &mounts, opts.show_dots))
                .collect()
        };
        let mut next: Vec<DirTask> = Vec::new();
        let bucket = &mut buckets[depth - 1];
        for (ents, subs) in results {
            bucket.extend(ents);
            next.extend(subs);
        }
        level = next;
        depth += 1;
    }

    // Shallower entries first, ties broken by name: concatenate the depth
    // buckets, each sorted by name. Sorting u32 indices instead of moving
    // whole Entry structs around in the quicksort keeps the partitioning
    // working set small; the permutation is applied once at the end.
    let mut entries: Vec<Entry> = Vec::new();
    for mut bucket in buckets {
        sort_by_name(&mut bucket);
        entries.append(&mut bucket);
    }
    entries
}

/// Lowercased extension ("tar.gz" -> "gz", no dot -> "").
fn ext_of(label: &str) -> &str {
    let base = basename(label);
    match base.rfind('.') {
        Some(i) if i + 1 < base.len() => &base[i + 1..],
        _ => "",
    }
}

/// eza --sort=ext: group each depth by extension, then name.
pub fn sort_by_ext(entries: &mut Vec<Entry>) {
    let n = entries.len();
    let mut i = 0;
    while i < n {
        let d = entries[i].depth;
        let mut j = i + 1;
        while j < n && entries[j].depth == d {
            j += 1;
        }
        entries[i..j].sort_unstable_by(|a, b| {
            ext_of(&a.label)
                .cmp(ext_of(&b.label))
                .then_with(|| a.basename().cmp(b.basename()))
        });
        i = j;
    }
}

/// Apply eza-style ordering tweaks on top of the canonical (depth, name)
/// order: optionally keep directories first within each depth and/or reverse
/// each depth group. Deterministic, so on-disk cache reuse stays consistent.
pub fn reorder(entries: &mut Vec<Entry>, dirs_first: bool, reverse: bool) {
    if !dirs_first && !reverse {
        return;
    }
    let n = entries.len();
    let mut i = 0;
    while i < n {
        let d = entries[i].depth;
        let mut j = i + 1;
        while j < n && entries[j].depth == d {
            j += 1;
        }
        let g = &mut entries[i..j];
        if dirs_first {
            g.sort_unstable_by(|a, b| match (a.kind == FileKind::Dir, b.kind == FileKind::Dir) {
                (true, false) => std::cmp::Ordering::Less,
                (false, true) => std::cmp::Ordering::Greater,
                _ => a.basename().cmp(b.basename()),
            });
        }
        if reverse {
            g.reverse();
        }
        i = j;
    }
}

/// Sort one depth bucket by name (in place) via an index permutation.
fn sort_by_name(bucket: &mut Vec<Entry>) {
    let n = bucket.len();
    if n < 2 {
        return;
    }
    let mut order: Vec<u32> = (0..n as u32).collect();
    order.sort_unstable_by(|&a, &b| basename(&bucket[a as usize].label).cmp(basename(&bucket[b as usize].label)));
    let mut src = std::mem::replace(bucket, Vec::with_capacity(n));
    for &i in &order {
        let empty = Entry {
            label: String::new(),
            kind: FileKind::File,
            depth: 0,
            name0: 0,
        };
        bucket.push(std::mem::replace(&mut src[i as usize], empty));
    }
    // src (now holding only empty placeholders) is dropped here.
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
        let names: Vec<&str> = entries.iter().map(|e| e.basename()).collect();
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
        let names: Vec<&str> = entries.iter().map(|e| e.basename()).collect();
        assert!(names.contains(&"b.txt"));
        // shallower first: a.txt (depth 1) before b.txt (depth 2)
        let a = entries.iter().position(|e| e.basename() == "a.txt").unwrap();
        let b = entries.iter().position(|e| e.basename() == "b.txt").unwrap();
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
        let names: Vec<&str> = entries.iter().map(|e| e.basename()).collect();
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
        let names: Vec<&str> = entries.iter().map(|e| e.basename()).collect();
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
