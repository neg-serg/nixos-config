//! Rules: hand-written matchers layered on top of the scanners.
//!
//! Two sources produce them — the built-in rulesets and the user config — and
//! both end up in the same [`RuleSet`]. Matching is a plain byte search: no
//! regex compilation, no per-line allocation, and a first-byte mask that skips
//! the whole rule list for lines that cannot match anything.

use crate::hit::Hit;
use crate::scan::PRIO_RULE;
use crate::theme::Kind;

/// How a rule looks for its needle.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Matcher {
    /// Anywhere in the line.
    Literal(Vec<u8>),
    /// Anywhere in the line, but only on word boundaries.
    Word(Vec<u8>),
    /// At the very beginning of the line.
    Prefix(Vec<u8>),
    /// At the very end of the line (before the terminator).
    Suffix(Vec<u8>),
}

impl Matcher {
    /// The needle, or `None` for prefix rules (they are checked separately).
    fn needle(&self) -> Option<&[u8]> {
        match self {
            Matcher::Prefix(_) => None,
            Matcher::Literal(n) | Matcher::Word(n) | Matcher::Suffix(n) => Some(n),
        }
    }
}

/// One compiled rule.
#[derive(Clone, Debug)]
pub struct Rule {
    pub matcher: Matcher,
    pub kind: Kind,
    /// 0 = theme style for `kind`, otherwise a slot in the style table.
    pub style: u16,
    pub prio: u16,
}

impl Rule {
    pub fn new(matcher: Matcher, kind: Kind) -> Rule {
        Rule {
            matcher,
            kind,
            style: 0,
            prio: PRIO_RULE,
        }
    }
}

/// A ruleset ready to match lines: prefix rules plus everything else behind a
/// first-byte filter.
#[derive(Debug)]
pub struct RuleSet {
    prefixes: Vec<Rule>,
    others: Vec<Rule>,
    first_bytes: [bool; 256],
}

impl Default for RuleSet {
    fn default() -> RuleSet {
        RuleSet {
            prefixes: Vec::new(),
            others: Vec::new(),
            first_bytes: [false; 256],
        }
    }
}

fn is_word_byte(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

impl RuleSet {
    pub fn new(rules: Vec<Rule>) -> RuleSet {
        let mut set = RuleSet::default();
        for rule in rules {
            match &rule.matcher {
                Matcher::Prefix(_) => set.prefixes.push(rule),
                _ => {
                    if let Some(needle) = rule.matcher.needle() {
                        if let Some(first) = needle.first() {
                            set.first_bytes[*first as usize] = true;
                        }
                    }
                    set.others.push(rule);
                }
            }
        }
        set
    }

    /// Number of compiled rules (for `--show` and tests).
    pub fn count(&self) -> usize {
        self.prefixes.len() + self.others.len()
    }

    /// Append every match found in `line`.
    pub fn matches(&self, line: &[u8], out: &mut Vec<Hit>) {
        for rule in &self.prefixes {
            if let Matcher::Prefix(needle) = &rule.matcher {
                if line.starts_with(needle) {
                    out.push(Hit::styled(
                        0,
                        needle.len(),
                        rule.kind,
                        rule.prio,
                        rule.style,
                    ));
                }
            }
        }
        if self.others.is_empty() {
            return;
        }
        // Quick reject: a line without a single possible first byte cannot
        // contain any needle.
        let interesting = line.iter().any(|b| self.first_bytes[*b as usize]);
        if !interesting {
            return;
        }
        for rule in &self.others {
            let Some(needle) = rule.matcher.needle() else {
                continue;
            };
            if needle.is_empty() {
                continue;
            }
            match rule.matcher {
                Matcher::Suffix(_) => {
                    if line.ends_with(needle) {
                        let start = line.len() - needle.len();
                        out.push(Hit::styled(
                            start,
                            line.len(),
                            rule.kind,
                            rule.prio,
                            rule.style,
                        ));
                    }
                }
                Matcher::Word(_) => {
                    let mut from = 0;
                    while let Some(pos) = find_from(line, needle, from) {
                        let end = pos + needle.len();
                        let before_ok = pos == 0 || !is_word_byte(line[pos - 1]);
                        let after_ok = end >= line.len() || !is_word_byte(line[end]);
                        if before_ok && after_ok {
                            out.push(Hit::styled(pos, end, rule.kind, rule.prio, rule.style));
                        }
                        from = pos + 1;
                    }
                }
                _ => {
                    let mut from = 0;
                    while let Some(pos) = find_from(line, needle, from) {
                        let end = pos + needle.len();
                        out.push(Hit::styled(pos, end, rule.kind, rule.prio, rule.style));
                        from = end.max(pos + 1);
                    }
                }
            }
        }
    }
}

/// Naive substring search; needles are short and lines are short, so the
/// `memchr` crate would be a dependency for no measurable win.
fn find_from(haystack: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if needle.len() > haystack.len() {
        return None;
    }
    let first = needle[0];
    let mut i = from;
    while i + needle.len() <= haystack.len() {
        // Look for the first byte anywhere in the tail: a windowed search
        // would step over matches that start on the window edge.
        match haystack[i..].iter().position(|b| *b == first) {
            Some(offset) => {
                let pos = i + offset;
                if pos + needle.len() > haystack.len() {
                    return None;
                }
                if &haystack[pos..pos + needle.len()] == needle {
                    return Some(pos);
                }
                i = pos + 1;
            }
            None => return None,
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(set: &RuleSet, line: &str) -> Vec<(usize, usize, Kind)> {
        let mut hits = Vec::new();
        set.matches(line.as_bytes(), &mut hits);
        crate::hit::normalize(&mut hits);
        hits.iter()
            .map(|h| (h.start as usize, h.end as usize, h.kind))
            .collect()
    }

    #[test]
    fn literal_matches_every_occurrence() {
        let set = RuleSet::new(vec![Rule::new(Matcher::Literal(b"ab".to_vec()), Kind::Err)]);
        assert_eq!(
            kinds(&set, "ab--ab"),
            [(0, 2, Kind::Err), (4, 6, Kind::Err)]
        );
    }

    #[test]
    fn word_matcher_respects_boundaries() {
        let set = RuleSet::new(vec![Rule::new(Matcher::Word(b"open".to_vec()), Kind::Ok)]);
        assert_eq!(kinds(&set, "open opened reopen"), [(0, 4, Kind::Ok)]);
    }

    #[test]
    fn prefix_matches_the_line_start_only() {
        let set = RuleSet::new(vec![Rule::new(
            Matcher::Prefix(b"error:".to_vec()),
            Kind::Err,
        )]);
        assert_eq!(kinds(&set, "error: x"), [(0, 6, Kind::Err)]);
        assert!(kinds(&set, "  error: x").is_empty());
    }

    #[test]
    fn suffix_matches_the_line_end() {
        let set = RuleSet::new(vec![Rule::new(Matcher::Suffix(b"ok".to_vec()), Kind::Ok)]);
        assert_eq!(kinds(&set, "all ok"), [(4, 6, Kind::Ok)]);
        assert!(kinds(&set, "ok all").is_empty());
    }

    #[test]
    fn first_byte_filter_does_not_lose_matches() {
        let set = RuleSet::new(vec![
            Rule::new(Matcher::Literal(b"\x01needle".to_vec()), Kind::Info),
            Rule::new(Matcher::Literal(b"other".to_vec()), Kind::Note),
        ]);
        assert_eq!(kinds(&set, "no match here"), []);
        assert_eq!(kinds(&set, "an other line"), [(3, 8, Kind::Note)]);
    }
}
