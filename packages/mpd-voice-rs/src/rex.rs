//! A small backtracking regular-expression engine.
//!
//! The intent table is a list of `re.search` patterns (`\w*`, `{1,3}`, `(?:…)`,
//! `(?P<value>…)`, `\b`, `^…$`). Rust's std has no regex, and the crate cannot
//! depend on `regex` — the build is offline — so this module implements the
//! subset those patterns use, with Python-compatible semantics: leftmost match,
//! alternatives in order, greedy quantifiers with backtracking.
//!
//! Supported: literals, `.`, `\w \W \s \S \d \D \b \B`, `[...]` classes with
//! ranges and negation, groups (`(a)` capturing, `(?:a)` non-capturing,
//! `(?P<name>a)` named), `|`, `* + ? {m} {m,} {m,n}` (greedy), `^` and `$`.
//! Not supported on purpose: lookaround and lazy quantifiers — the one pattern
//! that needed a lookahead (`mute`'s negative one) keeps that check in
//! `intents.rs`, where it is explicit and testable.

use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Class {
    negated: bool,
    /// Ranges as (low, high) pairs.
    ranges: [(char, char); 8],
    len: usize,
    /// `\w`, `\s`, `\d` memberships, folded into the class.
    word: bool,
    space: bool,
    digit: bool,
    /// `\W`, `\S`, `\D`: the negated versions, folded in the same way.
    neg_word: bool,
    neg_space: bool,
    neg_digit: bool,
}

impl Class {
    fn empty() -> Self {
        Class {
            negated: false,
            ranges: [('\0', '\0'); 8],
            len: 0,
            word: false,
            space: false,
            digit: false,
            neg_word: false,
            neg_space: false,
            neg_digit: false,
        }
    }

    fn push_range(&mut self, low: char, high: char) -> Option<()> {
        if self.len == self.ranges.len() {
            return None;
        }
        self.ranges[self.len] = (low, high);
        self.len += 1;
        Some(())
    }

    fn matches(&self, ch: char) -> bool {
        let mut hit = self.word && is_word(ch)
            || self.space && ch.is_whitespace()
            || self.digit && ch.is_ascii_digit()
            || self.neg_word && !is_word(ch)
            || self.neg_space && !ch.is_whitespace()
            || self.neg_digit && !ch.is_ascii_digit();
        if !hit {
            for (low, high) in self.ranges[..self.len].iter() {
                if (*low..=*high).contains(&ch) {
                    hit = true;
                    break;
                }
            }
        }
        if self.negated {
            !hit
        } else {
            hit
        }
    }
}

fn is_word(ch: char) -> bool {
    ch.is_alphanumeric() || ch == '_'
}

#[derive(Debug, Clone)]
enum Node {
    Char(char),
    Any,
    Class(Class),
    Bol,
    Eol,
    WordBoundary,
    NotWordBoundary,
    Group {
        index: usize,
        nodes: Vec<Node>,
    },
    /// End of a capturing group: records `(start, pos)` in the slot.
    SetCapture {
        index: usize,
        start: usize,
    },
    Alt(Vec<Vec<Node>>),
    Repeat {
        node: Box<Node>,
        min: usize,
        max: Option<usize>,
    },
}

/// A compiled pattern plus its capture slot names.
#[derive(Debug, Clone)]
pub struct Regex {
    nodes: Vec<Node>,
    names: Vec<(String, usize)>,
    slots: usize,
}

/// One match: character offsets in the haystack (Python semantics) plus the
/// captured substrings.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Match {
    pub start: usize,
    pub end: usize,
    pub captures: Vec<(String, String)>,
}

/// Rewrite bounded quantifiers into explicit copies and optionals.
///
/// A repetition node matches its operand in isolation, so an operand with
/// internal choices (`(?:a|ab)?`) could not backtrack into the enclosing
/// sequence. Expanding `{m,n}` into copies plus `Alt([x], [])` keeps every
/// choice inside the sequence, where the matcher can retry it. Unbounded
/// repetitions stay as-is and are only allowed over single-character operands.
fn simplify(nodes: Vec<Node>) -> Option<Vec<Node>> {
    let mut out: Vec<Node> = Vec::with_capacity(nodes.len());
    for node in nodes {
        match node {
            Node::Group { index, nodes: inner } => out.push(Node::Group {
                index,
                nodes: simplify(inner)?,
            }),
            Node::Alt(branches) => {
                let mut simplified = Vec::with_capacity(branches.len());
                for branch in branches {
                    simplified.push(simplify(branch)?);
                }
                out.push(Node::Alt(simplified));
            }
            Node::Repeat { node, min, max } => match max {
                Some(max) => {
                    for _ in 0..min {
                        out.push((*node).clone());
                    }
                    for _ in min..max {
                        out.push(Node::Alt(vec![vec![(*node).clone()], Vec::new()]));
                    }
                }
                None => {
                    if !is_simple(&node) {
                        return None;
                    }
                    if min > 0 {
                        out.push((*node).clone());
                    }
                    out.push(Node::Repeat {
                        node,
                        min: 0,
                        max: None,
                    });
                }
            },
            other => out.push(other),
        }
    }
    Some(out)
}

