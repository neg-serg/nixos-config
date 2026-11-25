//! Float formatting used by the Python port.
//!
//! `music-highlevel` prints scores through Python's `format(x, ".3f")`, values
//! through `str(float)`, and (because `orjson` is importable in the system
//! Python) the JSON payload through `orjson.dumps`. Those three formatters do
//! not agree on exponent thresholds, so each one is implemented explicitly
//! from the shortest round-trip digits Rust already produces.

/// Shortest round-trip decimal digits and the decimal exponent of the value:
/// digits form `d[0].d[1..] * 10^exp10`.
fn shortest_digits(value: f64) -> (Vec<u8>, i32) {
    let formatted = format!("{:e}", value.abs());
    let (mantissa, exponent) = formatted
        .split_once('e')
        .expect("LowerExp always contains an exponent");
    let digits: Vec<u8> = mantissa.bytes().filter(|byte| *byte != b'.').collect();
    let exponent: i32 = exponent.parse().expect("integer exponent");
    (digits, exponent)
}

fn decimal_from_digits(digits: &[u8], exponent: i32) -> Vec<u8> {
    let mut out = Vec::new();
    if exponent >= 0 {
        let integer_len = exponent as usize + 1;
        if digits.len() <= integer_len {
            out.extend_from_slice(digits);
            out.extend(std::iter::repeat_n(b'0', integer_len - digits.len()));
            out.extend_from_slice(b".0");
        } else {
            out.extend_from_slice(&digits[..integer_len]);
            out.push(b'.');
            out.extend_from_slice(&digits[integer_len..]);
        }
    } else {
        out.extend_from_slice(b"0.");
        out.extend(std::iter::repeat_n(b'0', (-exponent - 1) as usize));
        out.extend_from_slice(digits);
    }
    out
}

fn scientific_from_digits(digits: &[u8], exponent: i32, padded_exponent: bool) -> Vec<u8> {
    let mut out = Vec::new();
    out.push(digits[0]);
    if digits.len() > 1 {
        out.push(b'.');
        out.extend_from_slice(&digits[1..]);
    }
    out.push(b'e');
    if exponent >= 0 {
        out.push(b'+');
    } else {
        out.push(b'-');
    }
    let magnitude = exponent.unsigned_abs();
    if padded_exponent {
        if magnitude < 10 {
            out.push(b'0');
        }
        out.extend_from_slice(magnitude.to_string().as_bytes());
    } else {
        out.extend_from_slice(magnitude.to_string().as_bytes());
    }
    out
}

/// `orjson.dumps(float)`: fixed notation for `1e-5 <= |x| < 1e16`, compact
/// scientific notation outside that range, and always a fractional part in
/// fixed notation (`1.0`, not `1`).
pub fn orjson_float(value: f64) -> String {
    if value.is_nan() {
        return "null".to_string();
    }
    if value.is_infinite() {
        return if value.is_sign_negative() {
            "-1e999".to_string()
        } else {
            "1e999".to_string()
        };
    }
    let negative = value.is_sign_negative();
    if value == 0.0 {
        return if negative { "-0.0" } else { "0.0" }.to_string();
    }
    let (digits, exponent) = shortest_digits(value);
    let mut out = Vec::new();
    if negative {
        out.push(b'-');
    }
    if (-5..16).contains(&exponent) {
        out.extend_from_slice(&decimal_from_digits(&digits, exponent));
    } else {
        out.extend_from_slice(&scientific_from_digits(&digits, exponent, false));
    }
    String::from_utf8(out).expect("ASCII digits")
}

/// Python `repr(float)` / `str(float)`.
pub fn python_float_repr(value: f64) -> String {
    if value.is_nan() {
        return "nan".to_string();
    }
    if value.is_infinite() {
        return if value.is_sign_negative() {
            "-inf".to_string()
        } else {
            "inf".to_string()
        };
    }
    let negative = value.is_sign_negative();
    if value == 0.0 {
        return if negative { "-0.0" } else { "0.0" }.to_string();
    }
    let (digits, exponent) = shortest_digits(value);
    let mut out = Vec::new();
    if negative {
        out.push(b'-');
    }
    if (-4..16).contains(&exponent) {
        out.extend_from_slice(&decimal_from_digits(&digits, exponent));
    } else {
        out.extend_from_slice(&scientific_from_digits(&digits, exponent, true));
    }
    String::from_utf8(out).expect("ASCII digits")
}

/// Python `format(float, ".3f")`.
pub fn python_fixed3(value: f64) -> String {
    if value.is_nan() {
        return "nan".to_string();
    }
    if value.is_infinite() {
        return if value.is_sign_negative() {
            "-inf".to_string()
        } else {
            "inf".to_string()
        };
    }
    format!("{value:.3}")
}
