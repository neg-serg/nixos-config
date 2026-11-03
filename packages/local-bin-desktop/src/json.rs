//! Minimal JSON reader/writer that reproduces the jq behaviour the originals
//! relied on.
//!
//! The shell helpers piped `hyprctl`/`curl` output through `jq -r` and built the
//! Ollama payload with `jq -n --arg`. Keeping JSON in-process removes the jq
//! dependency while preserving the observable bytes: `raw()` matches `jq -r`
//! output, `pretty()` matches jq's default 2-space layout for the payload, and
//! the accessors follow jq's `// empty` truthiness rules (only `null` and
//! `false` are falsy, so an empty string stays an empty string).

#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(Vec<u8>),
    Arr(Vec<Json>),
    Obj(Vec<(Vec<u8>, Json)>),
}

impl Json {
    /// Parse one JSON document; trailing whitespace is allowed, trailing data is
    /// not (jq rejects it too).
    pub fn parse(bytes: &[u8]) -> Result<Json, ()> {
        let mut parser = Parser {
            bytes,
            position: 0,
            depth: 0,
        };
        parser.skip_whitespace();
        let value = parser.parse_value()?;
        parser.skip_whitespace();
        if parser.position != parser.bytes.len() {
            return Err(());
        }
        Ok(value)
    }

    /// jq object/array index access.
    pub fn get(&self, key: &str) -> Option<&Json> {
        let bytes = key.as_bytes();
        match self {
            Json::Obj(fields) => fields
                .iter()
                .find(|(name, _)| name.as_slice() == bytes)
                .map(|(_, value)| value),
            _ => None,
        }
    }

