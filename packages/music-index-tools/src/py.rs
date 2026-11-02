//! Python-compatible scalar formatting.
//!
//! Cache keys and `meta.json` values are derived from Python's `repr`, so
//! floats must be printed exactly the way CPython does it (shortest round-trip
//! repr, `.0` for integral values, scientific notation for very large/small
//! magnitudes) rather than the way Rust's `Display`/`Debug` happen to print.

/// `repr(x)` for a float, matching CPython's `float_repr`.
pub fn float_repr(x: f64) -> String {
    if x.is_nan() {
        return "nan".to_string();
    }
    if x.is_infinite() {
        return if x.is_sign_negative() { "-inf" } else { "inf" }.to_string();
    }
    if x == 0.0 {
        return if x.is_sign_negative() { "-0.0" } else { "0.0" }.to_string();
    }

    let negative = x.is_sign_negative();
    let magnitude = if negative { -x } else { x };
    // `{:e}` without a precision prints the shortest mantissa that
    // round-trips, which is what CPython's repr uses as well.
    let scientific = format!("{magnitude:e}");
    let (mantissa, exponent) = scientific
        .split_once('e')
        .expect("LowerExp always writes an exponent");
    let exponent: i32 = exponent
        .parse()
        .expect("LowerExp writes an integer exponent");
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    // Number of digits before the decimal point in fixed notation.
    let decpt = exponent + 1;

    let mut out = String::new();
    if negative {
        out.push('-');
    }
    if decpt <= -4 || decpt > 16 {
        // Scientific notation: d[.ddd]e±XX, exponent padded to two digits.
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        if decpt - 1 >= 0 {
            out.push('+');
        } else {
            out.push('-');
        }
        let exponent = (decpt - 1).abs();
        if exponent < 10 {
            out.push('0');
        }
        out.push_str(&exponent.to_string());
    } else if decpt <= 0 {
        out.push_str("0.");
        for _ in 0..(-decpt) {
            out.push('0');
        }
        out.push_str(&digits);
    } else {
        let point = decpt as usize;
        if point >= digits.len() {
            out.push_str(&digits);
            for _ in 0..(point - digits.len()) {
                out.push('0');
            }
            out.push_str(".0");
        } else {
            out.push_str(&digits[..point]);
            out.push('.');
            out.push_str(&digits[point..]);
        }
    }
    out
}

