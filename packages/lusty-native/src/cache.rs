//! On-disk listing cache for big roots (binary format, "LSTC" v1).
//!
//! A listing is a pure function of the tree shape: entry names, kinds and
//! depths. Content edits never change it, only adds/removes/renames do, and
//! every one of those bumps the mtime (and entry count) of the directory
//! that contains the change. So a cached listing can be validated by
//! stat-ing only the directories we walked into (for a depth-1 root that is
//! a single stat) instead of re-reading every entry.
//!
//! Layout (all integers little-endian):
//!   magic "LSTC" | depth u32 | dots u8 | follow u8
//!   mounts:  u32 count, each len u32 + bytes
//!   dirs:    u32 count, each label-len u32 + label bytes | mtime i64 | count u64
//!   entries: u32 count, each kind u8 | depth u32 | name-flag u8 | label-len
//!            u32 + label bytes | (name-len u32 + name bytes when flag=1)
//! Entry paths are not stored: they are root.join(label) again. The watch
//! dir labels are relative to the root ("" = root itself).
//!
//! Writes build one buffer and fs::write it to a temp file, then rename
//! into place (atomic). Reads slurp the file once and parse it with a
//! cursor, which keeps warm loads cheap.

use std::fs;
use std::path::{Path, PathBuf};

use crate::listing::{self, Entry, FileKind, Options};

/// More watch dirs than this and validation costs as much as a real walk.
const MAX_WATCH_DIRS: usize = 4096;
/// Only bother caching trees with at least this many entries.
const MIN_ENTRIES: usize = 16;

const MAGIC: &[u8] = b"LST3";

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
        .or_else(|| {
            std::env::var("HOME")
                .ok()
                .map(|h| PathBuf::from(h).join(".local/state"))
        })?;
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

fn kind_char(k: FileKind) -> u8 {
    match k {
        FileKind::Dir => b'd',
        FileKind::Link => b'l',
        FileKind::Socket => b's',
        FileKind::Pipe => b'p',
        FileKind::Block => b'b',
        FileKind::Char => b'c',
        FileKind::File => b'f',
    }
}

fn kind_from(c: u8) -> FileKind {
    match c {
        b'd' => FileKind::Dir,
        b'l' => FileKind::Link,
        b's' => FileKind::Socket,
        b'p' => FileKind::Pipe,
        b'b' => FileKind::Block,
        b'c' => FileKind::Char,
        _ => FileKind::File,
    }
}

fn mtime_len(p: &Path) -> Option<(i128, u64)> {
    let md = fs::metadata(p).ok()?;
    let t = md.modified().ok()?;
    let d = t.duration_since(std::time::UNIX_EPOCH).ok()?;
    Some((d.as_nanos() as i128, md.len()))
}

/// Directories whose contents affect the listing (label, mtime, count): the
/// root itself (label "") plus every listed dir that was descended into.
fn watch_dirs(root: &Path, entries: &[Entry], opts: &Options) -> Vec<(String, i128, u64)> {
    let mut out = Vec::new();
    if let Some((m, l)) = mtime_len(root) {
        out.push((String::new(), m, l));
    }
    for e in entries {
        if e.kind == FileKind::Dir && (e.depth as usize) < opts.depth {
            if let Some((m, l)) = mtime_len(&e.path(root)) {
                out.push((e.label.clone(), m, l));
            }
        }
    }
    out
}

// --- binary writer --------------------------------------------------------

fn put_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}
fn put_u64(out: &mut Vec<u8>, v: u64) {
    out.extend_from_slice(&v.to_le_bytes());
}
fn put_i64(out: &mut Vec<u8>, v: i64) {
    out.extend_from_slice(&v.to_le_bytes());
}
fn put_str(out: &mut Vec<u8>, s: &str) {
    put_u32(out, s.len() as u32);
    out.extend_from_slice(s.as_bytes());
}

fn store(
    path: &Path,
    opts: &Options,
    entries: &[Entry],
    dirs: &[(String, i128, u64)],
    mounts: &[String],
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut w = Vec::with_capacity(entries.len() * 80 + mounts.len() * 64);
    w.extend_from_slice(MAGIC);
    put_u32(&mut w, opts.depth as u32);
    w.push(opts.show_dots as u8);
    w.push(opts.follow_mounts as u8);
    put_u32(&mut w, mounts.len() as u32);
    for m in mounts {
        put_str(&mut w, m);
    }
    put_u32(&mut w, dirs.len() as u32);
    for (label, m, l) in dirs {
        put_str(&mut w, label);
        put_i64(&mut w, *m as i64);
        put_u64(&mut w, *l);
    }
    put_u32(&mut w, entries.len() as u32);
    for e in entries {
        w.push(kind_char(e.kind));
        put_u32(&mut w, e.depth);
        w.push(e.name0);
        put_str(&mut w, &e.label);
    }
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, &w)?;
    fs::rename(&tmp, path)?;
    Ok(())
}

