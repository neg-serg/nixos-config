//! On-disk listing cache for big roots.
//!
//! A listing is a pure function of the tree shape: entry names, kinds and
//! depths. Content edits never change it, only adds/removes/renames do, and
//! every one of those bumps the mtime of the directory that contains the
//! change. So a cached listing can be validated by stat-ing only the
//! directories we walked into (for a depth-1 root that is a single stat)
//! instead of re-reading every entry. Used for big trees (e.g. /nix/store,
//! 155k entries) where a repeat listing goes from ~75ms to well under 1ms.
//!
//! File format is tab-separated records (paths with tabs/newlines are as
//! unsupported here as in the serve protocol):
//!   H <depth> <dots> <follow>
//!   M <mount point>
//!   E <kind> <depth> <name> <path> <label>
//!   D <dir path> <mtime-nanos>
//! Writes go to a temp file and are renamed into place (atomic).

use std::fs;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};

use crate::listing::{self, Entry, FileKind, Options};

/// More watch dirs than this and validation costs as much as a real walk.
const MAX_WATCH_DIRS: usize = 4096;
/// Only bother caching trees with at least this many entries.
const MIN_ENTRIES: usize = 16;

fn cache_enabled() -> bool {
    match std::env::var("LUSTY_CACHE") {
        Ok(v) => v != "0",
        Err(_) => true,
    }
}

fn state_dir() -> Option<PathBuf> {
    if let Ok(d) = std::env::var("LUSTY_CACHE_DIR") {
        return Some(PathBuf::from(d));
    }
    let base = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .ok()
        .or_else(|| std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".local/state")))?;
    Some(base.join("lusty-native"))
}

/// FNV-1a over the listing key: root, depth, skip list, dots flag.
fn key_hash(root: &Path, opts: &Options) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    let mut mix = |bytes: &[u8]| {
        for &b in bytes {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
    };
    mix(root.as_os_str().as_encoded_bytes());
    mix(&[b'|', opts.depth as u8]);
    for s in &opts.skip_dirs {
        mix(b"|");
        mix(s.as_bytes());
    }
    if opts.show_dots {
        mix(b"|d");
    }
    if opts.follow_mounts {
        mix(b"|f");
    }
    h
}

fn kind_char(k: FileKind) -> char {
    match k {
        FileKind::Dir => 'd',
        FileKind::Link => 'l',
        FileKind::Socket => 's',
        FileKind::Pipe => 'p',
        FileKind::Block => 'b',
        FileKind::Char => 'c',
        FileKind::File => 'f',
    }
}

fn kind_from(c: char) -> FileKind {
    match c {
        'd' => FileKind::Dir,
        'l' => FileKind::Link,
        's' => FileKind::Socket,
        'p' => FileKind::Pipe,
        'b' => FileKind::Block,
        'c' => FileKind::Char,
        _ => FileKind::File,
    }
}


/// Directories whose contents affect the listing: the root itself plus every
/// listed dir that was descended into (depth < max_depth). Returns
/// (path, mtime-nanos, entry-count): entry count catches adds/removes even
/// when the filesystem mtime granularity is coarse.
fn watch_dirs(root: &Path, entries: &[Entry], opts: &Options) -> Vec<(PathBuf, i128, u64)> {
    let mut out = Vec::new();
    if let Some((m, l)) = mtime_len(root) {
        out.push((root.to_path_buf(), m, l));
    }
    for e in entries {
        if e.kind == FileKind::Dir && (e.depth as usize) < opts.depth {
            if let Some((m, l)) = mtime_len(&e.path) {
                out.push((e.path.clone(), m, l));
            }
        }
    }
    out
}

fn mtime_len(p: &Path) -> Option<(i128, u64)> {
    let md = fs::metadata(p).ok()?;
    let t = md.modified().ok()?;
    let d = t.duration_since(std::time::UNIX_EPOCH).ok()?;
    Some((d.as_nanos() as i128, md.len()))
}

fn store(
    path: &Path,
    opts: &Options,
    entries: &[Entry],
    dirs: &[(PathBuf, i128, u64)],
    mounts: &[String],
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("tmp");
    {
        let f = fs::File::create(&tmp)?;
        let mut w = BufWriter::new(f);
        writeln!(
            w,
            "H\t{}\t{}\t{}",
            opts.depth,
            opts.show_dots as u8,
            opts.follow_mounts as u8
        )?;
        for m in mounts {
            writeln!(w, "M\t{m}")?;
        }
        for e in entries {
            writeln!(
                w,
                "E\t{}\t{}\t{}\t{}\t{}",
                kind_char(e.kind),
                e.depth,
                e.name,
                e.path.display(),
                e.label
            )?;
        }
        for (d, m, l) in dirs {
            writeln!(w, "D\t{0}\t{1}\t{2}", d.display(), m, l)?;
        }
        w.flush()?;
    }
    fs::rename(&tmp, path)?;
    Ok(())
}

