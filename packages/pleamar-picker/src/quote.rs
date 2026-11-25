//! Bash's `printf '%q'`, which `wallpaper-apply` used to quote the wallpaper
//! path before pasting it into the shell command from settings.json:
//!
//! ```text
//! quoted=$(printf '%q' "$file")
//! cmd=${template//\{\}/$quoted}
//! setsid -f sh -c "$cmd"
//! ```
//!
//! The result has to be byte-identical, or a parity run sees a different
//! `sh -c` argument. Bash picks one of two forms (measured on bash 5.3):
//!
//! - backslash quoting for a string with no control or unprintable bytes —
//!   every unsafe character gets a `\`, a leading `~`/`#` included, and `~`
//!   is escaped after `:` and `=` (the assignment tilde-expansion spots);
//! - ANSI-C quoting `$'…'` as soon as a byte would not print in the current
//!   locale: C0 controls, DEL, C1 controls, invalid UTF-8, U+2028/U+2029.
//!   Inside it printable multibyte text stays as it is, `\` and `'` are
//!   escaped, and everything else becomes an octal escape.
//!
//! The locale question is resolved for UTF-8: it is the session locale this
//! machine runs, and valid printable multibyte paths are emitted literally in
//! both forms, exactly as bash does there. In a C locale bash would turn every
//! non-ASCII byte into an octal escape; the bytes the shell eventually execs
//! are the same, the intermediate `sh -c` string is not.

/// Quote `input` the way bash's `printf '%q'` does in a UTF-8 locale.
pub fn quote(input: &[u8]) -> Vec<u8> {
    if input.is_empty() {
        return b"''".to_vec();
    }
    if needs_ansi_c(input) {
        ansi_c(input)
    } else {
        backslash(input)
    }
}

/// Whether bash would switch to `$'…'`: any byte that is not printable in the
/// UTF-8 locale. A valid multibyte character is printable unless it is a
/// control character or one of the two line separators.
fn needs_ansi_c(input: &[u8]) -> bool {
    if input.iter().any(|&byte| byte < 0x20 || byte == 0x7f) {
        return true;
    }
    let Ok(text) = std::str::from_utf8(input) else {
        return true;
    };
    text.chars().any(|character| {
        character.is_control() || character == '\u{2028}' || character == '\u{2029}'
    })
}

/// The `$'…'` form: printable UTF-8 stays raw, invalid bytes and controls are
/// octal escapes, and the two characters the form itself uses are escaped.
fn ansi_c(input: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(input.len() + 3);
    output.extend_from_slice(b"$'");
    let mut at = 0;
    while at < input.len() {
        let byte = input[at];
        match byte {
            b'\\' => output.extend_from_slice(b"\\\\"),
            b'\'' => output.extend_from_slice(b"\\'"),
            0x07 => output.extend_from_slice(b"\\a"),
            0x08 => output.extend_from_slice(b"\\b"),
            0x09 => output.extend_from_slice(b"\\t"),
            0x0a => output.extend_from_slice(b"\\n"),
            0x0b => output.extend_from_slice(b"\\v"),
            0x0c => output.extend_from_slice(b"\\f"),
            0x0d => output.extend_from_slice(b"\\r"),
            0x1b => output.extend_from_slice(b"\\E"),
            byte if byte < 0x20 || byte == 0x7f => octal(byte, &mut output),
            byte if byte < 0x80 => output.push(byte),
            _ => match utf8_width(&input[at..]) {
                Some(width) => {
                    let character = std::str::from_utf8(&input[at..at + width])
                        .expect("validated UTF-8")
                        .chars()
                        .next()
                        .expect("one character");
                    if character.is_control() || character == '\u{2028}' || character == '\u{2029}'
                    {
                        for index in 0..width {
                            octal(input[at + index], &mut output);
                        }
                    } else {
                        output.extend_from_slice(&input[at..at + width]);
                    }
                    at += width - 1;
                }
                None => octal(byte, &mut output),
            },
        }
        at += 1;
    }
    output.push(b'\'');
    output
}

/// The length of the valid UTF-8 sequence at the start of `bytes`, if any.
fn utf8_width(bytes: &[u8]) -> Option<usize> {
    let first = *bytes.first()?;
    let width = match first {
        0x00..=0x7f => 1,
        0xc2..=0xdf => 2,
        0xe0..=0xef => 3,
        0xf0..=0xf4 => 4,
        _ => return None,
    };
    if bytes.len() < width {
        return None;
    }
    std::str::from_utf8(&bytes[..width]).ok().map(|_| width)
}

/// One octal escape: `\NNN`, always three digits, as bash writes them.
fn octal(byte: u8, output: &mut Vec<u8>) {
    output.push(b'\\');
    output.push(b'0' + (byte >> 6));
    output.push(b'0' + ((byte >> 3) & 0x07));
    output.push(b'0' + (byte & 0x07));
}

/// The backslash form. The safe set and the context-sensitive `~` are bash's
/// measured rules: `#` only at the start of the word, `~` at the start or
/// after `:`/`=`.
fn backslash(input: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(input.len());
    for (index, &byte) in input.iter().enumerate() {
        let previous = index.checked_sub(1).map(|at| input[at]);
        let mut escape = false;
        match byte {
            b'~' => escape = previous.is_none() || previous == Some(b':') || previous == Some(b'='),
            b'#' => escape = previous.is_none(),
            b'A'..=b'Z'
            | b'a'..=b'z'
            | b'0'..=b'9'
            | b'%'
            | b'+'
            | b'-'
            | b'.'
            | b'/'
            | b':'
            | b'='
            | b'@'
            | b'_' => {}
            // The input is valid UTF-8 here (needs_ansi_c checked it), so a
            // printable multibyte character needs no escaping at all.
            byte if byte >= 0x80 => {}
            _ => escape = true,
        }
        if escape {
            output.push(b'\\');
        }
        output.push(byte);
    }
    output
}
