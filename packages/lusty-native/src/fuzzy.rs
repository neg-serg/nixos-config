//! Smart subsequence fuzzy scorer (fzy-style), ported 1:1 from the Lua port
//! (files/nvim/lua/lusty/fuzzy.lua). Default engine for Lusty-native.

const LEADING_PENALTY: f64 = 0.012; // per skipped char before the first match
const INNER_GAP: f64 = 0.02; // per skipped char between two matches
const CONSECUTIVE_BONUS: f64 = 0.05;

/// Boundary bonus for a haystack byte position (0-based).
fn bonus_for(s: &[u8], i: usize) -> f64 {
    if i == 0 {
        return 0.9;
    }
    let ch = s[i];
    if ch == b'/' {
        return 0.9;
    }
    let prev = s[i - 1];
    if prev == b'-' || prev == b'_' || prev == b' ' || prev == b'.' {
        return 0.8;
    }
    if prev == b'/' {
        return 0.9;
    }
    // camelCase: lower-case letter followed by an upper-case one.
    if prev.is_ascii_lowercase() && ch.is_ascii_uppercase() {
        return 0.7;
    }
    0.0
}

/// Case-insensitive subsequence check (both slices already lowercased).
fn has_match(lower_s: &[u8], lower_a: &[u8]) -> bool {
    let (mut a, mut b) = (0usize, 0usize);
    while a < lower_a.len() && b < lower_s.len() {
        if lower_a[a] == lower_s[b] {
            a += 1;
        }
        b += 1;
    }
    a == lower_a.len()
}

/// Reusable scorer. Ranking thousands of entries on every keystroke must not
/// allocate two DP rows plus a lowercase copy per candidate, so the scratch
/// buffers live here and are only grown when a longer label shows up.
pub struct Scorer {
    prev: Vec<f64>,
    cur: Vec<f64>,
    hay: Vec<u8>,
}

impl Default for Scorer {
    fn default() -> Self {
        Self::new()
    }
}

impl Scorer {
    pub fn new() -> Scorer {
        Scorer {
            prev: Vec::new(),
            cur: Vec::new(),
            hay: Vec::new(),
        }
    }

    /// Score how well `abbrev` matches `str_` (case-insensitive); 0.0 means
    /// no subsequence match.
    pub fn score(&mut self, str_: &str, abbrev: &str) -> f64 {
        if abbrev.is_empty() {
            return 0.75; // neutral score for an empty query
        }
        let s = str_.as_bytes();
        let a = abbrev.as_bytes();
        if a.len() > s.len() {
            return 0.0;
        }
        self.hay.clear();
        self.hay.extend(s.iter().map(|b| b.to_ascii_lowercase()));
        let m = self.hay.len();
        let n = a.len();
        // Reuse the DP rows; grow only when this label is longer than before.
        for row in [&mut self.prev, &mut self.cur] {
            if row.len() < m + 1 {
                row.resize(m + 1, f64::NEG_INFINITY);
            }
            row[..m + 1].fill(f64::NEG_INFINITY);
        }
        let lower_a: Vec<u8> = a.iter().map(|b| b.to_ascii_lowercase()).collect();
        if !has_match(&self.hay, &lower_a) {
            return 0.0;
        }

        let neg = f64::NEG_INFINITY;
        let (prev, cur) = (&mut self.prev, &mut self.cur);
        let mut best = neg;

        for i in 1..=n {
            // Running max of (prev[k] + INNER_GAP * k) over k < j enables the
            // inner-gap transition in O(1) per cell.
            let mut best_gap = neg;
            for j in 1..=m {
                let mut score_j = neg;
                if lower_a[i - 1] == self.hay[j - 1] {
                    let bon = bonus_for(s, j - 1);
                    if i == 1 {
                        score_j = bon - LEADING_PENALTY * (j - 1) as f64;
                    } else {
                        let mut cand = neg;
                        if prev[j - 1].is_finite() {
                            cand = prev[j - 1] + CONSECUTIVE_BONUS;
                        }
                        if best_gap.is_finite() {
                            let via_gap = best_gap - INNER_GAP * (j - 1) as f64;
                            if via_gap > cand {
                                cand = via_gap;
                            }
                        }
                        if cand.is_finite() {
                            score_j = cand + bon;
                        }
                    }
                }
                cur[j] = score_j;
                if score_j.is_finite() && i == n && score_j > best {
                    best = score_j;
                }
                // Allow prev[j] to serve gap transitions for positions after j.
                if prev[j].is_finite() {
                    let with_k = prev[j] + INNER_GAP * j as f64;
                    if with_k > best_gap {
                        best_gap = with_k;
                    }
                }
            }
            std::mem::swap(prev, cur);
        }

        if !best.is_finite() {
            return 0.0;
        }
        best
    }
}

