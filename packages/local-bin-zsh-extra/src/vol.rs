//! Rust port of `packages/local-bin/bin/vol`.
//!
//! `vol +DELTA` asks wpctl for the default sink volume, adds the delta and
//! calls `wpctl set-volume`, clamping at 1 and 0. The original `sign` helper
//! prints the sign with `echo`, and zsh's `echo '-'` treats a lone dash as the
//! end-of-options marker and prints an empty line, so a negative delta never
//! reaches `set_volume`: it falls through to the `expected +DELTA or -DELTA`
//! error and exits 2. This port reproduces that observable behaviour (only the
//! `+` path exists).
//!
//! `cut -d: -f2 | tr -d '[:space:]'` and the awk arithmetic/formatting are
//! native; wpctl is still spawned with the original argv.

#![forbid(unsafe_code)]

use std::ffi::OsString;

use local_bin_zsh_extra::{err_line, out_str, raw_args, report_spawn_failure, run, StdioMode};

const USAGE: &str = "\
vol: adjust PipeWire default sink volume via wpctl
Usage: vol [+DELTA|-DELTA]
  Example: vol +0.05 (increase), vol -0.05 (decrease)
";

fn main() {
    let args = raw_args();
    let first = args
        .first()
        .map(|value| value.to_string_lossy())
        .unwrap_or_default();
    if args.is_empty() || first == "-h" || first == "--help" {
        out_str(USAGE);
        return;
    }

    if local_bin_zsh_extra::which_str("wpctl").is_none() {
        err_line("vol: wpctl not found");
    }

    if !first.starts_with('+') {
        // The zsh `sign` function returns an empty string for a leading `-`
        // (`echo '-'` prints only a newline), so even a valid negative delta
        // lands in the `*)` branch of the case statement.
        err_line("vol: expected +DELTA or -DELTA");
        std::process::exit(2);
    }

    let current = read_volume();
    let delta = awk_number(&first);
    let value = awk_number(&current) + delta;
    let formatted = if value >= 1.0 {
        "1".to_string()
    } else if value < 0.0 {
        "0".to_string()
    } else {
        format_g6(value)
    };

    let status = match run(
        "wpctl",
        &[
            OsString::from("set-volume"),
            OsString::from("@DEFAULT_SINK@"),
            OsString::from(formatted),
        ],
        StdioMode::Inherit,
        StdioMode::Inherit,
    ) {
        Ok(status) => status,
        Err(error) => report_spawn_failure("set_volume", "wpctl", &error, StdioMode::Inherit),
    };
    std::process::exit(status);
}

/// `$(wpctl get-volume @DEFAULT_SINK@ | cut -d: -f2 | tr -d '[:space:]')`.
fn read_volume() -> String {
    let output = match local_bin_zsh_extra::capture(
        "wpctl",
        &[
            OsString::from("get-volume"),
            OsString::from("@DEFAULT_SINK@"),
        ],
        StdioMode::Inherit,
    ) {
        Ok(captured) => captured.stdout,
        Err(error) => {
            report_spawn_failure("get_volume_", "wpctl", &error, StdioMode::Inherit);
            return String::new();
        }
    };

    let mut text = String::new();
    for line in output.split(|byte| *byte == b'\n') {
        // `cut -d: -f2` prints the whole line when the delimiter is absent.
        let field = match line.iter().position(|byte| *byte == b':') {
            Some(position) => &line[position + 1..],
            None => line,
        };
        for byte in field {
            if !is_ascii_space(*byte) {
                text.push(*byte as char);
            }
        }
    }
    text
}

fn is_ascii_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

/// awk's numeric conversion: the longest valid numeric prefix, else 0.
fn awk_number(text: &str) -> f64 {
    let bytes = text.as_bytes();
    let mut index = 0;
    while index < bytes.len() && is_ascii_space(bytes[index]) {
        index += 1;
    }
    let start = index;
    if index < bytes.len() && matches!(bytes[index], b'+' | b'-') {
        index += 1;
    }
    let mut digits = 0;
    while index < bytes.len() && bytes[index].is_ascii_digit() {
        index += 1;
        digits += 1;
    }
    if index < bytes.len() && bytes[index] == b'.' {
        index += 1;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            index += 1;
            digits += 1;
        }
    }
    if digits == 0 {
        return 0.0;
    }
    if index < bytes.len() && matches!(bytes[index], b'e' | b'E') {
        let mut exponent = index + 1;
        if exponent < bytes.len() && matches!(bytes[exponent], b'+' | b'-') {
            exponent += 1;
        }
        let mut exponent_digits = 0;
        while exponent < bytes.len() && bytes[exponent].is_ascii_digit() {
            exponent += 1;
            exponent_digits += 1;
        }
        if exponent_digits > 0 {
            index = exponent;
        }
    }
    text[start..index].parse::<f64>().unwrap_or(0.0)
}

/// awk's `print v` with the default `OFMT=%.6g`.
fn format_g6(value: f64) -> String {
    if value == 0.0 {
        return "0".to_string();
    }
    let scientific = format!("{value:.5e}");
    let (mantissa, exponent) = scientific
        .split_once('e')
        .expect("Rust's scientific formatting always has an exponent");
    let exponent: i32 = exponent.parse().expect("a numeric exponent");
    if exponent < -4 || exponent >= 6 {
        let mut mantissa = mantissa
            .trim_end_matches('0')
            .trim_end_matches('.')
            .to_string();
        if mantissa.is_empty() {
            mantissa.push('0');
        }
        format!(
            "{mantissa}e{}{:02}",
            if exponent < 0 { '-' } else { '+' },
            exponent.abs()
        )
    } else {
        let decimals = (5 - exponent).max(0) as usize;
        let mut fixed = format!("{value:.decimals$}");
        if fixed.contains('.') {
            while fixed.ends_with('0') {
                fixed.pop();
            }
            if fixed.ends_with('.') {
                fixed.pop();
            }
        }
        fixed
    }
}

#[cfg(test)]
mod tests {
    use super::{awk_number, format_g6};

    #[test]
    fn awk_numbers_use_the_numeric_prefix() {
        assert_eq!(awk_number("0.50"), 0.5);
        assert_eq!(awk_number(" 0.50"), 0.5);
        assert_eq!(awk_number("0.50[MUTED]"), 0.5);
        assert_eq!(awk_number("+-0.5"), 0.0);
        assert_eq!(awk_number(""), 0.0);
        assert_eq!(awk_number("null"), 0.0);
        assert_eq!(awk_number("1e-3"), 0.001);
        assert_eq!(awk_number("1e"), 1.0);
        assert_eq!(awk_number("0x10"), 0.0);
    }

    #[test]
    fn g6_format_matches_awk() {
        for (value, expected) in [
            (0.55, "0.55"),
            (0.3, "0.3"),
            (0.5, "0.5"),
            (0.0001, "0.0001"),
            (0.00001, "1e-05"),
            (0.123456789, "0.123457"),
            (0.0, "0"),
        ] {
            assert_eq!(format_g6(value), expected, "{value}");
        }
    }
}
