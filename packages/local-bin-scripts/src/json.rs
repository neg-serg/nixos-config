//! Minimal JSON reader/writer with the semantics `music-highlevel` observes.
//!
//! The original script loads the extractor output with `orjson` (it is
//! importable in the system Python) and writes its result with
//! `orjson.dumps`; both preserve object insertion order. This module therefore
//! keeps objects as ordered pairs, rejects the extensions `orjson` rejects
//! (`NaN`, `Infinity`, trailing commas, lone surrogates, BOM), lets a duplicate
//! key overwrite the value in its first position, and serializes numbers with
//! `pyfmt::orjson_float`.
//!
//! `orjson` keeps the token's kind: an integer literal that fits `i64`..`u64`
//! round-trips as an integer (`3`, not `3.0`), everything else becomes a double
//! (`3.0`, `1e3` -> `1000.0`; a literal too large for a double is rejected as
//! "number is infinity when parsed as double"). `Json::Int` and `Json::Num`
//! model that split; `Int` is wide enough for the whole accepted range.

use crate::pyfmt::orjson_float;

#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Int(i128),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(entries) => entries
                .iter()
                .find_map(|(name, value)| (name == key).then_some(value)),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_object(&self) -> Option<&[(String, Json)]> {
        match self {
            Json::Obj(entries) => Some(entries),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ParseError {
    message: String,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

fn location(bytes: &[u8], position: usize) -> (usize, usize) {
    let mut line = 1usize;
    let mut column = 1usize;
    for byte in &bytes[..position.min(bytes.len())] {
        if *byte == b'\n' {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    (line, column)
}

fn error_at(bytes: &[u8], position: usize, message: &str) -> ParseError {
    let (line, column) = location(bytes, position);
    ParseError {
        message: format!("{message}: line {line} column {column} (char {position})"),
    }
}

struct Parser<'a> {
    bytes: &'a [u8],
    index: usize,
}

impl<'a> Parser<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, index: 0 }
    }

    fn error(&self, position: usize, message: &str) -> ParseError {
        error_at(self.bytes, position, message)
    }

    fn skip_whitespace(&mut self) {
        while let Some(byte) = self.bytes.get(self.index) {
            if matches!(*byte, b' ' | b'\t' | b'\n' | b'\r') {
                self.index += 1;
            } else {
                break;
            }
        }
    }

    fn parse_value(&mut self) -> Result<Json, ParseError> {
        self.skip_whitespace();
        let Some(byte) = self.bytes.get(self.index).copied() else {
            return Err(self.error(self.index, "unexpected end of data"));
        };
        match byte {
            b'n' => {
                self.parse_literal(b"null", "null")?;
                Ok(Json::Null)
            }
            b't' => {
                self.parse_literal(b"true", "true")?;
                Ok(Json::Bool(true))
            }
            b'f' => {
                self.parse_literal(b"false", "false")?;
                Ok(Json::Bool(false))
            }
            b'"' => Ok(Json::Str(self.parse_string()?)),
            b'[' => self.parse_array(),
            b'{' => self.parse_object(),
            b'-' | b'0'..=b'9' => self.parse_number(),
            _ => Err(self.error(self.index, "unexpected character, expected a JSON value")),
        }
    }

    fn parse_literal(&mut self, literal: &[u8], name: &str) -> Result<(), ParseError> {
        let start = self.index;
        if self.bytes.len() < start + literal.len()
            || &self.bytes[start..start + literal.len()] != literal
        {
            return Err(self.error(start, &format!("invalid literal, expected '{name}'")));
        }
        self.index += literal.len();
        Ok(())
    }

    fn parse_array(&mut self) -> Result<Json, ParseError> {
        self.index += 1; // '['
        let mut items = Vec::new();
        self.skip_whitespace();
        if self.bytes.get(self.index) == Some(&b']') {
            self.index += 1;
            return Ok(Json::Arr(items));
        }
        loop {
            items.push(self.parse_value()?);
            self.skip_whitespace();
            match self.bytes.get(self.index).copied() {
                Some(b',') => {
                    let comma = self.index;
                    self.index += 1;
                    self.skip_whitespace();
                    if self.bytes.get(self.index) == Some(&b']') {
                        return Err(self.error(comma, "trailing comma is not allowed"));
                    }
                }
                Some(b']') => {
                    self.index += 1;
                    return Ok(Json::Arr(items));
                }
                Some(_) => {
                    return Err(self.error(self.index, "unexpected character, expected ',' or ']'"))
                }
                None => return Err(self.error(self.index, "unexpected end of data")),
            }
        }
    }

    fn parse_object(&mut self) -> Result<Json, ParseError> {
        self.index += 1; // '{'
        let mut entries: Vec<(String, Json)> = Vec::new();
        self.skip_whitespace();
        if self.bytes.get(self.index) == Some(&b'}') {
            self.index += 1;
            return Ok(Json::Obj(entries));
        }
        loop {
            self.skip_whitespace();
            if self.bytes.get(self.index) != Some(&b'"') {
                return Err(self.error(self.index, "unexpected character, expected a string key"));
            }
            let key = self.parse_string()?;
            self.skip_whitespace();
            if self.bytes.get(self.index) != Some(&b':') {
                return Err(self.error(self.index, "unexpected character, expected ':'"));
            }
            self.index += 1;
            let value = self.parse_value()?;
            if let Some(existing) = entries.iter_mut().find(|(name, _)| *name == key) {
                existing.1 = value;
            } else {
                entries.push((key, value));
            }
            self.skip_whitespace();
            match self.bytes.get(self.index).copied() {
                Some(b',') => {
                    let comma = self.index;
                    self.index += 1;
                    self.skip_whitespace();
                    if self.bytes.get(self.index) == Some(&b'}') {
                        return Err(self.error(comma, "trailing comma is not allowed"));
                    }
                }
                Some(b'}') => {
                    self.index += 1;
                    return Ok(Json::Obj(entries));
                }
                Some(_) => {
                    return Err(self.error(self.index, "unexpected character, expected ',' or '}'"))
                }
                None => return Err(self.error(self.index, "unexpected end of data")),
            }
        }
    }

    fn parse_string(&mut self) -> Result<String, ParseError> {
        self.index += 1; // opening quote
        let mut out: Vec<u8> = Vec::new();
        loop {
            let Some(byte) = self.bytes.get(self.index).copied() else {
                return Err(self.error(self.index, "unexpected end of data"));
            };
            match byte {
                b'"' => {
                    self.index += 1;
                    return String::from_utf8(out)
                        .map_err(|_| self.error(self.index, "invalid UTF-8 in string"));
                }
                b'\\' => {
                    let escape_start = self.index;
                    self.index += 1;
                    let Some(escape) = self.bytes.get(self.index).copied() else {
                        return Err(self.error(self.index, "unexpected end of data"));
                    };
                    self.index += 1;
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
                            let (first, first_start) = self.parse_hex4()?;
                            let scalar = if (0xd800..=0xdbff).contains(&first) {
                                let save = self.index;
                                if self.bytes.get(self.index) == Some(&b'\\')
                                    && self.bytes.get(self.index + 1) == Some(&b'u')
                                {
                                    self.index += 2;
                                    let (second, _) = self.parse_hex4()?;
                                    if !(0xdc00..=0xdfff).contains(&second) {
                                        return Err(
                                            self.error(first_start, "no low surrogate in string")
                                        );
                                    }
                                    0x10000
                                        + (((first as u32) - 0xd800) << 10)
                                        + ((second as u32) - 0xdc00)
                                } else {
                                    self.index = save;
                                    return Err(
                                        self.error(first_start, "no low surrogate in string")
                                    );
                                }
                            } else if (0xdc00..=0xdfff).contains(&first) {
                                return Err(self.error(first_start, "no low surrogate in string"));
                            } else {
                                first as u32
                            };
                            let character = char::from_u32(scalar).ok_or_else(|| {
                                self.error(escape_start, "invalid unicode escape")
                            })?;
                            let mut buffer = [0u8; 4];
                            out.extend_from_slice(character.encode_utf8(&mut buffer).as_bytes());
                        }
                        _ => {
                            return Err(self.error(escape_start, "invalid escape character"));
                        }
                    }
                }
                0x00..=0x1f => {
                    return Err(self.error(self.index, "unexpected control character in string"));
                }
                _ => {
                    out.push(byte);
                    self.index += 1;
                }
            }
        }
    }

    fn parse_hex4(&mut self) -> Result<(u16, usize), ParseError> {
        let start = self.index;
        if self.index + 4 > self.bytes.len() {
            return Err(self.error(self.index, "unexpected end of data"));
        }
        let mut value = 0u16;
        for offset in 0..4 {
            let byte = self.bytes[self.index + offset];
            let digit = match byte {
                b'0'..=b'9' => (byte - b'0') as u16,
                b'a'..=b'f' => (byte - b'a' + 10) as u16,
                b'A'..=b'F' => (byte - b'A' + 10) as u16,
                _ => return Err(self.error(start, "invalid unicode escape")),
            };
            value = value * 16 + digit;
        }
        self.index += 4;
        Ok((value, start))
    }

    fn parse_number(&mut self) -> Result<Json, ParseError> {
        let start = self.index;
        if self.bytes.get(self.index) == Some(&b'-') {
            self.index += 1;
        }
        let digits_start = self.index;
        while matches!(self.bytes.get(self.index), Some(b'0'..=b'9')) {
            self.index += 1;
        }
        if self.index == digits_start {
            return Err(self.error(start, "no digit after sign"));
        }
        if self.bytes[digits_start] == b'0' && self.index - digits_start > 1 {
            return Err(self.error(start, "number with leading zero is not allowed"));
        }
        if self.bytes.get(self.index) == Some(&b'.') {
            self.index += 1;
            let fraction_start = self.index;
            while matches!(self.bytes.get(self.index), Some(b'0'..=b'9')) {
                self.index += 1;
            }
            if self.index == fraction_start {
                return Err(self.error(self.index, "unexpected end of data"));
            }
        }
        if matches!(self.bytes.get(self.index), Some(b'e' | b'E')) {
            self.index += 1;
            if matches!(self.bytes.get(self.index), Some(b'+' | b'-')) {
                self.index += 1;
            }
            let exponent_start = self.index;
            while matches!(self.bytes.get(self.index), Some(b'0'..=b'9')) {
                self.index += 1;
            }
            if self.index == exponent_start {
                return Err(self.error(self.index, "unexpected end of data"));
            }
        }
        let text =
            std::str::from_utf8(&self.bytes[start..self.index]).expect("number grammar is ASCII");
        // orjson keeps integer tokens in the int range (negative down to
        // i64::MIN, positive up to u64::MAX) and turns every other token into
        // a double; "1e3" is a double because of the exponent marker.
        let is_integer_token = !text.contains(['.', 'e', 'E']);
        if is_integer_token {
            if let Ok(value) = text.parse::<i128>() {
                if value >= i64::MIN as i128 && value <= u64::MAX as i128 {
                    return Ok(Json::Int(value));
                }
            }
        }
        let value: f64 = text
            .parse()
            .map_err(|_| self.error(start, "invalid number"))?;
        if !value.is_finite() {
            return Err(self.error(start, "number is infinity when parsed as double"));
        }
        Ok(Json::Num(value))
    }
}

