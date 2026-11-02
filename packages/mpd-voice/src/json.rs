//! A small JSON reader for the mood-tag records.
//!
//! The tag file is JSONL written by `music-mtg-tags`: one object per track with
//! `path`, `audio_seconds` and `tags.mood[{label, score}]`. Neither a full
//! serde dependency nor a hand-rolled field scan can express the nested shapes
//! the controller walks, so this module parses the subset JSON uses.

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Number(f64),
    Str(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(entries) => entries
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(text) => Some(text),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Value::Number(number) => Some(*number),
            Value::Str(text) => text.trim().parse::<f64>().ok(),
            Value::Bool(flag) => Some(if *flag { 1.0 } else { 0.0 }),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(items) => Some(items),
            _ => None,
        }
    }

    pub fn is_object(&self) -> bool {
        matches!(self, Value::Object(_))
    }
}

/// Parse one JSON document; `None` on any syntax error (the caller skips the
/// line, which is what the Python reader does with a broken record).
pub fn parse(text: &str) -> Option<Value> {
    let chars: Vec<char> = text.chars().collect();
    let mut parser = Parser { chars, pos: 0 };
    let value = parser.value()?;
    parser.skip_ws();
    if parser.pos != parser.chars.len() {
        return None;
    }
    Some(value)
}

struct Parser {
    chars: Vec<char>,
    pos: usize,
}

impl Parser {
    fn peek(&self) -> Option<char> {
        self.chars.get(self.pos).copied()
    }

    fn skip_ws(&mut self) {
        while matches!(self.peek(), Some(ch) if ch.is_whitespace()) {
            self.pos += 1;
        }
    }

    fn eat(&mut self, ch: char) -> bool {
        if self.peek() == Some(ch) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn value(&mut self) -> Option<Value> {
        self.skip_ws();
        match self.peek()? {
            '{' => self.object(),
            '[' => self.array(),
            '"' => self.string().map(Value::Str),
            't' => self.literal("true", Value::Bool(true)),
            'f' => self.literal("false", Value::Bool(false)),
            'n' => self.literal("null", Value::Null),
            _ => self.number(),
        }
    }

    fn literal(&mut self, text: &str, value: Value) -> Option<Value> {
        for expected in text.chars() {
            if self.peek()? != expected {
                return None;
            }
            self.pos += 1;
        }
        Some(value)
    }

    fn object(&mut self) -> Option<Value> {
        self.pos += 1; // {
        let mut entries = Vec::new();
        self.skip_ws();
        if self.eat('}') {
            return Some(Value::Object(entries));
        }
        loop {
            self.skip_ws();
            let key = self.string()?;
            self.skip_ws();
            if !self.eat(':') {
                return None;
            }
            let value = self.value()?;
            entries.push((key, value));
            self.skip_ws();
            if self.eat(',') {
                continue;
            }
            if self.eat('}') {
                return Some(Value::Object(entries));
            }
            return None;
        }
    }

    fn array(&mut self) -> Option<Value> {
        self.pos += 1; // [
        let mut items = Vec::new();
        self.skip_ws();
        if self.eat(']') {
            return Some(Value::Array(items));
        }
        loop {
            items.push(self.value()?);
            self.skip_ws();
            if self.eat(',') {
                continue;
            }
            if self.eat(']') {
                return Some(Value::Array(items));
            }
            return None;
        }
    }

    fn string(&mut self) -> Option<String> {
        if !self.eat('"') {
            return None;
        }
        let mut out = String::new();
        loop {
            let ch = self.peek()?;
            self.pos += 1;
            match ch {
                '"' => return Some(out),
                '\\' => {
                    let escaped = self.peek()?;
                    self.pos += 1;
                    match escaped {
                        '"' => out.push('"'),
                        '\\' => out.push('\\'),
                        '/' => out.push('/'),
                        'n' => out.push('\n'),
                        't' => out.push('\t'),
                        'r' => out.push('\r'),
                        'b' => out.push('\u{8}'),
                        'f' => out.push('\u{c}'),
                        'u' => {
                            let mut code = String::new();
                            for _ in 0..4 {
                                code.push(self.peek()?);
                                self.pos += 1;
                            }
                            let value = u32::from_str_radix(&code, 16).ok()?;
                            out.push(char::from_u32(value).unwrap_or('\u{fffd}'));
                        }
                        _ => return None,
                    }
                }
                other => out.push(other),
            }
        }
    }

    fn number(&mut self) -> Option<Value> {
        let start = self.pos;
        if matches!(self.peek(), Some('-')) {
            self.pos += 1;
        }
        while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
            self.pos += 1;
        }
        if matches!(self.peek(), Some('.')) {
            self.pos += 1;
            while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                self.pos += 1;
            }
        }
        if matches!(self.peek(), Some('e') | Some('E')) {
            self.pos += 1;
            if matches!(self.peek(), Some('+') | Some('-')) {
                self.pos += 1;
            }
            while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                self.pos += 1;
            }
        }
        if self.pos == start {
            return None;
        }
        let text: String = self.chars[start..self.pos].iter().collect();
        text.parse::<f64>().ok().map(Value::Number)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_tag_record() {
        let record = parse(
            r#"{"path": "/music/a.flac", "audio_seconds": 61.5,
                "tags": {"mood": [{"label": "dark", "score": 0.31},
                                  {"label": "sad", "score": 0.2}]}}"#,
        )
        .expect("record");
        assert_eq!(
            record.get("path").and_then(Value::as_str),
            Some("/music/a.flac")
        );
        assert_eq!(
            record.get("audio_seconds").and_then(Value::as_f64),
            Some(61.5)
        );
        let moods = record
            .get("tags")
            .and_then(|tags| tags.get("mood"))
            .and_then(Value::as_array)
            .expect("mood array");
        assert_eq!(moods.len(), 2);
        assert_eq!(moods[0].get("label").and_then(Value::as_str), Some("dark"));
        assert_eq!(moods[0].get("score").and_then(Value::as_f64), Some(0.31));
    }

    #[test]
    fn scalars_and_escapes() {
        assert_eq!(parse("null"), Some(Value::Null));
        assert_eq!(parse("true"), Some(Value::Bool(true)));
        assert_eq!(parse("-12.5e2"), Some(Value::Number(-1250.0)));
        assert_eq!(
            parse(r#""a\"b\u0041""#),
            Some(Value::Str("a\"bA".to_string()))
        );
    }

    #[test]
    fn broken_documents_are_rejected() {
        assert!(parse("{").is_none());
        assert!(parse("{\"a\": }").is_none());
        assert!(parse("[1,]x").is_none());
        assert!(parse("").is_none());
    }
}