    pub fn index(&self, index: usize) -> Option<&Json> {
        match self {
            Json::Arr(items) => items.get(index),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&[u8]> {
        match self {
            Json::Str(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_number(&self) -> Option<f64> {
        match self {
            Json::Num(value) => Some(*value),
            _ => None,
        }
    }

    /// jq truthiness: false and null are false, everything else is true.
    pub fn truthy(&self) -> bool {
        !matches!(self, Json::Null | Json::Bool(false))
    }

    /// `jq -r` output for this value.
    pub fn raw(&self) -> Vec<u8> {
        match self {
            Json::Null => b"null".to_vec(),
            Json::Bool(true) => b"true".to_vec(),
            Json::Bool(false) => b"false".to_vec(),
            Json::Num(value) => number_text(*value),
            Json::Str(value) => value.clone(),
            Json::Arr(_) | Json::Obj(_) => self.pretty(),
        }
    }

    /// `jq -r '.path // empty'`: no output for null/false.
    pub fn raw_or_empty(&self) -> Vec<u8> {
        if self.truthy() {
            self.raw()
        } else {
            Vec::new()
        }
    }

    /// jq's default output layout (2-space indent, one member per line, no
    /// trailing newline because the callers capture the value with `$(...)`).
    pub fn pretty(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_pretty(self, 0, &mut out);
        out
    }
}

/// `jq -r` number spelling: integers lose the fractional part.
pub fn number_text(value: f64) -> Vec<u8> {
    if value.is_finite() && value.fract() == 0.0 && value.abs() < 9.007_199_254_740_992e15 {
        return format!("{}", value as i64).into_bytes();
    }
    let text = format!("{value}");
    text.into_bytes()
}

fn write_pretty(value: &Json, indent: usize, out: &mut Vec<u8>) {
    match value {
        Json::Null => out.extend_from_slice(b"null"),
        Json::Bool(true) => out.extend_from_slice(b"true"),
        Json::Bool(false) => out.extend_from_slice(b"false"),
        Json::Num(number) => out.extend_from_slice(&number_text(*number)),
        Json::Str(text) => write_string(text, out),
        Json::Arr(items) => {
            if items.is_empty() {
                out.extend_from_slice(b"[]");
                return;
            }
            out.extend_from_slice(b"[\n");
            for (index, item) in items.iter().enumerate() {
                write_indent(indent + 2, out);
                write_pretty(item, indent + 2, out);
                if index + 1 < items.len() {
                    out.push(b',');
                }
                out.push(b'\n');
            }
            write_indent(indent, out);
            out.push(b']');
        }
        Json::Obj(fields) => {
            if fields.is_empty() {
                out.extend_from_slice(b"{}");
                return;
            }
            out.extend_from_slice(b"{\n");
            for (index, (name, item)) in fields.iter().enumerate() {
                write_indent(indent + 2, out);
                write_string(name, out);
                out.extend_from_slice(b": ");
                write_pretty(item, indent + 2, out);
                if index + 1 < fields.len() {
                    out.push(b',');
                }
                out.push(b'\n');
            }
            write_indent(indent, out);
            out.push(b'}');
        }
    }
}

fn write_indent(count: usize, out: &mut Vec<u8>) {
    out.extend(std::iter::repeat(b' ').take(count));
}

fn write_string(text: &[u8], out: &mut Vec<u8>) {
    out.push(b'"');
    for byte in text {
        match byte {
            b'"' => out.extend_from_slice(b"\\\""),
            b'\\' => out.extend_from_slice(b"\\\\"),
            0x08 => out.extend_from_slice(b"\\b"),
            0x09 => out.extend_from_slice(b"\\t"),
            0x0a => out.extend_from_slice(b"\\n"),
            0x0c => out.extend_from_slice(b"\\f"),
            0x0d => out.extend_from_slice(b"\\r"),
            0x00..=0x1f => {
                out.extend_from_slice(format!("\\u{byte:04x}").as_bytes());
            }
            _ => out.push(*byte),
        }
    }
    out.push(b'"');
}

struct Parser<'a> {
    bytes: &'a [u8],
    position: usize,
    depth: usize,
}

impl<'a> Parser<'a> {
    fn skip_whitespace(&mut self) {
        while let Some(byte) = self.bytes.get(self.position) {
            match byte {
                b' ' | b'\t' | b'\n' | b'\r' => self.position += 1,
                _ => break,
            }
        }
    }

    fn parse_value(&mut self) -> Result<Json, ()> {
        if self.depth > 128 {
            return Err(());
        }
        let byte = *self.bytes.get(self.position).ok_or(())?;
        match byte {
            b'n' => {
                self.expect_literal(b"null")?;
                Ok(Json::Null)
            }
            b't' => {
                self.expect_literal(b"true")?;
                Ok(Json::Bool(true))
            }
            b'f' => {
                self.expect_literal(b"false")?;
                Ok(Json::Bool(false))
            }
            b'"' => Ok(Json::Str(self.parse_string()?)),
            b'[' => self.parse_array(),
            b'{' => self.parse_object(),
            b'-' | b'0'..=b'9' => self.parse_number(),
            _ => Err(()),
        }
    }

    fn expect_literal(&mut self, literal: &[u8]) -> Result<(), ()> {
        if self.bytes[self.position..].starts_with(literal) {
            self.position += literal.len();
            Ok(())
        } else {
            Err(())
        }
    }

    fn parse_string(&mut self) -> Result<Vec<u8>, ()> {
        if self.bytes.get(self.position) != Some(&b'"') {
            return Err(());
        }
        self.position += 1;
        let mut out = Vec::new();
        loop {
            let byte = *self.bytes.get(self.position).ok_or(())?;
            self.position += 1;
            match byte {
                b'"' => return Ok(out),
                b'\\' => {
                    let escape = *self.bytes.get(self.position).ok_or(())?;
                    self.position += 1;
                    match escape {
                        b'"' => out.push(b'"'),
                        b'\\' => out.push(b'\\'),
                        b'/' => out.push(b'/'),
                        b'b' => out.push(0x08),
                        b'f' => out.push(0x0c),
                        b'n' => out.push(b'\n'),
                        b'r' => out.push(b'\r'),
                        b't' => out.push(b'\t'),
                        b'u' => {
                            let first = self.parse_hex4()?;
                            let scalar = if (0xd800..=0xdbff).contains(&first) {
                                if self.bytes.get(self.position) != Some(&b'\\')
                                    || self.bytes.get(self.position + 1) != Some(&b'u')
                                {
                                    return Err(());
                                }
                                self.position += 2;
                                let second = self.parse_hex4()?;
                                if !(0xdc00..=0xdfff).contains(&second) {
                                    return Err(());
                                }
                                0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00)
                            } else {
                                first
                            };
                            let character = char::from_u32(scalar).unwrap_or('\u{fffd}');
                            let mut buffer = [0u8; 4];
                            out.extend_from_slice(character.encode_utf8(&mut buffer).as_bytes());
                        }
                        _ => return Err(()),
                    }
                }
                0x00..=0x1f => return Err(()),
                _ => out.push(byte),
            }
        }
    }

    fn parse_hex4(&mut self) -> Result<u32, ()> {
        let mut value = 0u32;
        for _ in 0..4 {
            let byte = *self.bytes.get(self.position).ok_or(())?;
            self.position += 1;
            let digit = char::from(byte).to_digit(16).ok_or(())?;
            value = value * 16 + digit;
        }
        Ok(value)
    }

    fn parse_array(&mut self) -> Result<Json, ()> {
        self.depth += 1;
        self.position += 1; // '['
        let mut items = Vec::new();
        self.skip_whitespace();
        if self.bytes.get(self.position) == Some(&b']') {
            self.position += 1;
            self.depth -= 1;
            return Ok(Json::Arr(items));
        }
        loop {
            self.skip_whitespace();
            items.push(self.parse_value()?);
            self.skip_whitespace();
            match self.bytes.get(self.position) {
                Some(b',') => self.position += 1,
                Some(b']') => {
                    self.position += 1;
                    self.depth -= 1;
                    return Ok(Json::Arr(items));
                }
                _ => return Err(()),
            }
        }
    }

    fn parse_object(&mut self) -> Result<Json, ()> {
        self.depth += 1;
        self.position += 1; // '{'
        let mut fields: Vec<(Vec<u8>, Json)> = Vec::new();
        self.skip_whitespace();
        if self.bytes.get(self.position) == Some(&b'}') {
            self.position += 1;
            self.depth -= 1;
            return Ok(Json::Obj(fields));
        }
        loop {
            self.skip_whitespace();
            let key = self.parse_string()?;
            self.skip_whitespace();
            if self.bytes.get(self.position) != Some(&b':') {
                return Err(());
            }
            self.position += 1;
            self.skip_whitespace();
            let value = self.parse_value()?;
            // jq keeps the last value for a duplicated key at the first
            // position, which is what an ordered Vec gives us.
            if let Some(existing) = fields.iter_mut().find(|(name, _)| name == &key) {
                existing.1 = value;
            } else {
                fields.push((key, value));
            }
            self.skip_whitespace();
            match self.bytes.get(self.position) {
                Some(b',') => self.position += 1,
                Some(b'}') => {
                    self.position += 1;
                    self.depth -= 1;
                    return Ok(Json::Obj(fields));
                }
                _ => return Err(()),
            }
        }
    }

    fn parse_number(&mut self) -> Result<Json, ()> {
        let start = self.position;
        if self.bytes.get(self.position) == Some(&b'-') {
            self.position += 1;
        }
        while matches!(self.bytes.get(self.position), Some(b'0'..=b'9')) {
            self.position += 1;
        }
        if self.bytes.get(self.position) == Some(&b'.') {
            self.position += 1;
            while matches!(self.bytes.get(self.position), Some(b'0'..=b'9')) {
                self.position += 1;
            }
        }
        if matches!(self.bytes.get(self.position), Some(b'e') | Some(b'E')) {
            self.position += 1;
            if matches!(self.bytes.get(self.position), Some(b'+') | Some(b'-')) {
                self.position += 1;
            }
            while matches!(self.bytes.get(self.position), Some(b'0'..=b'9')) {
                self.position += 1;
            }
        }
        let text = std::str::from_utf8(&self.bytes[start..self.position]).map_err(|_| ())?;
        let value: f64 = text.parse().map_err(|_| ())?;
        Ok(Json::Num(value))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_objects_and_lists() {
        let value = Json::parse(br#"{"a":[1,2,{"b":null}],"c":true}"#).unwrap();
        assert_eq!(value.get("c"), Some(&Json::Bool(true)));
        assert_eq!(
            value.get("a").unwrap().index(2).unwrap().get("b"),
            Some(&Json::Null)
        );
    }

    #[test]
    fn raw_matches_jq_r() {
        let value = Json::parse(br#"{"pid":4242,"f":1.5,"s":"x"}"#).unwrap();
        assert_eq!(value.get("pid").unwrap().raw(), b"4242");
        assert_eq!(value.get("f").unwrap().raw(), b"1.5");
        assert_eq!(value.get("s").unwrap().raw(), b"x");
        assert_eq!(value.get("missing").map(Json::raw), None);
        assert_eq!(Json::Null.raw_or_empty(), Vec::<u8>::new());
        assert_eq!(Json::Str(b"".to_vec()).raw_or_empty(), b"");
    }

    #[test]
    fn pretty_matches_jq_layout() {
        let value = Json::parse(br#"{"a":"b","l":[1,{"c":false}]}"#).unwrap();
        let expected =
            "{\n  \"a\": \"b\",\n  \"l\": [\n    1,\n    {\n      \"c\": false\n    }\n  ]\n}";
        assert_eq!(String::from_utf8(value.pretty()).unwrap(), expected);
    }

    #[test]
    fn escapes_strings_like_jq() {
        let value = Json::Str(b"a\"b\\c\nd".to_vec());
        assert_eq!(value.pretty(), b"\"a\\\"b\\\\c\\nd\"");
    }

    #[test]
    fn rejects_trailing_data() {
        assert!(Json::parse(br#"{"a":1} x"#).is_err());
        assert!(Json::parse(b"").is_err());
    }
}