pub fn parse(bytes: &[u8]) -> Result<Json, ParseError> {
    if bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
        return Err(error_at(
            bytes,
            0,
            "UTF-8 byte order mark (BOM) is not supported",
        ));
    }
    let mut parser = Parser::new(bytes);
    parser.skip_whitespace();
    if parser.index == bytes.len() {
        return Err(error_at(bytes, 0, "Input is a zero-length, empty document"));
    }
    let value = parser.parse_value()?;
    parser.skip_whitespace();
    if parser.index != bytes.len() {
        return Err(parser.error(parser.index, "unexpected content after document"));
    }
    Ok(value)
}

pub fn dump(value: &Json) -> String {
    let mut out = String::new();
    dump_into(value, &mut out);
    out
}

fn dump_into(value: &Json, out: &mut String) {
    match value {
        Json::Null => out.push_str("null"),
        Json::Bool(true) => out.push_str("true"),
        Json::Bool(false) => out.push_str("false"),
        Json::Int(number) => out.push_str(&number.to_string()),
        Json::Num(number) => out.push_str(&orjson_float(*number)),
        Json::Str(text) => dump_string(text, out),
        Json::Arr(items) => {
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                dump_into(item, out);
            }
            out.push(']');
        }
        Json::Obj(entries) => {
            out.push('{');
            for (index, (name, item)) in entries.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                dump_string(name, out);
                out.push(':');
                dump_into(item, out);
            }
            out.push('}');
        }
    }
}

