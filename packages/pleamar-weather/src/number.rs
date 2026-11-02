//! The number grammar the shell validated and the literal rendering jq gave
//! the numbers it interpolated into a payload.
//!
//! Two different grammars matter here:
//!
//! - `is_number` is the shell's `awk` check for `--lat`/`--lon`
//!   (`^[+-]?[0-9]+(\.[0-9]+)?$`): a leading sign and leading zeroes are
//!   accepted, an exponent or a bare `.5` is not.
//! - jq's `--argjson` accepts any JSON number, and jq 1.8 keeps the literal as
//!   written when it already is one (`59.938630` stays `59.938630`), while a
//!   non-JSON spelling is normalised by decNumber (`+003.50` becomes `3.50`).
//!
//! The payload builder and the cache writer feed every interpolated number
//! through `json_literal`, so the bytes match what jq produced.

/// The shell's `is_uint`: a non-empty run of ASCII digits.
pub fn is_uint(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

/// The shell's `is_number` (the awk regex): an optional sign, at least one
/// digit, and an optional fractional part that must have digits after the dot.
pub fn is_number(value: &str) -> bool {
    let bytes = value.as_bytes();
    let mut index = 0;
    if index < bytes.len() && (bytes[index] == b'+' || bytes[index] == b'-') {
        index += 1;
    }
    let integer = index;
    while index < bytes.len() && bytes[index].is_ascii_digit() {
        index += 1;
    }
    if index == integer {
        return false;
    }
    if index < bytes.len() && bytes[index] == b'.' {
        index += 1;
        let fraction = index;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            index += 1;
        }
        if index == fraction {
            return false;
        }
    }
    index == bytes.len()
}

/// A JSON number literal (`-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`).
pub fn is_json_number(value: &str) -> bool {
    let bytes = value.as_bytes();
    let mut index = 0;
    if index < bytes.len() && bytes[index] == b'-' {
        index += 1;
    }
    if index >= bytes.len() {
        return false;
    }
    if bytes[index] == b'0' {
        index += 1;
    } else if bytes[index].is_ascii_digit() {
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            index += 1;
        }
    } else {
        return false;
    }
    if index < bytes.len() && bytes[index] == b'.' {
        index += 1;
        let fraction = index;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            index += 1;
        }
        if index == fraction {
            return false;
        }
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
            return false;
        }
    }
    index == bytes.len()
}

/// Render a number the way `jq -cn --argjson name "$value"` then printed it:
/// a JSON literal is preserved verbatim (jq 1.8 decNumber literal
/// preservation), otherwise the sign and leading zeroes are normalised.
///
/// Only values accepted by `is_number` reach this with a non-JSON spelling
/// (that grammar is a superset of the JSON one apart from the leading `+` and
/// leading zeroes), so the normalisation below covers every reachable case.
pub fn json_literal(value: &str) -> String {
    if is_json_number(value) {
        return value.to_string();
    }
    if !is_number(value) {
        return value.to_string();
    }
    let (negative, unsigned) = match value.as_bytes().first() {
        Some(b'+') => (false, &value[1..]),
        Some(b'-') => (true, &value[1..]),
        _ => (false, value),
    };
    let (integer, fraction) = match unsigned.find('.') {
        Some(dot) => (&unsigned[..dot], Some(&unsigned[dot..])),
        None => (unsigned, None),
    };
    let trimmed = integer.trim_start_matches('0');
    let integer = if trimmed.is_empty() { "0" } else { trimmed };
    let mut rendered = String::new();
    if negative {
        rendered.push('-');
    }
    rendered.push_str(integer);
    if let Some(fraction) = fraction {
        rendered.push_str(fraction);
    }
    rendered
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uint_matches_the_shell() {
        for value in ["0", "1", "300", "3600000"] {
            assert!(is_uint(value), "{value} should be an unsigned integer");
        }
        for value in ["", "-1", "+1", "1.0", " 1", "1 ", "x"] {
            assert!(!is_uint(value), "{value} should not be an unsigned integer");
        }
    }

    #[test]
    fn number_matches_the_shell_awk_regex() {
        for value in ["0", "5", "+5", "-5", "5.0", "+59.938", "-0.0", "003"] {
            assert!(is_number(value), "{value} should be a number");
        }
        for value in ["", ".5", "5.", "1e3", "1.0e3", " 5", "5 ", "abc", "+", "-"] {
            assert!(!is_number(value), "{value} should not be a number");
        }
    }

    #[test]
    fn json_number_grammar() {
        for value in ["0", "-0", "12", "-12", "1.5", "1e3", "1E+3", "0.5e-2"] {
            assert!(is_json_number(value), "{value} is a JSON number");
        }
        for value in ["", "+1", "01", "1.", ".5", "--1", "1.0.0", "1e", "1e+"] {
            assert!(!is_json_number(value), "{value} is not a JSON number");
        }
    }

    #[test]
    fn json_literal_keeps_what_jq_keeps() {
        // Literal preservation: jq 1.8 prints these exactly as received.
        assert_eq!(json_literal("59.93863"), "59.93863");
        assert_eq!(json_literal("59.938630"), "59.938630");
        assert_eq!(json_literal("3.40"), "3.40");
        assert_eq!(json_literal("7.0"), "7.0");
        assert_eq!(json_literal("-0"), "-0");
        assert_eq!(json_literal("1013"), "1013");
        // Normalisation of the spellings jq's decNumber rewrote.
        assert_eq!(json_literal("+3"), "3");
        assert_eq!(json_literal("+3.50"), "3.50");
        assert_eq!(json_literal("003"), "3");
        assert_eq!(json_literal("00.50"), "0.50");
        assert_eq!(json_literal("-003"), "-3");
        assert_eq!(json_literal("-000"), "-0");
        assert_eq!(json_literal("+0"), "0");
    }
}