// --- binary reader --------------------------------------------------------

struct Cur<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Cur<'a> {
    fn new(data: &'a [u8]) -> Self {
        Cur { data, pos: 0 }
    }
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let end = self.pos.checked_add(n)?;
        if end > self.data.len() {
            return None;
        }
        let s = &self.data[self.pos..end];
        self.pos = end;
        Some(s)
    }
    fn u8(&mut self) -> Option<u8> {
        self.take(1).map(|b| b[0])
    }
    fn u32(&mut self) -> Option<u32> {
        self.take(4)
            .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn u64(&mut self) -> Option<u64> {
        self.take(8).map(|b| {
            let mut a = [0u8; 8];
            a.copy_from_slice(b);
            u64::from_le_bytes(a)
        })
    }
    fn i64(&mut self) -> Option<i64> {
        self.take(8).map(|b| {
            let mut a = [0u8; 8];
            a.copy_from_slice(b);
            i64::from_le_bytes(a)
        })
    }
    fn str(&mut self) -> Option<String> {
        let n = self.u32()? as usize;
        let b = self.take(n)?;
        Some(String::from_utf8_lossy(b).into_owned())
    }
}

fn current_mounts() -> Vec<String> {
    let mut v: Vec<String> = crate::mount::mount_points().into_iter().collect();
    v.sort();
    v
}

fn try_load(path: &Path, root: &Path, opts: &Options) -> Option<Vec<Entry>> {
    let data = fs::read(path).ok()?;
    let mut c = Cur::new(&data);
    if c.take(MAGIC.len())? != MAGIC {
        return None;
    }
    let depth = c.u32()? as usize;
    let dots = c.u8()?;
    let follow = c.u8()?;
    if depth != opts.depth || dots != opts.show_dots as u8 || follow != opts.follow_mounts as u8 {
        return None;
    }
    let mn = c.u32()? as usize;
    let mut mounts = Vec::with_capacity(mn);
    for _ in 0..mn {
        mounts.push(c.str()?);
    }
    if current_mounts() != mounts {
        return None;
    }
    if !root.is_dir() {
        return None;
    }
    let dn = c.u32()? as usize;
    for _ in 0..dn {
        let label = c.str()?;
        let m = c.i64()? as i128;
        let l = c.u64()?;
        let p = if label.is_empty() {
            root.to_path_buf()
        } else {
            root.join(&label)
        };
        if mtime_len(&p) != Some((m, l)) {
            return None;
        }
    }
    let en = c.u32()? as usize;
    let mut entries = Vec::with_capacity(en);
    for _ in 0..en {
        let kind = kind_from(c.u8()?);
        let edepth = c.u32()?;
        let name0 = c.u8()?;
        let label = c.str()?;
        entries.push(Entry {
            label,
            kind,
            depth: edepth,
            name0,
        });
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
            depth: 2,
            skip_dirs: vec![],
            follow_mounts: false,
            show_dots: false,
        };
        fs::create_dir_all(dir.join("sub")).unwrap();
        fs::write(dir.join("sub/deep.txt"), b"x").unwrap();
        let first = cached_list(&dir, &opts);
        assert!(first.len() >= 41);
        let second = cached_list(&dir, &opts);
        assert_eq!(second.len(), first.len(), "cache hit keeps the entries");
        // path reconstruction must match the real walk
        let real = listing::list(&dir, &opts);
        let mut labels: Vec<String> = real.iter().map(|e| e.label.clone()).collect();
        labels.sort();
        let mut cached: Vec<String> = second.iter().map(|e| e.label.clone()).collect();
        cached.sort();
        assert_eq!(cached, labels, "labels identical to a fresh walk");
        // add a file -> root mtime/count changes -> cache must invalidate
        fs::write(dir.join("f99.txt"), b"x").unwrap();
        let third = cached_list(&dir, &opts);
        assert_eq!(
            third.len(),
            first.len() + 1,
            "cache invalidated after a change"
        );
        // remove it again
        fs::remove_file(dir.join("f99.txt")).unwrap();
        let fourth = cached_list(&dir, &opts);
        assert_eq!(fourth.len(), first.len(), "cache invalidated after removal");
        let _ = fs::remove_dir_all(&dir);
        let _ = fs::remove_dir_all(&cache_dir);
    }
}