fn dump_string(text: &str, out: &mut String) {
    out.push('"');
    for character in text.chars() {
        match character {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{00}'..='\u{1f}' => {
                out.push_str(&format!("\\u{:04x}", character as u32));
            }
            _ => out.push(character),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_order_and_duplicate_keys() {
        let value = parse(br#"{"a":1,"b":2,"a":3}"#).unwrap();
        assert_eq!(dump(&value), r#"{"a":3,"b":2}"#);
    }

    #[test]
    fn rejects_non_json_literals() {
        assert!(parse(b"NaN").is_err());
        assert!(parse(b"{\"a\":1,}").is_err());
        assert!(parse(b"{\"a\":1} x").is_err());
    }

    #[test]
    fn integer_tokens_stay_integers() {
        // Probed against orjson 3.12: int keeps its kind, a fractional or
        // exponent token becomes a double, -0 folds into 0, and the accepted
        // int range is i64::MIN ..= u64::MAX.
        let cases: &[(&[u8], &str)] = &[
            (b"3", "3"),
            (b"3.0", "3.0"),
            (b"-0", "0"),
            (b"1e3", "1000.0"),
            (b"-9223372036854775808", "-9223372036854775808"),
            (b"9223372036854775808", "9223372036854775808"),
            (b"18446744073709551616", "1.8446744073709552e+19"),
            (b"-9223372036854775809", "-9.223372036854776e+18"),
        ];
        for (input, expected) in cases {
            assert_eq!(&dump(&parse(input).unwrap()), expected);
        }
        let huge = [b'9'; 400];
        let error = parse(&huge).unwrap_err().to_string();
        assert_eq!(
            error,
            "number is infinity when parsed as double: line 1 column 1 (char 0)"
        );
    }

    #[test]
    fn dump_escapes_like_orjson() {
        let value = Json::Obj(vec![
            ("s".to_string(), Json::Str("a\tb\u{1}\"\\/é".to_string())),
            ("f".to_string(), Json::Num(1e-5)),
        ]);
        assert_eq!(
            dump(&value),
            "{\"s\":\"a\\tb\\u0001\\\"\\\\/é\",\"f\":0.00001}"
        );
    }
}
