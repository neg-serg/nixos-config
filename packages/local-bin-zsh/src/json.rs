//! Minimal JSON reader for the music similarity index files.
//!
//! `mode_profile` used to shell out to `python3 -c` three times: twice for the
//! scalars of `meta.json` and once for the artist histogram of
//! `tracks.jsonl`. Parsing that data is what the ports move in-process, so this
//! module reproduces the parts of `json.loads` the scripts relied on: a strict
//! document parser, `str.strip('/')`-style path handling in the caller, and the
//! scalar rendering `print()` produces (`42`, `"text"`, `True`, `None`).
//!
//! Containers inside `meta.json` are rendered as compact JSON rather than as a
//! Python repr; the index files only carry numbers, so the difference is not
//! observable for them.

#![forbid(unsafe_code)]

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    /// The literal number text, so integer and exponent forms survive.
    Number(String),
    String(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            // `json.loads` keeps the last duplicate key, so look from the end.
            Value::Object(members) => members
                .iter()
                .rev()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value),
            _ => None,
        }
    }

    /// What `python3 -c 'print(value)'` prints for the value.
    pub fn python_repr(&self) -> String {
        match self {
            Value::Null => "None".to_string(),
            Value::Bool(true) => "True".to_string(),
            Value::Bool(false) => "False".to_string(),
            Value::Number(literal) => literal.clone(),
            Value::String(text) => text.clone(),
            Value::Array(items) => {
                let rendered: Vec<String> = items.iter().map(|item| item.json_repr()).collect();
                format!("[{}]", rendered.join(", "))
            }
            Value::Object(members) => {
                let rendered: Vec<String> = members
                    .iter()
                    .map(|(key, value)| format!("{}: {}", json_string(key), value.json_repr()))
                    .collect();
                format!("{{{}}}", rendered.join(", "))
            }
        }
    }

    fn json_repr(&self) -> String {
        match self {
            Value::String(text) => json_string(text),
            other => other.python_repr(),
        }
    }
}

fn json_string(text: &str) -> String {
    let mut rendered = String::with_capacity(text.len() + 2);
    rendered.push('"');
    for character in text.chars() {
        match character {
            '"' => rendered.push_str("\\\""),
            '\\' => rendered.push_str("\\\\"),
            '\n' => rendered.push_str("\\n"),
            '\r' => rendered.push_str("\\r"),
            '\t' => rendered.push_str("\\t"),
            character if (character as u32) < 0x20 => {
                rendered.push_str(&format!("\\u{:04x}", character as u32));
            }
            character => rendered.push(character),
        }
    }
    rendered.push('"');
    rendered
}

const MAX_DEPTH: usize = 64;

struct Parser<'a> {
    bytes: &'a [u8],
    position: usize,
}

/// Parse one JSON document with the whitespace/escape rules of `json.loads`.
pub fn parse(text: &str) -> Result<Value, ()> {
    let mut parser = Parser {
        bytes: text.as_bytes(),
        position: 0,
    };
    parser.skip_whitespace();
    let value = parser.value(0)?;
    parser.skip_whitespace();
    if parser.position == parser.bytes.len() {
        Ok(value)
    } else {
        Err(())
    }
}