fn is_simple(node: &Node) -> bool {
    matches!(node, Node::Char(_) | Node::Class(_) | Node::Any)
}

impl Regex {
    pub fn new(pattern: &str) -> Option<Regex> {
        let chars: Vec<char> = pattern.chars().collect();
        let mut parser = Parser {
            chars: &chars,
            pos: 0,
            slots: 1,
            names: Vec::new(),
        };
        let nodes = parser.parse_alt()?;
        if parser.pos != chars.len() {
            return None;
        }
        let nodes = simplify(nodes)?;
        Some(Regex {
            nodes,
            names: parser.names,
            slots: parser.slots,
        })
    }

    /// Leftmost match anywhere in the text (`re.search`).
    pub fn search(&self, text: &str) -> Option<Match> {
        let chars: Vec<char> = text.chars().collect();
        for start in 0..=chars.len() {
            if let Some(caps) = self.match_at(&chars, start) {
                return Some(self.build_match(&chars, caps));
            }
        }
        None
    }

    /// Match the whole text (`re.fullmatch`).
    pub fn fullmatch(&self, text: &str) -> Option<Match> {
        let chars: Vec<char> = text.chars().collect();
        let caps = self.match_at(&chars, 0)?;
        if caps[0] != Some((0, chars.len())) {
            return None;
        }
        Some(self.build_match(&chars, caps))
    }

    pub fn is_match(&self, text: &str) -> bool {
        self.search(text).is_some()
    }

