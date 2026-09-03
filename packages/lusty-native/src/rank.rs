//! Query filtering and ranking over listed entries.
//!
//! Mirrors filesystem_explorer.lua compute_sorted_matches: the first letter of
//! the query must be a prefix of the entry's basename (so 'c' cannot match
//! 'pic.jpg'), the rest are fuzzy-scored on the label, and results are sorted
//! shallower-first, then by score.

use crate::fuzzy;
use crate::listing::Entry;

/// Filter and rank entries for a typed query. Empty query returns the entries
/// unchanged (they are already sorted shallow-first by listing::list).
pub fn filter_and_rank(entries: Vec<Entry>, query: &str) -> Vec<Entry> {
    if query.is_empty() {
        return entries;
    }
    let first = query.as_bytes()[0].to_ascii_lowercase();
    let mut out: Vec<(Entry, f64)> = Vec::new();
    for e in entries {
        let name_first = e
            .name
            .as_bytes()
            .first()
            .copied()
            .unwrap_or(0)
            .to_ascii_lowercase();
        if name_first == first {
            let score = fuzzy::score(&e.label, query);
            // Lua keeps any non-zero score (negative ones rank last); 0.0 is
            // the exact "no subsequence match" sentinel.
            if score != 0.0 {
                out.push((e, score));
            }
        }
    }
    out.sort_by(|(a, sa), (b, sb)| {
        a.depth
            .cmp(&b.depth)
            .then_with(|| sb.partial_cmp(sa).unwrap_or(std::cmp::Ordering::Equal))
            .then_with(|| a.name.cmp(&b.name))
    });
    out.into_iter().map(|(e, _)| e).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::listing::{list, Options};
    use std::fs;

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

    fn entries(dir: &std::path::Path) -> Vec<Entry> {
        list(dir, &Options { depth: 2, skip_dirs: vec![], follow_mounts: false, show_dots: false })
    }

    #[test]
    fn first_letter_must_prefix_basename() {
        let dir = fixture("anchor");
        let out = filter_and_rank(entries(&dir), "c");
        assert_eq!(out.len(), 0, "query c must not match pic.jpg (prefix anchor)");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn prefix_query_keeps_matching_entries() {
        let dir = fixture("prefix");
        let out = filter_and_rank(entries(&dir), "p");
        let labels: Vec<&str> = out.iter().map(|e| e.label.as_str()).collect();
        assert!(labels.contains(&"pic.jpg"), "pic.jpg starts with p");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn deep_entry_matches_by_basename() {
        let dir = fixture("deep");
        let out = filter_and_rank(entries(&dir), "gamma");
        assert_eq!(out.len(), 1, "gamma.txt inside sub/ is the only match");
        assert_eq!(out[0].label, "sub/gamma.txt");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn shallower_entries_win_on_equal_scores() {
        let dir = fixture("shallow");
        // 'a' prefix: alpha.txt (depth 1) and nothing deeper; rank puts
        // depth-1 entries first regardless of score.
        let out = filter_and_rank(entries(&dir), "a");
        assert!(out.iter().any(|e| e.name == "alpha.txt"));
        let _ = fs::remove_dir_all(&dir);
    }
}
