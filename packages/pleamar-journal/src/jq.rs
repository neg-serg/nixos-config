//! The jq program the shell ran, reimplemented value for value.
//!
//! The shell's entry filter was:
//!
//! ```jq
//! [ .[] | {
//!     time: ((.__REALTIME_TIMESTAMP | tonumber? // 0) / 1000000 | strflocaltime("%H:%M")),
//!     service: (._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER // "journal"),
//!     msg: ((.MESSAGE // "") | if type == "array" then join(" ") else tostring end | .[0:120])
//!   } ]
//! ```
//!
//! and `jq -s -c` meant "treat the stream as one array, print it compactly".
//! The details that matter for the bytes are jq 1.8's: `//` treats only null
//! and false as absent; `tostring` renders a number through decNumber (so an
//! input literal keeps its digits, an exponent is normalised); a string slice
//! counts Unicode codepoints; object keys keep their input order.

use serde_json::Value;

/// Parse a stream of JSON values the way `jq -s` does. `None` means the input
/// was not a valid JSON stream: jq exited non-zero, and the shell's
/// `|| echo '[]'` supplied an empty array instead.
pub fn parse_stream(bytes: &[u8]) -> Option<Vec<Value>> {
    let mut values = Vec::new();
    for value in serde_json::Deserializer::from_slice(bytes).into_iter::<Value>() {
        values.push(value.ok()?);
    }
    Some(values)
}

/// jq's truthiness: everything except null and false.
pub fn truthy(value: &Value) -> bool {
    !matches!(value, Value::Null | Value::Bool(false))
}

/// jq's `//`: the left value unless it is null or false.
pub fn either<'a>(left: Option<&'a Value>, right: Option<&'a Value>) -> Option<&'a Value> {
    left.filter(|value| truthy(value))
        .or_else(|| right.filter(|value| truthy(value)))
}

/// `tostring`: a string is itself, everything else is its compact JSON
/// representation (for numbers that is jq's decNumber rendering).
pub fn tostring(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        _ => render_value(value),
    }
}

/// `join(" ")` over the MESSAGE array. jq joins scalars only; a nested array
/// or an object makes the whole filter fail (`None`), which the shell's
/// fallback turned into `entries: []`.
pub fn join_space(values: &[Value]) -> Option<String> {
    let mut parts = Vec::with_capacity(values.len());
    for value in values {
        let part = match value {
            Value::String(text) => text.clone(),
            Value::Number(number) => render_number(&number.to_string()),
            Value::Bool(true) => "true".to_string(),
            Value::Bool(false) => "false".to_string(),
            Value::Null => String::new(),
            Value::Array(_) | Value::Object(_) => return None,
        };
        parts.push(part);
    }
    Some(parts.join(" "))
}

/// `.[0:120]`: codepoints, not bytes (jq's string indexing is by codepoint).
pub fn slice_codepoints(text: &str, count: usize) -> String {
    text.chars().take(count).collect()
}

/// `tonumber?` on the timestamp field, as a number. Anything jq's `tonumber`
/// rejects is the missing value the filter replaced with 0.
pub fn timestamp_seconds(value: Option<&Value>) -> f64 {
    match value {
        Some(Value::Number(number)) => number.to_string().parse::<f64>().unwrap_or(0.0),
        Some(Value::String(text)) => tonumber(text).unwrap_or(0.0),
        // null, booleans, arrays and objects make `tonumber` error; `?`
        // dropped the error and `// 0` supplied zero.
        _ => 0.0,
    }
}