/// `repr(s)` for a string, close enough to CPython for model ids and paths.
///
/// CPython prefers single quotes, switches to double quotes when the string
/// holds a single quote but no double quote, and escapes control characters as
/// `\xNN`/`\uNNNN`. Non-ASCII printable characters are kept verbatim (CPython
/// escapes a few non-printable Unicode categories we do not model).
pub fn str_repr(s: &str) -> String {
    let has_single = s.contains('\'');
    let has_double = s.contains('"');
    let quote = if has_single && !has_double { '"' } else { '\'' };
    let mut out = String::with_capacity(s.len() + 2);
    out.push(quote);
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c if c.is_control() => {
                let code = c as u32;
                if code <= 0xff {
                    out.push_str(&format!("\\x{code:02x}"));
                } else if code <= 0xffff {
                    out.push_str(&format!("\\u{code:04x}"));
                } else {
                    out.push_str(&format!("\\U{code:08x}"));
                }
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

/// `("%g" % x)` with C's default precision of 6 significant digits.
///
/// Used by the warnings and `--adopt-legacy` notice, which print
/// `window_seconds` with `:g` in the Python payload.
pub fn format_g6(x: f64) -> String {
    if x.is_nan() {
        return "nan".to_string();
    }
    if x.is_infinite() {
        return if x < 0.0 { "-inf" } else { "inf" }.to_string();
    }
    if x == 0.0 {
        return "0".to_string();
    }
    let negative = x < 0.0;
    let magnitude = x.abs();
    // Round to six significant digits first, then decide the style from the
    // (possibly bumped) exponent, exactly like printf("%g").
    let scientific = format!("{magnitude:.5e}");
    let (mantissa, exponent) = scientific
        .split_once('e')
        .expect("LowerExp always writes an exponent");
    let exponent: i32 = exponent
        .parse()
        .expect("LowerExp writes an integer exponent");
    let mut digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    while digits.len() > 1 && digits.ends_with('0') {
        digits.pop();
    }

    let mut out = String::new();
    if negative {
        out.push('-');
    }
    if exponent < -4 || exponent >= 6 {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        out.push(if exponent >= 0 { '+' } else { '-' });
        let exponent = exponent.abs();
        if exponent < 10 {
            out.push('0');
        }
        out.push_str(&exponent.to_string());
    } else if exponent < 0 {
        out.push_str("0.");
        for _ in 0..(-exponent - 1) {
            out.push('0');
        }
        out.push_str(&digits);
    } else {
        let point = (exponent + 1) as usize;
        if point >= digits.len() {
            out.push_str(&digits);
            for _ in 0..(point - digits.len()) {
                out.push('0');
            }
        } else {
            out.push_str(&digits[..point]);
            out.push('.');
            out.push_str(&digits[point..]);
        }
    }
    out
}

/// Python's `round(x, digits)` for the score values printed by `--json`.
///
/// Python rounds the exact binary value to `digits` decimal places and returns
/// the nearest float, which is what formatting to that many decimals and
/// parsing back does. Ties cannot occur at four decimals (1e-4 is not a
/// dyadic fraction), so correct rounding is unambiguous.
pub fn round_to(x: f64, digits: usize) -> f64 {
    if !x.is_finite() || x.abs() >= 1e16 {
        return x;
    }
    format!("{x:.digits$}").parse::<f64>().unwrap_or(x)
}

/// `float(s)` with the spellings Python accepts but `str::parse` does not.
pub fn parse_float(s: &str) -> Option<f64> {
    let trimmed = s.trim();
    match trimmed.to_ascii_lowercase().as_str() {
        "inf" | "+inf" | "infinity" | "+infinity" => return Some(f64::INFINITY),
        "-inf" | "-infinity" => return Some(f64::NEG_INFINITY),
        "nan" | "+nan" | "-nan" => return Some(f64::NAN),
        _ => {}
    }
    trimmed.parse::<f64>().ok()
}

/// `str(Path)` for a path; the Python payloads operate on UTF-8 text paths.
pub fn path_str(path: &std::path::Path) -> String {
    path.to_string_lossy().into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn float_repr_matches_cpython() {
        let cases = [
            (1e15, "1000000000000000.0"),
            (1e16, "1e+16"),
            (9999999999999998.0, "9999999999999998.0"),
            (1234567890123456.8, "1234567890123456.8"),
            (0.0001, "0.0001"),
            (0.00001, "1e-05"),
            (10.0, "10.0"),
            (7.5, "7.5"),
            (1.5, "1.5"),
            (0.1, "0.1"),
            (100.0, "100.0"),
            (5e-324, "5e-324"),
            (f64::MAX, "1.7976931348623157e+308"),
            (-0.0, "-0.0"),
            (3.0, "3.0"),
            (0.0, "0.0"),
        ];
        for (value, expected) in cases {
            assert_eq!(float_repr(value), expected, "repr({value})");
        }
    }

    #[test]
    fn tuple_repr_matches_cpython() {
        // repr(("stub/model", -2, 10.0, 3))
        assert_eq!(
            format!(
                "({}, {}, {}, {})",
                str_repr("stub/model"),
                -2,
                float_repr(10.0),
                3
            ),
            "('stub/model', -2, 10.0, 3)"
        );
        // repr(('a\'b"c', 3, 0.1, 7))
        assert_eq!(
            format!(
                "({}, {}, {}, {})",
                str_repr("a'b\"c"),
                3,
                float_repr(0.1),
                7
            ),
            "('a\\'b\"c', 3, 0.1, 7)"
        );
    }

    #[test]
    fn percent_g_matches_cpython() {
        let cases = [
            (10.0, "10"),
            (7.5, "7.5"),
            (0.1, "0.1"),
            (1e-5, "1e-05"),
            (1e6, "1e+06"),
            (1234567.0, "1.23457e+06"),
            (0.000123456789, "0.000123457"),
            (5.0, "5"),
            (0.0, "0"),
            (1.0, "1"),
            (0.123456, "0.123456"),
            (123456789.0, "1.23457e+08"),
            (1e-7, "1e-07"),
            (999999.9, "1e+06"),
            (0.0001, "0.0001"),
            (123456.789, "123457"),
        ];
        for (value, expected) in cases {
            assert_eq!(format_g6(value), expected, "%g of {value}");
        }
    }

    #[test]
    fn round_and_repr_match_cpython() {
        let cases = [
            (0.99999994, "1.0"),
            (-0.0, "-0.0"),
            (1.0, "1.0"),
            (0.12345, "0.1235"),
            (0.000049999999, "0.0"),
            (-0.00005, "-0.0001"),
            (0.123456789, "0.1235"),
        ];
        for (value, expected) in cases {
            assert_eq!(float_repr(round_to(value, 4)), expected);
        }
    }

    #[test]
    fn parse_float_accepts_python_spellings() {
        assert_eq!(parse_float("10"), Some(10.0));
        assert_eq!(parse_float(" 1e-3 "), Some(0.001));
        assert!(parse_float("inf").unwrap().is_infinite());
        assert!(parse_float("nan").unwrap().is_nan());
        assert_eq!(parse_float("1,5"), None);
    }
}
