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
