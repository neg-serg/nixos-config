//! Directory listing engine: depth-limited parallel walk with mount-point and
//! skip-dir pruning, shallower entries first.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use rayon::prelude::*;
use walkdir::WalkDir;

use crate::glob;
use crate::mount;

#[derive(Debug, Clone)]
pub struct Entry {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
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

pub fn list(root: &Path, opts: &Options) -> Vec<Entry> {
    let mounts = if opts.follow_mounts {
        HashSet::new()
    } else {
        mount::mount_points()
    };
    let root_norm = mount::normalize(root.to_string_lossy());

    let walker = WalkDir::new(root)
        .min_depth(1)
        .max_depth(opts.depth)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| {
            if e.depth() == 0 {
                return true;
            }
            let name = e.file_name().to_string_lossy().to_string();
            let is_dir = e.file_type().is_dir();
            if name.starts_with('.') && !opts.show_dots {
                return false;
            }
            if is_dir {
                if is_skip_dir(&name, e.path(), &opts.skip_dirs) {
                    return false;
                }
                if !mounts.is_empty() {
                    let p = mount::normalize(e.path().to_string_lossy());
                    if p != root_norm && mounts.contains(&p) {
                        return false;
                    }
                }
            }
            true
        });

    let mut entries: Vec<Entry> = walker
        .filter_map(|e| e.ok())
        .par_bridge()
        .map(|e| Entry {
            name: e.file_name().to_string_lossy().to_string(),
            path: e.path().to_path_buf(),
            is_dir: e.file_type().is_dir(),
            depth: e.depth() as u32,
        })
        .collect();

    // Shallower entries first, ties broken by name.
    entries.sort_by(|a, b| a.depth.cmp(&b.depth).then_with(|| a.name.cmp(&b.name)));
    entries
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn depth_one_lists_children() {
        let dir = std::env::temp_dir().join("lusty_native_list_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("sub")).unwrap();
        fs::write(dir.join("a.txt"), b"x").unwrap();
        fs::write(dir.join("sub/b.txt"), b"y").unwrap();
        let entries = list(&dir, &Options {
            depth: 1,
            skip_dirs: vec![],
            follow_mounts: false,
            show_dots: false,
        });
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
        let entries = list(&dir, &Options {
            depth: 2,
            skip_dirs: vec![],
            follow_mounts: false,
            show_dots: false,
        });
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(names.contains(&"b.txt"));
        // shallower first: a.txt (depth 1) before b.txt (depth 2)
        let a = entries.iter().position(|e| e.name == "a.txt").unwrap();
        let b = entries.iter().position(|e| e.name == "b.txt").unwrap();
        assert!(a < b);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn skip_dirs_are_pruned() {
        let dir = std::env::temp_dir().join("lusty_native_skip_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("pic")).unwrap();
        fs::write(dir.join("pic/x.txt"), b"x").unwrap();
        let entries = list(&dir, &Options {
            depth: 2,
            skip_dirs: vec!["pic".to_string()],
            follow_mounts: false,
            show_dots: false,
        });
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(!names.contains(&"x.txt"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn dots_hidden_by_default() {
        let dir = std::env::temp_dir().join("lusty_native_dots_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join(".hid")).unwrap();
        fs::write(dir.join(".hidden"), b"x").unwrap();
        let entries = list(&dir, &Options {
            depth: 1,
            skip_dirs: vec![],
            follow_mounts: false,
            show_dots: false,
        });
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        assert!(!names.contains(&".hidden"));
        assert!(!names.contains(&".hid"));
        let _ = fs::remove_dir_all(&dir);
    }
}