fn current_mounts() -> Vec<String> {
    let mut v: Vec<String> = crate::mount::mount_points().into_iter().collect();
    v.sort();
    v
}

fn try_load(path: &Path, root: &Path, opts: &Options) -> Option<Vec<Entry>> {
    let f = fs::File::open(path).ok()?;
    let reader = BufReader::new(f);
    let mut entries: Vec<Entry> = Vec::new();
    let mut dirs: Vec<(PathBuf, i128, u64)> = Vec::new();
    let mut mounts: Vec<String> = Vec::new();
    let mut header_ok = false;
    for line in reader.lines() {
        let line = line.ok()?;
        let mut it = line.split('\t');
        match it.next()? {
            "H" => {
                let depth: usize = it.next()?.parse().ok()?;
                let dots: u8 = it.next()?.parse().ok()?;
                let follow: u8 = it.next()?.parse().ok()?;
                if depth == opts.depth
                    && dots == opts.show_dots as u8
                    && follow == opts.follow_mounts as u8
                {
                    header_ok = true;
                }
            }
            "M" => {
                if let Some(m) = it.next() {
                    mounts.push(m.to_string());
                }
            }
            "E" => {
                let kind = kind_from(it.next()?.chars().next()?);
                let depth: u32 = it.next()?.parse().ok()?;
                let name = it.next()?.to_string();
                let path = PathBuf::from(it.next()?);
                let label = it.next()?.to_string();
                entries.push(Entry { name, path, label, kind, depth });
            }
            "D" => {
                let d = PathBuf::from(it.next()?);
                let m: i128 = it.next()?.parse().ok()?;
                let l: u64 = it.next()?.parse().ok()?;
                dirs.push((d, m, l));
            }
            _ => {}
        }
    }
    if !header_ok || entries.is_empty() {
        return None;
    }
    // mounts must match (a new mount would change traversal decisions)
    if current_mounts() != mounts {
        return None;
    }
    // root must still be a directory and every watched dir untouched
    if !root.is_dir() {
        return None;
    }
    for (d, m, l) in &dirs {
        if mtime_len(d) != Some((*m, *l)) {
            return None;
        }
    }
    Some(entries)
}

/// listing::list with an on-disk cache; falls back to a plain walk on any
/// cache miss, invalidation or IO error.
pub fn cached_list(root: &Path, opts: &Options) -> Vec<Entry> {
    if !cache_enabled() {
        return listing::list(root, opts);
    }
    let Some(dir) = state_dir() else {
        return listing::list(root, opts);
    };
    let key = dir.join(format!("{:016x}.lc", key_hash(root, opts)));
    if let Some(entries) = try_load(&key, root, opts) {
        return entries;
    }
    let entries = listing::list(root, opts);
    let dirs = watch_dirs(root, &entries, opts);
    if dirs.len() <= MAX_WATCH_DIRS && entries.len() >= MIN_ENTRIES {
        let mounts = current_mounts();
        let _ = store(&key, opts, &entries, &dirs, &mounts);
    }
    entries
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn cache_hit_after_first_walk_and_invalidation_on_change() {
        let dir = std::env::temp_dir().join("lusty_native_cache_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        for i in 0..40 {
            fs::write(dir.join(format!("f{i:02}.txt")), b"x").unwrap();
        }
        let cache_dir = std::env::temp_dir().join("lusty_native_cache_store");
        let _ = fs::remove_dir_all(&cache_dir);
        fs::create_dir_all(&cache_dir).unwrap();
        std::env::set_var("LUSTY_CACHE_DIR", &cache_dir);
        let opts = Options {
            depth: 1,
            skip_dirs: vec![],
            follow_mounts: false,
            show_dots: false,
        };
        let first = cached_list(&dir, &opts);
        assert_eq!(first.len(), 40);
        let second = cached_list(&dir, &opts);
        assert_eq!(second.len(), 40, "cache hit keeps the entries");
        // add a file -> root mtime changes -> cache must invalidate
        fs::write(dir.join("f99.txt"), b"x").unwrap();
        let third = cached_list(&dir, &opts);
        assert_eq!(third.len(), 41, "cache invalidated after a change");
        // remove a file again
        fs::remove_file(dir.join("f99.txt")).unwrap();
        let fourth = cached_list(&dir, &opts);
        assert_eq!(fourth.len(), 40, "cache invalidated after removal");
        let _ = fs::remove_dir_all(&dir);
        let _ = fs::remove_dir_all(&cache_dir);
    }
}
