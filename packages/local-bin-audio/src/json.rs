//! The slice of JSON the ports need.
//!
//! `synth` used to pipe `hyprctl clients -j` through
//! `jq -r '.[] | select(.class|test($c)) | select($t=="" or (.title|contains($t))) | .address'`.
//! The port reads the same array directly: a small recursive-descent parser
//! keeps the selection native without a regex or serialization crate.

pub enum Value {
    Null,
    Bool(bool),
    Number(Vec<u8>),
    String(Vec<u8>),
    Array(Vec<Value>),
    Object(Vec<(Vec<u8>, Value)>),
}

impl Value {
    pub fn get(&self, key: &[u8]) -> Option<&Value> {
        match self {
            Value::Object(entries) => entries
                .iter()
                .find(|(name, _)| name == key)
                .map(|(_, value)| value),
            _ => None,
        }
    }

    pub fn as_bytes(&self) -> Option<&[u8]> {
        match self {
            Value::String(value) => Some(value),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(values) => Some(values),
            _ => None,
        }
    }
}

/// Parse one complete JSON value; trailing whitespace is allowed, any other
/// trailing byte makes the parse fail (like `jq` reporting a parse error).
pub fn parse(bytes: &[u8]) -> Option<Value> {
    let mut parser = Parser { bytes, index: 0 };
    let value = parser.value()?;
    parser.skip_whitespace();
    if parser.index == bytes.len() {
        Some(value)
    } else {
        None
    }
}

struct Parser<'a> {
    bytes: &'a [u8],
    index: usize,
}

impl<'a> Parser<'a> {
    fn skip_whitespace(&mut self) {
        while self.index < self.bytes.len()
            && matches!(self.bytes[self.index], b' ' | b'\t' | b'\n' | b'\r')
        {
            self.index += 1;
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.index).copied()
    }

    fn expect(&mut self, byte: u8) -> Option<()> {
        if self.peek() == Some(byte) {
            self.index += 1;
            Some(())
        } else {
            None
        }
    }

    fn value(&mut self) -> Option<Value> {
        self.skip_whitespace();
        match self.peek()? {
            b'{' => self.object(),
            b'[' => self.array(),
            b'"' => self.string().map(Value::String),
            b't' => self.literal(b"true", Value::Bool(true)),
            b'f' => self.literal(b"false", Value::Bool(false)),
            b'n' => self.literal(b"null", Value::Null),
            b'-' | b'0'..=b'9' => self.number(),
            _ => None,
        }
    }

    fn literal(&mut self, text: &[u8], value: Value) -> Option<Value> {
        if self.bytes[self.index..].starts_with(text) {
            self.index += text.len();
            Some(value)
        } else {
            None
        }
    }

    fn number(&mut self) -> Option<Value> {
        let start = self.index;
        if self.peek() == Some(b'-') {
            self.index += 1;
        }
        let digits_start = self.index;
        while matches!(self.peek(), Some(byte) if byte.is_ascii_digit()) {
            self.index += 1;
        }
        if self.index == digits_start {
            return None;
        }
        if self.peek() == Some(b'.') {
            self.index += 1;
            let fraction_start = self.index;
            while matches!(self.peek(), Some(byte) if byte.is_ascii_digit()) {
                self.index += 1;
            }
            if self.index == fraction_start {
                return None;
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.index += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.index += 1;
            }
            let exponent_start = self.index;
            while matches!(self.peek(), Some(byte) if byte.is_ascii_digit()) {
                self.index += 1;
            }
            if self.index == exponent_start {
                return None;
            }
        }
        Some(Value::Number(self.bytes[start..self.index].to_vec()))
    }

    fn string(&mut self) -> Option<Vec<u8>> {
        self.expect(b'"')?;
        let mut result = Vec::new();
        loop {
            let byte = self.peek()?;
            match byte {
                b'"' => {
                    self.index += 1;
                    return Some(result);
                }
                b'\\' => {
                    self.index += 1;
                    let escape = self.peek()?;
                    self.index += 1;
                    match escape {
                        b'"' => result.push(b'"'),
                        b'\\' => result.push(b'\\'),
                        b'/' => result.push(b'/'),
                        b'b' => result.push(0x08),
                        b'f' => result.push(0x0c),
                        b'n' => result.push(b'\n'),
                        b'r' => result.push(b'\r'),
                        b't' => result.push(b'\t'),
                        b'u' => {
                            let code = self.hex4()?;
                            push_char(&mut result, code);
                        }
                        _ => return None,
                    }
                }
                _ => {
                    // Inside a string, any byte that is not a quote, a
                    // backslash or a control character is literal UTF-8.
                    self.index += 1;
                    result.push(byte);
                }
            }
        }
    }

    fn hex4(&mut self) -> Option<u32> {
        let mut value = 0u32;
        for _ in 0..4 {
            let byte = self.peek()?;
            let digit = (byte as char).to_digit(16)?;
            value = value * 16 + digit;
            self.index += 1;
        }
        Some(value)
    }

    fn array(&mut self) -> Option<Value> {
        self.expect(b'[')?;
        let mut values = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b']') {
            self.index += 1;
            return Some(Value::Array(values));
        }
        loop {
            values.push(self.value()?);
            self.skip_whitespace();
            match self.peek()? {
                b',' => self.index += 1,
                b']' => {
                    self.index += 1;
                    return Some(Value::Array(values));
                }
                _ => return None,
            }
        }
    }

    fn object(&mut self) -> Option<Value> {
        self.expect(b'{')?;
        let mut entries = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b'}') {
            self.index += 1;
            return Some(Value::Object(entries));
        }
        loop {
            self.skip_whitespace();
            let key = self.string()?;
            self.skip_whitespace();
            self.expect(b':')?;
            let value = self.value()?;
            entries.push((key, value));
            self.skip_whitespace();
            match self.peek()? {
                b',' => self.index += 1,
                b'}' => {
                    self.index += 1;
                    return Some(Value::Object(entries));
                }
                _ => return None,
            }
        }
    }
}

/// Encode one `\uXXXX` scalar as UTF-8. Lone surrogates are encoded as the
/// replacement character; `hyprctl` window classes never carry them.
fn push_char(result: &mut Vec<u8>, code: u32) {
    if (0xD800..=0xDFFF).contains(&code) {
        result.push(b'?');
        return;
    }
    match char::from_u32(code) {
        Some(character) => {
            let mut buffer = [0u8; 4];
            result.extend_from_slice(character.encode_utf8(&mut buffer).as_bytes());
        }
        None => result.push(b'?'),
    }
}
