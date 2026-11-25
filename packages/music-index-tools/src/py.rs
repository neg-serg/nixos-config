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
