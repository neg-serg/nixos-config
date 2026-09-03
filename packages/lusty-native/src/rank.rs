//! Query filtering and ranking over listed entries.
//!
//! Mirrors filesystem_explorer.lua compute_sorted_matches: the first letter of
//! the query must be a prefix of the entry's basename (so 'c' cannot match
//! 'pic.jpg'), the rest are fuzzy-scored on the label, and results are sorted
//! shallower-first, then by score. A query of exactly "." reveals dot files:
//! the prefix anchor is skipped (any basename may match).

use crate::fuzzy;
use crate::listing::Entry;

/// Filter and rank entries for a typed query, returning indices into the
/// slice (the TUI keeps one cached listing and re-ranks per keystroke without
/// cloning entries). Empty query returns all indices (listing order).
pub fn rank_indices(entries: &[Entry], query: &str) -> Vec<usize> {
    if query.is_empty() {
        return (0..entries.len()).collect();
    }
    // Only an exact "." query exempts the first-letter anchor (dot reveal).
    let first = if query == "." {
        None
    } else {
        Some(query.as_bytes()[0].to_ascii_lowercase())
    };
    let mut out: Vec<(usize, f64)> = Vec::new();
    for (idx, e) in entries.iter().enumerate() {
        if let Some(first) = first {
            let name_first = e
                .name
                .as_bytes()
                .first()
                .copied()
                .unwrap_or(0)
                .to_ascii_lowercase();
            if name_first != first {
                continue;
            }
        }
        let score = fuzzy::score(&e.label, query);
        // Lua keeps any non-zero score (negative ones rank last); 0.0 is
        // the exact "no subsequence match" sentinel.
        if score != 0.0 {
            out.push((idx, score));
        }
    }
    out.sort_by(|(ia, sa), (ib, sb)| {
        let a = &entries[*ia];
        let b = &entries[*ib];
        a.depth
            .cmp(&b.depth)
            .then_with(|| sb.partial_cmp(sa).unwrap_or(std::cmp::Ordering::Equal))
            .then_with(|| a.name.cmp(&b.name))
    });
    out.into_iter().map(|(i, _)| i).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::listing::{list, FileKind, Options};
    use std::fs;
    use std::path::Path;

    // Each test gets its own fixture directory: the tests run in parallel
    // threads and must not race on a shared temp path.
    fn fixture(tag: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("lusty_native_rank_{}", tag));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("sub")).unwrap();
        fs::write(dir.join("alpha.txt"), b"x").unwrap();
        fs::write(dir.join("beta.lua"), b"x").unwrap();
        fs::write(dir.join("pic.jpg"), b"x").unwrap();
        fs::write(dir.join("sub/gamma.txt"), b"x").unwrap();
        dir
    }

    fn entries(dir: &Path) -> Vec<Entry> {
        list(dir, &Options { depth: 2, skip_dirs: vec![], follow_mounts: false, show_dots: false })
    }

    fn labels(entries: &[Entry], idxs: &[usize]) -> Vec<String> {
        idxs.iter().map(|&i| entries[i].label.clone()).collect()
    }

    #[test]
    fn first_letter_must_prefix_basename() {
        let dir = fixture("anchor");
        let e = entries(&dir);
        assert_eq!(rank_indices(&e, "c").len(), 0, "query c must not match pic.jpg");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn prefix_query_keeps_matching_entries() {
        let dir = fixture("prefix");
        let e = entries(&dir);
        let l = labels(&e, &rank_indices(&e, "p"));
        assert!(l.contains(&"pic.jpg".to_string()), "pic.jpg starts with p");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn deep_entry_matches_by_basename() {
        let dir = fixture("deep");
        let e = entries(&dir);
        let idxs = rank_indices(&e, "gamma");
        assert_eq!(idxs.len(), 1, "gamma.txt inside sub/ is the only match");
        assert_eq!(e[idxs[0]].label, "sub/gamma.txt");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn empty_query_returns_all() {
        let dir = fixture("all");
        let e = entries(&dir);
        assert_eq!(rank_indices(&e, "").len(), e.len());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn dot_query_skips_anchor() {
        let dir = fixture("dotq");
        fs::write(dir.join(".hidden"), b"x").unwrap();
        let e = list(dir.as_path(), &Options {
            depth: 1,
            skip_dirs: vec![],
            follow_mounts: false,
            show_dots: true,
        });
        // ".hidden" starts with '.', so the anchor would never match it; with
        // the exemption the dot rule itself decides (every name has a dot).
        let idxs = rank_indices(&e, ".");
        assert!(idxs.iter().any(|&i| e[i].name == ".hidden"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn dirs_sort_before_their_contents() {
        // Fixture dirs are reported at depth 1, contents deeper; ranking
        // keeps shallower entries first for equal-ish queries.
        let dir = fixture("order");
        let e = entries(&dir);
        let idxs = rank_indices(&e, "g");
        assert_eq!(idxs.len(), 1);
        assert_eq!(e[idxs[0]].kind, FileKind::File);
        assert_eq!(e[idxs[0]].label, "sub/gamma.txt");
        let _ = fs::remove_dir_all(&dir);
    }
}
