//! Small JSON helpers shared by the protocol and the payload builder.
//!
//! The shell built its lines with `printf` plus jq's compact output; a JSON
//! string literal here must have the same bytes jq produced, which is what
//! `serde_json::to_string` gives for a `&str` (quote, backslash and control
//! escapes only, raw UTF-8 for everything else).

use serde_json::value::RawValue;

/// A JSON string literal, exactly as jq writes it.
pub fn string(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string())
}

/// A JSON fragment that has already been validated (a provider value, or
/// output of `number::json_literal`). The fallback is `null`, never a panic:
/// every caller passes a parsed JSON value or a formatted number.
pub fn raw(fragment: &str) -> Box<RawValue> {
    RawValue::from_string(fragment.to_string())
        .unwrap_or_else(|_| RawValue::from_string("null".to_string()).expect("null is valid JSON"))
}

/// Render an optional raw fragment: a missing value was `null` in the jq
/// programs (`.current.foo` on an absent key is null).
pub fn raw_or_null(value: &Option<Box<RawValue>>) -> String {
    match value {
        Some(value) => value.get().to_string(),
        None => "null".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn string_literals_match_jq() {
        assert_eq!(string("weather"), "\"weather\"");
        assert_eq!(string(""), "\"\"");
        assert_eq!(string("Saint Petersburg"), "\"Saint Petersburg\"");
        assert_eq!(string("a\"b\\c"), "\"a\\\"b\\\\c\"");
        assert_eq!(string("line\nbreak"), "\"line\\nbreak\"");
        assert_eq!(string("Zürich"), "\"Zürich\"");
    }

    #[test]
    fn raw_or_null_keeps_the_literal() {
        assert_eq!(raw_or_null(&Some(raw("3.40"))), "3.40");
        assert_eq!(raw_or_null(&Some(raw("null"))), "null");
        assert_eq!(raw_or_null(&None), "null");
    }
}
