//! Small JSON helpers shared by the protocol and the payload builder.
//!
//! The shell built its lines with `printf` plus jq's compact output; a JSON
//! string literal here must have the same bytes jq produced, which is what
//! `serde_json::to_string` gives for a `&str` (quote, backslash and control
//! escapes only, raw UTF-8 for everything else).

/// A JSON string literal, exactly as jq writes it.
pub fn string(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn string_literals_match_jq() {
        assert_eq!(string("calendar"), "\"calendar\"");
        assert_eq!(string(""), "\"\"");
        assert_eq!(string("a\"b\\c"), "\"a\\\"b\\\\c\"");
        assert_eq!(string("line\nbreak"), "\"line\\nbreak\"");
        assert_eq!(string("Zürich"), "\"Zürich\"");
        assert_eq!(string("§7"), "\"§7\"");
    }
}
