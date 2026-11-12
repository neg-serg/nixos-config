//! Minimal JSON reader shared by the `local-bin-tools` binaries.
//!
//! `paths` parses `nix eval --json`, `window-activate` parses `hyprctl clients
//! -j`, and `menu-search` parses DBusMenu payloads; its `--json` dump is also
//! the only user of the writer. The module was moved out of the three binaries
//! unchanged, so their parsing behavior cannot drift apart.
//!
//! The scope is deliberately narrow — full JSON compliance is a separate
//! decision with its own tests. These are the contracts of the current code,
//! not claims of correctness:
//!
//! * numbers are scanned as `-?digits(.digits)?`, so exponent form (`1e5`)
//!   leaves trailing text and `parse` rejects the whole input;
//! * `\uXXXX` is decoded per code unit, so a surrogate pair becomes two
//!   `U+FFFD` (non-BMP text is not round-tripped);
//! * `dump` is only exercised with `Some(indent)`; `None` still emits the
//!   newlines, so the compact mode is not usable today.

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
}

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
        self.pos += 1;
        let mut entries = Vec::new();
        self.skip_ws();
        if self.peek() == Some('}') {
            self.pos += 1;
            return Some(Value::Object(entries));
        }
        loop {
            self.skip_ws();
            let key = self.string()?;
            self.skip_ws();
            if self.peek() != Some(':') {
                return None;
            }
            self.pos += 1;
            entries.push((key, self.value()?));
            self.skip_ws();
            match self.peek()? {
                ',' => self.pos += 1,
                '}' => {
                    self.pos += 1;
                    return Some(Value::Object(entries));
                }
                _ => return None,
            }
        }
    }

    fn array(&mut self) -> Option<Value> {
        self.pos += 1;
        let mut items = Vec::new();
        self.skip_ws();
        if self.peek() == Some(']') {
            self.pos += 1;
            return Some(Value::Array(items));
        }
        loop {
            items.push(self.value()?);
            self.skip_ws();
            match self.peek()? {
                ',' => self.pos += 1,
                ']' => {
                    self.pos += 1;
                    return Some(Value::Array(items));
                }
                _ => return None,
            }
        }
    }

    fn string(&mut self) -> Option<String> {
        if self.peek() != Some('"') {
            return None;
        }
        self.pos += 1;
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
                        'u' => {
                            let mut code = String::new();
                            for _ in 0..4 {
                                code.push(self.peek()?);
                                self.pos += 1;
                            }
                            let value = u32::from_str_radix(&code, 16).ok()?;
                            out.push(char::from_u32(value).unwrap_or('\u{fffd}'));
                        }
                        other => out.push(other),
                    }
                }
                other => out.push(other),
            }
        }
    }

    fn number(&mut self) -> Option<Value> {
        let start = self.pos;
        if self.peek() == Some('-') {
            self.pos += 1;
        }
        while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
            self.pos += 1;
        }
        if self.peek() == Some('.') {
            self.pos += 1;
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

// `menu-search` is the only binary that renders JSON back out; the other two
// compile the writer without calling it, so the whole module is allowed to be
// unused there instead of scattering `allow(dead_code)` over every helper.
#[allow(dead_code)]
mod writer {
    use super::Value;

    impl Value {
        /// `json.dumps(value, ensure_ascii=False, indent=indent)`.
        pub fn dump(&self, indent: Option<usize>) -> String {
            let mut out = String::new();
            self.write(&mut out, indent, 0);
            out
        }

        fn write(&self, out: &mut String, indent: Option<usize>, level: usize) {
            match self {
                Value::Null => out.push_str("null"),
                Value::Bool(flag) => out.push_str(if *flag { "true" } else { "false" }),
                Value::Number(number) => {
                    if number.fract() == 0.0 && number.abs() < 1e15 {
                        out.push_str(&format!("{}", *number as i64));
                    } else {
                        out.push_str(&format!("{number}"));
                    }
                }
                Value::Str(text) => write_string(out, text),
                Value::Array(items) => {
                    if items.is_empty() {
                        out.push_str("[]");
                        return;
                    }
                    out.push('[');
                    for (index, item) in items.iter().enumerate() {
                        if index > 0 {
                            out.push(',');
                        }
                        newline(out, indent, level + 1);
                        item.write(out, indent, level + 1);
                    }
                    close(out, indent, level);
                    out.push(']');
                }
                Value::Object(entries) => {
                    if entries.is_empty() {
                        out.push_str("{}");
                        return;
                    }
                    out.push('{');
                    for (index, (key, value)) in entries.iter().enumerate() {
                        if index > 0 {
                            out.push(',');
                        }
                        newline(out, indent, level + 1);
                        write_string(out, key);
                        out.push_str(": ");
                        value.write(out, indent, level + 1);
                    }
                    close(out, indent, level);
                    out.push('}');
                }
            }
        }
    }

    fn newline(out: &mut String, indent: Option<usize>, level: usize) {
        out.push('\n');
        if let Some(width) = indent {
            for _ in 0..width * level {
                out.push(' ');
            }
        }
    }

    fn close(out: &mut String, indent: Option<usize>, level: usize) {
        if indent.is_some() {
            newline(out, indent, level);
        }
    }

    fn write_string(out: &mut String, text: &str) {
        out.push('"');
        for ch in text.chars() {
            match ch {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
                ch => out.push(ch),
            }
        }
        out.push('"');
    }
}

#[cfg(test)]
mod tests {
    use super::{parse, Value};

    fn object(fields: Vec<(&str, Value)>) -> Value {
        Value::Object(
            fields
                .into_iter()
                .map(|(name, value)| (name.to_string(), value))
                .collect(),
        )
    }

    #[test]
    fn parses_scalars() {
        assert_eq!(parse("null"), Some(Value::Null));
        assert_eq!(parse("true"), Some(Value::Bool(true)));
        assert_eq!(parse(" false "), Some(Value::Bool(false)));
        assert_eq!(parse("42"), Some(Value::Number(42.0)));
        assert_eq!(parse("-1.5"), Some(Value::Number(-1.5)));
        assert_eq!(parse(r#""text""#), Some(Value::Str("text".to_string())));
    }

    #[test]
    fn parses_nested_arrays_and_objects() {
        let value = parse(r#"{"a":[1,{"b":null}],"c":{"d":true}}"#).expect("valid JSON");
        assert_eq!(
            value.get("a"),
            Some(&Value::Array(vec![
                Value::Number(1.0),
                object(vec![("b", Value::Null)]),
            ]))
        );
        assert_eq!(
            value.get("c").and_then(|inner| inner.get("d")),
            Some(&Value::Bool(true))
        );
    }

    #[test]
    fn decodes_escapes() {
        let value = parse(r#""a\"b\\c\/d\ne\tf\rg\u0041""#).expect("valid JSON");
        assert_eq!(value, Value::Str("a\"b\\c/d\ne\tf\rgA".to_string()));
    }

    #[test]
    fn rejects_malformed_input() {
        for text in ["", "{", r#"{"a":1"#, "[1,]", "\"unterminated", "tru", "{}x"] {
            assert_eq!(parse(text), None, "input: {text:?}");
        }
    }

    #[test]
    fn rejects_trailing_text() {
        assert_eq!(parse("1 2"), None);
        assert_eq!(parse("null null"), None);
    }

    #[test]
    fn exponent_form_is_rejected() {
        // The number scanner stops at `e`/`E`, and the leftover text fails the
        // trailing-input check. Keep this in sync with the module docs.
        assert_eq!(parse("1e5"), None);
        assert_eq!(parse("1.5E-3"), None);
    }

    #[test]
    fn surrogate_pairs_become_replacement_characters() {
        // `\uXXXX` is one code unit here, so a surrogate pair cannot be
        // combined into one char. Documented limitation, not an accident.
        assert_eq!(
            parse(r#""\ud83d\ude00""#),
            Some(Value::Str("\u{fffd}\u{fffd}".to_string()))
        );
    }

    #[test]
    fn dumps_indented_json() {
        let value = object(vec![
            ("a", Value::Number(1.0)),
            ("b", Value::Str("x\ny".to_string())),
        ]);
        assert_eq!(value.dump(Some(1)), "{\n \"a\": 1,\n \"b\": \"x\\ny\"\n}");
        assert_eq!(Value::Array(Vec::new()).dump(Some(1)), "[]");
        assert_eq!(Value::Object(Vec::new()).dump(Some(1)), "{}");
    }
}
