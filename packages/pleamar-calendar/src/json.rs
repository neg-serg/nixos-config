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