/// One-shot convenience wrapper (allocates scratch per call); used by the
/// reference tests and handy for callers that score a single pair.
#[allow(dead_code)]
pub fn score(str_: &str, abbrev: &str) -> f64 {
    Scorer::new().score(str_, abbrev)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_query_neutral() {
        assert_eq!(score("anything", ""), 0.75);
    }

    #[test]
    fn boundary_beats_midword_leading_match() {
        // 'b' at the string start earns the start bonus; a mid-word 'c' with
        // no boundary scores negative (the Lua port returns -0.024 here).
        let prefix = score("beta.lua", "b");
        let inner = score("pic.jpg", "c");
        assert_eq!(prefix, 0.9);
        assert!(prefix > inner);
        assert!(inner < 0.0);
    }

    #[test]
    fn word_boundary_bonus() {
        // matching 'g' after the slash in sub/gamma.txt is a strong boundary
        let after_slash = score("sub/gamma.txt", "g");
        let mid_word = score("sugar.txt", "g");
        assert!(after_slash > mid_word);
        assert!(after_slash > 0.0);
        assert!(mid_word < 0.0);
    }

    #[test]
    fn boundary_bonus_can_beat_consecutive() {
        // 'at' lands on the '.'-boundary ('t' after '.'), so it outscores the
        // plain consecutive prefix 'alp' -- matches the Lua port exactly.
        let consecutive = score("alpha.txt", "alp");
        let gapped = score("alpha.txt", "at");
        assert_eq!(consecutive, 1.0);
        assert_eq!(gapped, 1.6);
        assert!(gapped > consecutive);
    }

    #[test]
    fn case_insensitive() {
        assert_eq!(score("Alpha.txt", "alp"), score("alpha.txt", "alp"));
        assert!(score("Alpha.txt", "ALP") > 0.0);
    }

    #[test]
    fn no_match_returns_zero() {
        assert_eq!(score("alpha.txt", "zzz"), 0.0);
        assert_eq!(score("beta.lua", "alpha"), 0.0);
    }

    #[test]
    fn longer_query_than_string() {
        assert_eq!(score("ab", "abc"), 0.0);
    }

    #[test]
    fn camel_case_boundary() {
        let cc = score("MyUgens.sc", "mu");
        let plain = score("myugens.sc", "mu");
        assert!(cc > plain);
    }

    #[test]
    fn port_matches_lua_reference_table() {
        // Ground-truth values printed by the real Lua port
        // (nvim --clean --headless -l, files/nvim/lua/lusty/fuzzy.lua).
        let cases: &[(&str, &str, f64)] = &[
            ("pic.jpg", "c", -0.024),
            ("beta.lua", "b", 0.9),
            ("beta.lua", "beta", 1.05),
            ("alpha.txt", "alp", 1.0),
            ("alpha.txt", "at", 1.6),
            ("sub/gamma.txt", "g", 0.852),
            ("sugar.txt", "g", -0.024),
            ("sub/gamma.txt", "gamma", 1.052),
            ("mug.png", "gamma", 0.0),
            ("Alpha.txt", "alp", 1.0),
            ("Alpha.txt", "ALP", 1.0),
            ("MyUgens.sc", "mu", 1.58),
            ("myugens.sc", "mu", 0.88),
            ("alpha.txt", "zzz", 0.0),
            ("ab", "abc", 0.0),
        ];
        for (s, a, want) in cases {
            let got = score(s, a);
            assert!(
                (got - want).abs() < 1e-9,
                "score({:?}, {:?}) = {} (want {})",
                s,
                a,
                got,
                want
            );
        }
    }
}
