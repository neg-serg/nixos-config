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
    /// Rules that end the line, checked once.
    suffixes: Vec<Rule>,
    /// Everything else, bucketed by the first byte of the needle: one pass over
    /// the line visits only the positions where a rule can start.
    buckets: Vec<Vec<Rule>>,
}

impl Default for RuleSet {
    fn default() -> RuleSet {
        RuleSet {
            prefixes: Vec::new(),
            suffixes: Vec::new(),
            buckets: vec![Vec::new(); 256],
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
                Matcher::Suffix(_) => set.suffixes.push(rule),
                _ => {
                    if let Some(first) = rule.matcher.needle().and_then(|n| n.first()) {
                        set.buckets[*first as usize].push(rule);
                    }
                }
            }
        }
        set
    }

    /// Number of compiled rules (for `--show` and tests).
    pub fn count(&self) -> usize {
        self.prefixes.len() + self.suffixes.len() + self.buckets.iter().map(Vec::len).sum::<usize>()
    }

    /// Append every match found in `line`.
    ///
    /// One pass over the line, with a first-byte bucket to skip the positions
    /// where no needle can start. The previous version ran a separate substring
    /// search per rule, which for a ruleset with seven words meant seven passes
    /// over every line.
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
        if !self.buckets.is_empty() {
            for (position, byte) in line.iter().enumerate() {
                let bucket = &self.buckets[*byte as usize];
                for rule in bucket {
                    let Some(needle) = rule.matcher.needle() else {
                        continue;
                    };
                    if line[position..].starts_with(needle) {
                        let end = position + needle.len();
                        let word_ok = match rule.matcher {
                            Matcher::Word(_) => {
                                (position == 0 || !is_word_byte(line[position - 1]))
                                    && (end >= line.len() || !is_word_byte(line[end]))
                            }
                            _ => true,
                        };
                        if word_ok {
                            out.push(Hit::styled(position, end, rule.kind, rule.prio, rule.style));
                        }
                    }
                }
            }
        }
        for rule in &self.suffixes {
            if let Matcher::Suffix(needle) = &rule.matcher {
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
        }
    }
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
