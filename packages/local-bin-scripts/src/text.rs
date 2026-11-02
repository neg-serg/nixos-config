//! Byte-level text helpers matching the shell/Python operations the originals
//! used (`$(...)`, `head -n1`, `tr -d`, `"$*"`, Python `str.strip`).

/// `$(...)` removes every trailing newline (and nothing else).
pub fn chomp_newlines(bytes: &[u8]) -> &[u8] {
    let mut end = bytes.len();
    while end > 0 && bytes[end - 1] == b'\n' {
        end -= 1;
    }
    &bytes[..end]
}

/// `head -n1 | tr -d '\r\n'`: first line with CR/LF bytes removed.
pub fn first_line_without_crlf(bytes: &[u8]) -> Vec<u8> {
    let end = bytes
        .iter()
        .position(|byte| *byte == b'\n')
        .unwrap_or(bytes.len());
    bytes[..end]
        .iter()
        .copied()
        .filter(|byte| *byte != b'\r' && *byte != b'\n')
        .collect()
}

/// Split a command substitution's whitespace-separated words (shell field
/// splitting with the default IFS). Only used for `seq` output, where the
/// words are decimal counters; the loop count is what matters.
pub fn split_shell_words(bytes: &[u8]) -> Vec<&[u8]> {
    bytes
        .split(|byte| matches!(*byte, b' ' | b'\t' | b'\n'))
        .filter(|word| !word.is_empty())
        .collect()
}

/// `"$*"`: join with a single space (IFS default) into one argv element.
pub fn join_args(args: &[Vec<u8>]) -> Vec<u8> {
    let mut joined = Vec::new();
    for (index, arg) in args.iter().enumerate() {
        if index > 0 {
            joined.push(b' ');
        }
        joined.extend_from_slice(arg);
    }
    joined
}

/// Python `str.strip()` for UTF-8 text. Command output in these tools is
/// whitespace-delimited metadata, so the Unicode definition is the right one.
pub fn py_strip(text: &str) -> &str {
    text.trim()
}

/// True when a byte string is a shell/Python negative number literal
/// (`^-\d+$|^-\d*\.\d+$`, the matcher argparse uses to tell a positional
/// such as `-1` from an unknown option such as `-x`).
///
/// Python's `\d` also matches non-ASCII decimal digits; argv is bytes here, so
/// only ASCII digits are recognised. That differs only for an argument whose
/// digits are not ASCII.
pub fn is_negative_number(bytes: &[u8]) -> bool {
    let Some(rest) = bytes.strip_prefix(b"-") else {
        return false;
    };
    // ^-\d+$
    if !rest.is_empty() && rest.iter().all(u8::is_ascii_digit) {
        return true;
    }
    // ^-\d*\.\d+$: exactly one dot and at least one digit after it.
    let Some(dot) = rest.iter().position(|byte| *byte == b'.') else {
        return false;
    };
    let (whole, fraction) = (&rest[..dot], &rest[dot + 1..]);
    whole.iter().all(u8::is_ascii_digit)
        && !fraction.is_empty()
        && fraction.iter().all(u8::is_ascii_digit)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn negative_number_matcher_matches_argparse() {
        let cases: &[(&str, bool)] = &[
            ("-1", true),
            ("-0", true),
            ("-1.5", true),
            ("-.5", true),
            ("-0.0.0", false),
            ("-5.", false),
            ("-", false),
            ("--5", false),
            ("-5x", false),
            ("1", false),
            ("-1_0", false),
        ];
        for (input, expected) in cases {
            assert_eq!(is_negative_number(input.as_bytes()), *expected, "{input}");
        }
    }
}
