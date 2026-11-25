//! Python-compatible JSON writing.
//!
//! `serde_json` produces the same structure but not the same text: Python's
//! `json.dumps` uses `", "`/`": "` separators by default and keeps non-ASCII
//! verbatim with `ensure_ascii=False`. The payloads' on-disk JSONL and the
//! `--json` output are written by hand here so re-running the port does not
//! rewrite those files with a different byte layout.

/// Append `json.dumps(s)` string content, without the surrounding quotes.
///
/// `ensure_ascii` mirrors Python's flag: `true` is used by `meta.json`
/// (`json.dump(meta, handle, indent=2)` defaults to ASCII escapes), `false` by
/// `tracks.jsonl` and the `--json` output.
pub fn push_json_string(out: &mut String, s: &str, ensure_ascii: bool) {
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c if ensure_ascii && (c as u32) >= 0x80 => {
                let code = c as u32;
                if code <= 0xffff {
                    out.push_str(&format!("\\u{code:04x}"));
                } else {
                    let code = code - 0x10000;
                    let high = 0xd800 + (code >> 10);
                    let low = 0xdc00 + (code & 0x3ff);
                    out.push_str(&format!("\\u{high:04x}\\u{low:04x}"));
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Quote a string the way `json.dumps(s, ensure_ascii=...)` does.
pub fn json_string(s: &str, ensure_ascii: bool) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    push_json_string(&mut out, s, ensure_ascii);
    out
}