impl Parser<'_> {
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.position).copied()
    }

    fn skip_whitespace(&mut self) {
        while let Some(byte) = self.peek() {
            if matches!(byte, b' ' | b'\t' | b'\n' | b'\r') {
                self.position += 1;
            } else {
                break;
            }
        }
    }

    fn literal(&mut self, text: &[u8], value: Value) -> Result<Value, ()> {
        if self.bytes[self.position..].starts_with(text) {
            self.position += text.len();
            Ok(value)
        } else {
            Err(())
        }
    }

    fn value(&mut self, depth: usize) -> Result<Value, ()> {
        if depth > MAX_DEPTH {
            return Err(());
        }
        match self.peek() {
            None => Err(()),
            Some(b'{') => self.object(depth),
            Some(b'[') => self.array(depth),
            Some(b'"') => self.string().map(Value::String),
            Some(b't') => self.literal(b"true", Value::Bool(true)),
            Some(b'f') => self.literal(b"false", Value::Bool(false)),
            Some(b'n') => self.literal(b"null", Value::Null),
            Some(b'-') | Some(b'0'..=b'9') => self.number(),
            Some(_) => Err(()),
        }
    }

    fn object(&mut self, depth: usize) -> Result<Value, ()> {
        self.position += 1; // '{'
        let mut members = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b'}') {
            self.position += 1;
            return Ok(Value::Object(members));
        }
        loop {
            self.skip_whitespace();
            if self.peek() != Some(b'"') {
                return Err(());
            }
            let key = self.string()?;
            self.skip_whitespace();
            if self.peek() != Some(b':') {
                return Err(());
            }
            self.position += 1;
            self.skip_whitespace();
            let value = self.value(depth + 1)?;
            members.push((key, value));
            self.skip_whitespace();
            match self.peek() {
                Some(b',') => {
                    self.position += 1;
                }
                Some(b'}') => {
                    self.position += 1;
                    return Ok(Value::Object(members));
                }
                _ => return Err(()),
            }
        }
    }

    fn array(&mut self, depth: usize) -> Result<Value, ()> {
        self.position += 1; // '['
        let mut items = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b']') {
            self.position += 1;
            return Ok(Value::Array(items));
        }
        loop {
            self.skip_whitespace();
            items.push(self.value(depth + 1)?);
            self.skip_whitespace();
            match self.peek() {
                Some(b',') => {
                    self.position += 1;
                }
                Some(b']') => {
                    self.position += 1;
                    return Ok(Value::Array(items));
                }
                _ => return Err(()),
            }
        }
    }

    fn number(&mut self) -> Result<Value, ()> {
        let start = self.position;
        if self.peek() == Some(b'-') {
            self.position += 1;
        }
        match self.peek() {
            Some(b'0') => self.position += 1,
            Some(b'1'..=b'9') => {
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.position += 1;
                }
            }
            _ => return Err(()),
        }
        if self.peek() == Some(b'.') {
            self.position += 1;
            let fraction_start = self.position;
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.position += 1;
            }
            if self.position == fraction_start {
                return Err(());
            }
        }
        if matches!(self.peek(), Some(b'e') | Some(b'E')) {
            self.position += 1;
            if matches!(self.peek(), Some(b'+') | Some(b'-')) {
                self.position += 1;
            }
            let exponent_start = self.position;
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.position += 1;
            }
            if self.position == exponent_start {
                return Err(());
            }
        }
        let literal = std::str::from_utf8(&self.bytes[start..self.position])
            .expect("number literals are ASCII")
            .to_string();
        Ok(Value::Number(literal))
    }

    fn string(&mut self) -> Result<String, ()> {
        self.position += 1; // '"'
        let mut text = String::new();
        loop {
            let byte = self.peek().ok_or(())?;
            match byte {
                b'"' => {
                    self.position += 1;
                    return Ok(text);
                }
                b'\\' => {
                    self.position += 1;
                    let escape = self.peek().ok_or(())?;
                    self.position += 1;
                    match escape {
                        b'"' => text.push('"'),
                        b'\\' => text.push('\\'),
                        b'/' => text.push('/'),
                        b'b' => text.push('\u{0008}'),
                        b'f' => text.push('\u{000c}'),
                        b'n' => text.push('\n'),
                        b'r' => text.push('\r'),
                        b't' => text.push('\t'),
                        b'u' => {
                            let first = self.hex4()?;
                            let character = if (0xD800..=0xDBFF).contains(&first) {
                                if self.peek() != Some(b'\\') {
                                    return Err(());
                                }
                                self.position += 1;
                                if self.peek() != Some(b'u') {
                                    return Err(());
                                }
                                self.position += 1;
                                let second = self.hex4()?;
                                if !(0xDC00..=0xDFFF).contains(&second) {
                                    return Err(());
                                }
                                let code = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
                                char::from_u32(code).ok_or(())?
                            } else {
                                char::from_u32(first).ok_or(())?
                            };
                            text.push(character);
                        }
                        _ => return Err(()),
                    }
                }
                byte if byte < 0x20 => return Err(()),
                _ => {
                    // Decode one UTF-8 character; json.loads rejects invalid
                    // UTF-8, so do the same.
                    let remainder =
                        std::str::from_utf8(&self.bytes[self.position..]).map_err(|_| ())?;
                    let character = remainder.chars().next().ok_or(())?;
                    text.push(character);
                    self.position += character.len_utf8();
                }
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, ()> {
        if self.position + 4 > self.bytes.len() {
            return Err(());
        }
        let digits =
            std::str::from_utf8(&self.bytes[self.position..self.position + 4]).map_err(|_| ())?;
        if !digits.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(());
        }
        self.position += 4;
        u32::from_str_radix(digits, 16).map_err(|_| ())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_meta_shape() {
        let value = parse(r#"{"count": 42, "dim": 128}"#).expect("valid JSON");
        assert_eq!(
            value.get("count").map(Value::python_repr),
            Some("42".into())
        );
        assert_eq!(value.get("dim").map(Value::python_repr), Some("128".into()));
        assert_eq!(value.get("missing"), None);
    }

    #[test]
    fn renders_python_scalars() {
        assert_eq!(parse("null").unwrap().python_repr(), "None");
        assert_eq!(parse("true").unwrap().python_repr(), "True");
        assert_eq!(parse("false").unwrap().python_repr(), "False");
        assert_eq!(parse("\"A·B\"").unwrap().python_repr(), "A·B");
        assert_eq!(parse("-1.5e3").unwrap().python_repr(), "-1.5e3");
    }

    #[test]
    fn decodes_escapes_and_surrogates() {
        assert_eq!(
            parse(r#""a\u00b7b\n""#).unwrap(),
            Value::String("a·b\n".to_string())
        );
        assert_eq!(
            parse(r#""\ud83d\ude00""#).unwrap(),
            Value::String("😀".to_string())
        );
    }

    #[test]
    fn rejects_bad_documents() {
        for text in ["", "{", "{\"a\":}", "[1,]", "01", "nul", "tru", "{} x"] {
            assert!(parse(text).is_err(), "{text:?} should be rejected");
        }
    }
}