/// jq's `tonumber` grammar: an optional sign, digits with an optional
/// fraction, an optional exponent. Whitespace, hex and a bare sign are
/// rejected; `.5`, `12.` and `+12` are accepted (`tonumber` treats the string
/// like a JSON number plus a leading sign, not like `strtod`).
pub fn tonumber(text: &str) -> Option<f64> {
    let bytes = text.as_bytes();
    let mut index = 0;
    if index < bytes.len() && (bytes[index] == b'+' || bytes[index] == b'-') {
        index += 1;
    }
    let mut digits = 0;
    while index < bytes.len() && bytes[index].is_ascii_digit() {
        index += 1;
        digits += 1;
    }
    if index < bytes.len() && bytes[index] == b'.' {
        index += 1;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            index += 1;
            digits += 1;
        }
    }
    if digits == 0 {
        return None;
    }
    if index < bytes.len() && (bytes[index] == b'e' || bytes[index] == b'E') {
        index += 1;
        if index < bytes.len() && (bytes[index] == b'+' || bytes[index] == b'-') {
            index += 1;
        }
        let exponent = index;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            index += 1;
        }
        if index == exponent {
            return None;
        }
    }
    if index != bytes.len() {
        return None;
    }
    // Rust's parser accepts this grammar except for a mantissa that ends in a
    // dot (`12.`), where appending a zero is exact.
    let mut canonical = String::with_capacity(text.len() + 2);
    canonical.push_str(text);
    if canonical.ends_with('.') {
        canonical.push('0');
    }
    canonical.parse::<f64>().ok()
}

/// Compact JSON bytes exactly as jq prints them.
pub fn render_value(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(true) => "true".to_string(),
        Value::Bool(false) => "false".to_string(),
        Value::Number(number) => render_number(&number.to_string()),
        Value::String(text) => string_literal(text),
        Value::Array(items) => {
            let rendered: Vec<String> = items.iter().map(render_value).collect();
            format!("[{}]", rendered.join(","))
        }
        Value::Object(map) => {
            let rendered: Vec<String> = map
                .iter()
                .map(|(key, value)| format!("{}:{}", string_literal(key), render_value(value)))
                .collect();
            format!("{{{}}}", rendered.join(","))
        }
    }
}

/// A JSON string literal, exactly as jq writes it.
pub fn string_literal(text: &str) -> String {
    serde_json::to_string(text).unwrap_or_else(|_| "\"\"".to_string())
}