    /// Named capture from a match, by group name.
    pub fn group<'a>(&self, m: &'a Match, name: &str) -> Option<&'a str> {
        m.captures
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    }

    fn build_match(&self, chars: &[char], caps: Vec<Option<(usize, usize)>>) -> Match {
        let whole = caps[0].unwrap_or((0, 0));
        let mut captures: BTreeMap<String, String> = BTreeMap::new();
        for (name, index) in &self.names {
            if let Some((start, end)) = caps.get(*index).copied().flatten() {
                let text: String = chars[start..end].iter().collect();
                captures.insert(name.clone(), text);
            }
        }
        Match {
            // Character offsets, like Python's `re`: the intent parser slices
            // the normalised text with them.
            start: whole.0,
            end: whole.1,
            captures: captures.into_iter().collect(),
        }
    }

    fn match_at(&self, chars: &[char], start: usize) -> Option<Vec<Option<(usize, usize)>>> {
        let mut caps = vec![None; self.slots];
        let end = self.match_nodes(&self.nodes, chars, start, &mut caps)?;
        caps[0] = Some((start, end));
        Some(caps)
    }

    fn match_nodes(
        &self,
        nodes: &[Node],
        chars: &[char],
        pos: usize,
        caps: &mut Vec<Option<(usize, usize)>>,
    ) -> Option<usize> {
        let Some((first, rest)) = nodes.split_first() else {
            return Some(pos);
        };
        match first {
            Node::Char(ch) => {
                if chars.get(pos) == Some(ch) {
                    self.match_nodes(rest, chars, pos + 1, caps)
                } else {
                    None
                }
            }
            Node::Any => {
                if chars.get(pos).is_some_and(|ch| *ch != '\n') {
                    self.match_nodes(rest, chars, pos + 1, caps)
                } else {
                    None
                }
            }
            Node::Class(class) => {
                if chars.get(pos).is_some_and(|ch| class.matches(*ch)) {
                    self.match_nodes(rest, chars, pos + 1, caps)
                } else {
                    None
                }
            }
            Node::Bol => {
                if pos == 0 {
                    self.match_nodes(rest, chars, pos, caps)
                } else {
                    None
                }
            }
            Node::Eol => {
                if pos == chars.len() {
                    self.match_nodes(rest, chars, pos, caps)
                } else {
                    None
                }
            }
            Node::WordBoundary => {
                if is_boundary(chars, pos) {
                    self.match_nodes(rest, chars, pos, caps)
                } else {
                    None
                }
            }
            Node::NotWordBoundary => {
                if !is_boundary(chars, pos) {
                    self.match_nodes(rest, chars, pos, caps)
                } else {
                    None
                }
            }
            Node::Group { index, nodes: inner } => {
                // Flatten the group into the enclosing sequence: a group is not
                // an isolated match, its alternatives must be able to retry
                // once the rest of the pattern fails (`(?:a|ab)$` on "ab").
                let mut combined: Vec<Node> = Vec::with_capacity(inner.len() + 1 + rest.len());
                combined.extend_from_slice(inner);
                if *index != usize::MAX {
                    combined.push(Node::SetCapture {
                        index: *index,
                        start: pos,
                    });
                }
                combined.extend_from_slice(rest);
                self.match_nodes(&combined, chars, pos, caps)
            }
            Node::SetCapture { index, start } => {
                let saved = caps[*index];
                caps[*index] = Some((*start, pos));
                if let Some(result) = self.match_nodes(rest, chars, pos, caps) {
                    return Some(result);
                }
                caps[*index] = saved;
                None
            }
            Node::Alt(branches) => {
                for branch in branches {
                    let saved = caps.clone();
                    if let Some(end) = self.match_nodes(branch, chars, pos, caps) {
                        if let Some(result) = self.match_nodes(rest, chars, end, caps) {
                            return Some(result);
                        }
                    }
                    *caps = saved;
                }
                None
            }
            Node::Repeat { node, min, max } => {
                self.match_repeat(node, *min, *max, 0, chars, pos, caps, rest)
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn match_repeat(
        &self,
        node: &Node,
        min: usize,
        max: Option<usize>,
        count: usize,
        chars: &[char],
        pos: usize,
        caps: &mut Vec<Option<(usize, usize)>>,
        rest: &[Node],
    ) -> Option<usize> {
        if max.is_none_or(|max| count < max) {
            let single = std::slice::from_ref(node);
            let saved = caps.clone();
            if let Some(end) = self.match_nodes(single, chars, pos, caps) {
                // An empty repetition would loop forever; stop growing instead.
                if end > pos || count < min {
                    if let Some(result) =
                        self.match_repeat(node, min, max, count + 1, chars, end, caps, rest)
                    {
                        return Some(result);
                    }
                }
                *caps = saved;
            }
        }
        if count >= min {
            return self.match_nodes(rest, chars, pos, caps);
        }
        None
    }
}

fn is_boundary(chars: &[char], pos: usize) -> bool {
    let before = pos.checked_sub(1).and_then(|i| chars.get(i)).copied();
    let after = chars.get(pos).copied();
    let before_word = before.is_some_and(is_word);
    let after_word = after.is_some_and(is_word);
    before_word != after_word
}

struct Parser<'a> {
    chars: &'a [char],
    pos: usize,
    slots: usize,
    names: Vec<(String, usize)>,
}

impl Parser<'_> {
    fn peek(&self) -> Option<char> {
        self.chars.get(self.pos).copied()
    }

    fn next(&mut self) -> Option<char> {
        let ch = self.peek()?;
        self.pos += 1;
        Some(ch)
    }

    fn eat(&mut self, ch: char) -> bool {
        if self.peek() == Some(ch) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn parse_alt(&mut self) -> Option<Vec<Node>> {
        let mut branches = vec![self.parse_seq()?];
        while self.eat('|') {
            branches.push(self.parse_seq()?);
        }
        if branches.len() == 1 {
            branches.pop()
        } else {
            Some(vec![Node::Alt(branches)])
        }
    }

    fn parse_seq(&mut self) -> Option<Vec<Node>> {
        let mut nodes = Vec::new();
        while let Some(ch) = self.peek() {
            if ch == '|' || ch == ')' {
                break;
            }
            let atom = self.parse_atom()?;
            let atom = self.parse_quantifier(atom)?;
            nodes.push(atom);
        }
        Some(nodes)
    }

    fn parse_quantifier(&mut self, atom: Node) -> Option<Node> {
        let (min, max) = match self.peek() {
            Some('*') => {
                self.pos += 1;
                (0, None)
            }
            Some('+') => {
                self.pos += 1;
                (1, None)
            }
            Some('?') => {
                self.pos += 1;
                (0, Some(1))
            }
            Some('{') => {
                let start = self.pos;
                self.pos += 1;
                let mut min_text = String::new();
                while let Some(ch) = self.peek() {
                    if ch.is_ascii_digit() {
                        min_text.push(ch);
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
                if min_text.is_empty() {
                    self.pos = start;
                    return Some(atom);
                }
                let min: usize = min_text.parse().ok()?;
                let max = if self.eat(',') {
                    let mut max_text = String::new();
                    while let Some(ch) = self.peek() {
                        if ch.is_ascii_digit() {
                            max_text.push(ch);
                            self.pos += 1;
                        } else {
                            break;
                        }
                    }
                    if max_text.is_empty() {
                        None
                    } else {
                        Some(max_text.parse().ok()?)
                    }
                } else {
                    Some(min)
                };
                if !self.eat('}') {
                    return None;
                }
                (min, max)
            }
            _ => return Some(atom),
        };
        Some(Node::Repeat {
            node: Box::new(atom),
            min,
            max,
        })
    }

    fn parse_atom(&mut self) -> Option<Node> {
        match self.next()? {
            '(' => {
                let mut index = None;
                if self.eat('?') {
                    if self.eat(':') {
                        // non-capturing
                    } else if self.peek() == Some('P') {
                        self.pos += 1;
                        if !self.eat('<') {
                            return None;
                        }
                        let mut name = String::new();
                        while let Some(ch) = self.peek() {
                            if ch == '>' {
                                break;
                            }
                            name.push(ch);
                            self.pos += 1;
                        }
                        if !self.eat('>') {
                            return None;
                        }
                        let slot = self.slots;
                        self.slots += 1;
                        self.names.push((name, slot));
                        index = Some(slot);
                    } else {
                        return None;
                    }
                } else {
                    let slot = self.slots;
                    self.slots += 1;
                    index = Some(slot);
                }
                let inner = self.parse_alt()?;
                if !self.eat(')') {
                    return None;
                }
                match index {
                    Some(index) => Some(Node::Group {
                        index,
                        nodes: inner,
                    }),
                    None => Some(Node::Group {
                        index: usize::MAX,
                        nodes: inner,
                    }),
                }
            }
            '[' => self.parse_class(),
            '.' => Some(Node::Any),
            '^' => Some(Node::Bol),
            '$' => Some(Node::Eol),
            '\\' => self.parse_escape(),
            ch => Some(Node::Char(ch)),
        }
    }

    fn parse_escape(&mut self) -> Option<Node> {
        let ch = self.next()?;
        let mut class = Class::empty();
        match ch {
            'w' => class.word = true,
            'W' => class.neg_word = true,
            's' => class.space = true,
            'S' => class.neg_space = true,
            'd' => class.digit = true,
            'D' => class.neg_digit = true,
            'b' => return Some(Node::WordBoundary),
            'B' => return Some(Node::NotWordBoundary),
            'n' => return Some(Node::Char('\n')),
            't' => return Some(Node::Char('\t')),
            'r' => return Some(Node::Char('\r')),
            other => return Some(Node::Char(other)),
        }
        Some(Node::Class(class))
    }

    fn parse_class(&mut self) -> Option<Node> {
        let mut class = Class::empty();
        if self.eat('^') {
            class.negated = true;
        }
        let mut first = true;
        loop {
            let ch = self.next()?;
            if ch == ']' && !first {
                break;
            }
            first = false;
            let low = if ch == '\\' {
                let escaped = self.next()?;
                match escaped {
                    'w' => {
                        class.word = true;
                        continue;
                    }
                    's' => {
                        class.space = true;
                        continue;
                    }
                    'd' => {
                        class.digit = true;
                        continue;
                    }
                    other => other,
                }
            } else {
                ch
            };
            if self.peek() == Some('-') && self.chars.get(self.pos + 1).copied() != Some(']') {
                self.pos += 1;
                let high = self.next()?;
                class.push_range(low, high)?;
            } else {
                class.push_range(low, low)?;
            }
        }
        Some(Node::Class(class))
    }
}

/// Escape every metacharacter, the way `re.escape` does for our patterns.
pub fn escape(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch.is_alphanumeric() || ch == '_' {
            out.push(ch);
        } else {
            out.push('\\');
            out.push(ch);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn search(pattern: &str, text: &str) -> Option<(usize, usize)> {
        let regex = Regex::new(pattern)?;
        regex.search(text).map(|m| (m.start, m.end))
    }

    #[test]
    fn literal_and_alternation() {
        let regex = Regex::new("(?:pause|стоп)").unwrap();
        assert!(regex.is_match("сделай стоп сейчас"));
        // Unanchored search matches inside a word, exactly like `re.search`.
        assert!(regex.is_match("стопно"));
        let bounded = Regex::new(r"\bстоп\b").unwrap();
        assert!(!bounded.is_match("стопно"));
    }

    #[test]
    fn word_suffix_wildcards() {
        assert_eq!(search(r"трек\w*", "включи треки"), Some((7, 12)));
        assert_eq!(search(r"трек\w*", "трек"), Some((0, 4)));
        assert_eq!(search(r"трек\w*", "тре"), None);
    }

    #[test]
    fn digit_classes_and_quantifiers() {
        assert_eq!(search(r"\d{1,3}", "volume 42"), Some((7, 9)));
        assert_eq!(search(r"\d{1,2}:\d{1,2}", "на 1:30"), Some((3, 7)));
    }

    #[test]
    fn greedy_repetition_backtracks() {
        // `.+)` must not eat the trailing "!" anchor away from `$`.
        let regex = Regex::new(r"^(?P<value>.+)$").unwrap();
        let m = regex.search("The Mantle").unwrap();
        assert_eq!(m.end, 10);
        assert_eq!(regex.group(&m, "value"), Some("The Mantle"));
    }

    #[test]
    fn word_boundaries() {
        let regex = Regex::new(r"\bмне\b").unwrap();
        assert!(regex.is_match("дай мне трек"));
        assert!(!regex.is_match("мнетрек"));
    }

    #[test]
    fn classes_with_ranges() {
        let regex = Regex::new(r"[а-яё]+").unwrap();
        assert!(regex.is_match("привет"));
        assert!(!regex.is_match("hello"));
        let regex = Regex::new(r"[^а-яё ]+").unwrap();
        assert_eq!(search(r"[^а-яё ]+", "привет world"), Some((7, 12)));
    }

    #[test]
    fn anchors_and_fullmatch() {
        let regex = Regex::new("^play$").unwrap();
        assert!(regex.fullmatch("play").is_some());
        assert!(regex.fullmatch("play ").is_none());
        assert!(regex.fullmatch(" play").is_none());
    }

    #[test]
    fn groups_keep_their_names() {
        let regex = Regex::new(r"(?P<tag>album|artist)\s+(?P<value>.+)").unwrap();
        let m = regex.search("album The Mantle").unwrap();
        assert_eq!(regex.group(&m, "tag"), Some("album"));
        assert_eq!(regex.group(&m, "value"), Some("The Mantle"));
    }

    #[test]
    fn empty_repetition_terminates() {
        // `a*` over "b" must terminate and match empty before it.
        let regex = Regex::new(r"a*b").unwrap();
        assert_eq!(regex.search("b").map(|m| (m.start, m.end)), Some((0, 1)));
        assert_eq!(regex.search("aaab").map(|m| (m.start, m.end)), Some((0, 4)));
    }

    #[test]
    fn unbounded_repetition_of_a_group_is_rejected() {
        // A repetition matches its operand in isolation, so an operand with
        // internal choices could not backtrack; the compiler refuses those
        // instead of silently matching short (no rule in the table needs one).
        assert!(Regex::new(r"(?:ab)*").is_none());
        assert!(Regex::new(r"(?:\w*)+").is_none());
        // A single-character operand stays supported.
        assert!(Regex::new(r"\w*").is_some());
    }

    #[test]
    fn bounded_repetition_of_a_group_backtracks() {
        let regex = Regex::new(r"^(?:a|ab){1,2}$").unwrap();
        assert!(regex.fullmatch("ab").is_some());
        assert!(regex.fullmatch("aab").is_some());
        assert!(regex.fullmatch("").is_none());
    }

    #[test]
    fn escape_round_trips_through_the_parser() {
        let pattern = escape("a.b*c");
        let regex = Regex::new(&pattern).unwrap();
        assert!(regex.is_match("xxa.b*cxx"));
        assert!(!regex.is_match("aXbYc"));
    }

    #[test]
    fn optional_groups() {
        let regex = Regex::new(r"(?:громче)(?:\s+на\s+\d{1,3})?").unwrap();
        assert_eq!(search(r"(?:громче)(?:\s+на\s+\d{1,3})?", "громче на 15"), Some((0, 12)));
        assert_eq!(search(r"(?:громче)(?:\s+на\s+\d{1,3})?", "громче"), Some((0, 6)));
    }
}
