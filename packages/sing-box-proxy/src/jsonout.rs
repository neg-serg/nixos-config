//! Serialise a `serde_json::Value` exactly like python's
//! `json.dump(value, f, indent=2)` with the default `ensure_ascii=True`.
//!
//! python puts every array/object element on its own line, indents nested
//! levels by two spaces, uses `", "`-free separators when indented
//! (`separators=(",", ": ")`), prints `[]`/`{}` for empty containers, escapes
//! every non-ASCII character as `\uXXXX` (surrogate pairs above U+FFFF) and
//! never writes a trailing newline.
//!
//! Only numbers that the generator can produce are handled precisely: all
//! config numbers are integers (ports, ids, tolerance). A float fallback is
//! present for completeness but not exercised by the fixtures.

use serde_json::Value;

pub fn to_python_json(value: &Value) -> String {
    let mut out = String::new();
    write_value(&mut out, value, 0);
    out
}

fn write_indent(out: &mut String, depth: usize) {
    for _ in 0..depth {
        out.push_str("  ");
    }
}

fn write_value(out: &mut String, value: &Value, depth: usize) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Number(number) => {
            if let Some(n) = number.as_i64() {
                out.push_str(&n.to_string());
            } else if let Some(n) = number.as_u64() {
                out.push_str(&n.to_string());
            } else if let Some(n) = number.as_f64() {
                // python repr() of a float: keep a ".0" for integral values.
                if n.is_finite() && n.fract() == 0.0 {
                    out.push_str(&format!("{n:.1}"));
                } else {
                    out.push_str(&n.to_string());
                }
            } else {
                out.push_str("null");
            }
        }
        Value::String(text) => write_string(out, text),
        Value::Array(items) => {
            out.push('[');
            if !items.is_empty() {
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    out.push('\n');
                    write_indent(out, depth + 1);
                    write_value(out, item, depth + 1);
                }
                out.push('\n');
                write_indent(out, depth);
            }
            out.push(']');
        }
        Value::Object(map) => {
            out.push('{');
            if !map.is_empty() {
                for (i, (key, item)) in map.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    out.push('\n');
                    write_indent(out, depth + 1);
                    write_string(out, key);
                    out.push_str(": ");
                    write_value(out, item, depth + 1);
                }
                out.push('\n');
                write_indent(out, depth);
            }
            out.push('}');
        }
    }
}

fn write_string(out: &mut String, text: &str) {
    out.push('"');
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch if (ch as u32) > 0x7f => {
                let cp = ch as u32;
                if cp <= 0xffff {
                    out.push_str(&format!("\\u{cp:04x}"));
                } else {
                    let cp = cp - 0x1_0000;
                    let high = 0xd800 + (cp >> 10);
                    let low = 0xdc00 + (cp & 0x3ff);
                    out.push_str(&format!("\\u{high:04x}\\u{low:04x}"));
                }
            }
            ch => out.push(ch),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn empty_containers_match_python() {
        assert_eq!(to_python_json(&json!({})), "{}");
        assert_eq!(to_python_json(&json!([])), "[]");
        assert_eq!(
            to_python_json(&json!({"a": [], "b": {}})),
            "{\n  \"a\": [],\n  \"b\": {}\n}"
        );
    }

    #[test]
    fn nested_format_matches_python() {
        let value = json!({"a": 1, "b": [true, null, "x"]});
        assert_eq!(
            to_python_json(&value),
            "{\n  \"a\": 1,\n  \"b\": [\n    true,\n    null,\n    \"x\"\n  ]\n}"
        );
    }

    #[test]
    fn ensure_ascii_escapes_match_python() {
        let value = json!({"s": "päss 😀 \n\t\u{1}"});
        assert_eq!(
            to_python_json(&value),
            "{\n  \"s\": \"p\\u00e4ss \\ud83d\\ude00 \\n\\t\\u0001\"\n}"
        );
    }
}