/// A number literal as jq 1.8 (decNumber) prints it. The rule decNumber uses
/// is: plain notation when the decimal exponent is <= 0 and the adjusted
/// exponent is at least -6, scientific notation otherwise
/// (`1e20` -> `1E+20`, `1.5e-3` -> `0.0015`, `1.50` -> `1.50`).
fn render_number(literal: &str) -> String {
    let (negative, body) = match literal.strip_prefix('-') {
        Some(body) => (true, body),
        None => (false, literal),
    };
    let (mantissa, exponent) = match body.find(['e', 'E']) {
        Some(index) => (
            &body[..index],
            body[index + 1..].parse::<i64>().unwrap_or(0),
        ),
        None => (body, 0),
    };
    let (integer, fraction) = match mantissa.find('.') {
        Some(index) => (&mantissa[..index], &mantissa[index + 1..]),
        None => (mantissa, ""),
    };

    let mut digits = String::with_capacity(integer.len() + fraction.len());
    digits.push_str(integer);
    digits.push_str(fraction);
    let exponent = exponent - fraction.len() as i64;
    let digits = digits.trim_start_matches('0');
    let digits = if digits.is_empty() { "0" } else { digits };
    let adjusted = exponent + digits.len() as i64 - 1;

    let mut rendered = String::new();
    if negative {
        rendered.push('-');
    }
    if exponent <= 0 && adjusted >= -6 {
        let point = digits.len() as i64 + exponent;
        if point <= 0 {
            rendered.push_str("0.");
            for _ in 0..(-point) {
                rendered.push('0');
            }
            rendered.push_str(digits);
        } else {
            let point = point as usize;
            rendered.push_str(&digits[..point]);
            if point < digits.len() {
                rendered.push('.');
                rendered.push_str(&digits[point..]);
            }
        }
    } else {
        rendered.push_str(&digits[..1]);
        if digits.len() > 1 {
            rendered.push('.');
            rendered.push_str(&digits[1..]);
        }
        if adjusted >= 0 {
            rendered.push_str("E+");
            rendered.push_str(&adjusted.to_string());
        } else {
            rendered.push('E');
            rendered.push_str(&adjusted.to_string());
        }
    }
    rendered
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn number_rendering_matches_jq() {
        // Expected values were produced by jq 1.8.2 with `tostring`.
        for (input, expected) in [
            ("1e20", "1E+20"),
            ("1E2", "1E+2"),
            ("1.50", "1.50"),
            ("1.5e-3", "0.0015"),
            ("10e1", "1.0E+2"),
            ("100e-2", "1.00"),
            ("42", "42"),
            ("0.000001", "0.000001"),
            ("-0.0", "-0.0"),
            ("1.0e+10", "1.0E+10"),
            ("9007199254740993", "9007199254740993"),
            ("0e5", "0E+5"),
            ("0e-7", "0E-7"),
            ("0.00e2", "0"),
            ("0.000000e0", "0.000000"),
            ("-0e5", "-0E+5"),
            ("0.0e10", "0E+9"),
            ("1e-10", "1E-10"),
            ("9.99e-7", "9.99E-7"),
            ("9.99e-6", "0.00000999"),
            ("123.4500", "123.4500"),
        ] {
            assert_eq!(render_number(input), expected, "number {input}");
        }
    }

    #[test]
    fn compact_json_matches_jq() {
        assert_eq!(
            render_value(&json!({"b": 1, "a": [true, null, "x"]})),
            r#"{"b":1,"a":[true,null,"x"]}"#
        );
        assert_eq!(tostring(&json!(1.5)), "1.5");
        // jq preserves the literal it parsed, so 1.50 stays 1.50; building a
        // Value from an f64 already lost that spelling, hence from_str here.
        assert_eq!(
            tostring(&serde_json::from_str::<Value>("1.50").unwrap()),
            "1.50"
        );
        assert_eq!(tostring(&json!("text")), "text");
        assert_eq!(string_literal("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"");
    }

    #[test]
    fn join_uses_the_same_scalar_rendering() {
        let values = serde_json::from_str::<Value>(r#"["a",1,null,true,"b"]"#).unwrap();
        let Value::Array(items) = values else {
            unreachable!()
        };
        assert_eq!(join_space(&items).as_deref(), Some("a 1  true b"));
        let nested: Value = serde_json::from_str(r#"["a",["b"]]"#).unwrap();
        let Value::Array(items) = nested else {
            unreachable!()
        };
        assert_eq!(join_space(&items), None);
    }

    #[test]
    fn slices_count_codepoints() {
        assert_eq!(slice_codepoints("😀😀😀", 2), "😀😀");
        assert_eq!(slice_codepoints("héllo", 2), "hé");
        assert_eq!(slice_codepoints("short", 120), "short");
    }

    #[test]
    fn stream_parsing_follows_jq_s() {
        assert_eq!(parse_stream(b""), Some(vec![]));
        assert_eq!(parse_stream(b"  \n\t"), Some(vec![]));
        assert_eq!(parse_stream(b"{}{}"), Some(vec![json!({}), json!({})]));
        assert_eq!(parse_stream(b"not json"), None);
        assert_eq!(parse_stream(b"{} trailing"), None);
    }

    #[test]
    fn tonumber_accepts_what_jq_accepts() {
        assert_eq!(tonumber("1730000000123456"), Some(1730000000123456.0));
        assert_eq!(tonumber("+12"), Some(12.0));
        assert_eq!(tonumber("12."), Some(12.0));
        assert_eq!(tonumber(".5"), Some(0.5));
        assert_eq!(tonumber("-1e3"), Some(-1000.0));
        for rejected in ["", " 12", "12 ", "1e", "1e+", "0x10", "abc", "+", "."] {
            assert_eq!(tonumber(rejected), None, "string {rejected:?}");
        }
    }

    #[test]
    fn timestamps_fall_back_to_zero_like_the_filter() {
        assert_eq!(timestamp_seconds(None), 0.0);
        assert_eq!(timestamp_seconds(Some(&json!(null))), 0.0);
        assert_eq!(timestamp_seconds(Some(&json!(false))), 0.0);
        assert_eq!(timestamp_seconds(Some(&json!("bogus"))), 0.0);
        assert_eq!(
            timestamp_seconds(Some(&json!("1730000000123456"))),
            1730000000123456.0
        );
        assert_eq!(timestamp_seconds(Some(&json!(5))), 5.0);
    }

    #[test]
    fn either_prefers_the_first_truthy_value() {
        assert_eq!(
            either(Some(&json!("a")), Some(&json!("b"))),
            Some(&json!("a"))
        );
        assert_eq!(
            either(Some(&json!(false)), Some(&json!("b"))),
            Some(&json!("b"))
        );
        assert_eq!(either(Some(&json!(null)), None), None);
    }
}
