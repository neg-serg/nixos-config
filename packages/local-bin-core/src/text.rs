//! Byte-level text helpers matching the shell/coreutils operations the ports
//! used (`$(...)`, `head -n1`, `basename`, `cut`, `tr`, `awk`, `sort`, Python
//! `str.strip`).
//!
//! The scripts, desktop and audio ports each grew their own copy of these
//! filters. The shared functions were byte-identical, so they live here once and
//! each crate re-exports this module. Nothing here formats diagnostics or
//! touches the filesystem, which is why merging it needed no behaviour
//! decisions: every function below is the one its caller already ran.

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

/// `$(...)`: drop every trailing newline.
pub fn strip_trailing_newlines(bytes: &[u8]) -> &[u8] {
    let mut end = bytes.len();
    while end > 0 && bytes[end - 1] == b'\n' {
        end -= 1;
    }
    &bytes[..end]
}

/// The bytes before the first newline.
pub fn first_line(bytes: &[u8]) -> &[u8] {
    match bytes.iter().position(|byte| *byte == b'\n') {
        Some(position) => &bytes[..position],
        None => bytes,
    }
}

pub fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

pub fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    find(haystack, needle).is_some()
}

/// Split on the default IFS whitespace (space, tab, newline) like `read` does.
pub fn words(bytes: &[u8]) -> Vec<&[u8]> {
    let mut result = Vec::new();
    let mut start = None;
    for (index, byte) in bytes.iter().enumerate() {
        if matches!(byte, b' ' | b'\t' | b'\n') {
            if let Some(from) = start.take() {
                result.push(&bytes[from..index]);
            }
        } else if start.is_none() {
            start = Some(index);
        }
    }
    if let Some(from) = start {
        result.push(&bytes[from..]);
    }
    result
}

/// `printf '%s\n' "$VAR" | grep -c .`: lines that contain at least one byte.
pub fn count_nonempty_lines(bytes: &[u8]) -> usize {
    bytes
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .count()
}

/// awk's string-to-number conversion (`strtod` prefix), used by the volume
/// arithmetic and the `$1 != 64` mixer check.
pub fn awk_number(text: &[u8]) -> f64 {
    let text = trim_ascii(text);
    let mut index = 0;
    let mut negative = false;
    if index < text.len() && (text[index] == b'+' || text[index] == b'-') {
        negative = text[index] == b'-';
        index += 1;
    }
    let start = index;
    let mut digits = 0;
    while index < text.len() && text[index].is_ascii_digit() {
        index += 1;
        digits += 1;
    }
    if index < text.len() && text[index] == b'.' {
        index += 1;
        while index < text.len() && text[index].is_ascii_digit() {
            index += 1;
            digits += 1;
        }
    }
    if digits == 0 {
        return 0.0;
    }
    let mut end = index;
    if index < text.len() && (text[index] == b'e' || text[index] == b'E') {
        let mut exponent = index + 1;
        if exponent < text.len() && (text[exponent] == b'+' || text[exponent] == b'-') {
            exponent += 1;
        }
        let exponent_start = exponent;
        while exponent < text.len() && text[exponent].is_ascii_digit() {
            exponent += 1;
        }
        if exponent > exponent_start {
            end = exponent;
        }
    }
    let _ = start;
    match std::str::from_utf8(&text[..end])
        .ok()
        .and_then(|value| value.parse::<f64>().ok())
    {
        Some(value) => {
            if negative {
                -value
            } else {
                value
            }
        }
        None => 0.0,
    }
}

pub fn trim_ascii(bytes: &[u8]) -> &[u8] {
    let mut start = 0;
    let mut end = bytes.len();
    while start < end && matches!(bytes[start], b' ' | b'\t' | b'\n' | b'\r') {
        start += 1;
    }
    while end > start && matches!(bytes[end - 1], b' ' | b'\t' | b'\n' | b'\r') {
        end -= 1;
    }
    &bytes[start..end]
}

/// POSIX `dirname`: the last slash-delimited component is removed, redundant
/// trailing slashes are ignored, and a bare name has the directory `.`.
pub fn dirname(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let mut end = path.len();
    while end > 1 && path[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &path[..end];
    match trimmed.iter().rposition(|byte| *byte == b'/') {
        None => b".".to_vec(),
        Some(0) => b"/".to_vec(),
        Some(position) => {
            let mut result = &trimmed[..position];
            while result.len() > 1 && result[result.len() - 1] == b'/' {
                result = &result[..result.len() - 1];
            }
            result.to_vec()
        }
    }
}

/// `basename PATH` without the trailing-slash edge cases bash also has: the
/// last component, ignoring trailing slashes unless the whole path is slashes.
pub fn basename(path: &[u8]) -> &[u8] {
    if path.is_empty() {
        return path;
    }
    let mut end = path.len();
    while end > 1 && path[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &path[..end];
    if trimmed == b"/" {
        return trimmed;
    }
    match trimmed.iter().rposition(|byte| *byte == b'/') {
        Some(position) => &trimmed[position + 1..],
        None => trimmed,
    }
}

/// `read -r A B C REST`: first `count - 1` fields, then the remainder joined by
/// single spaces. Missing fields are empty slices.
pub fn read_fields(line: &[u8], count: usize) -> Vec<Vec<u8>> {
    let pieces = words(line);
    let mut fields: Vec<Vec<u8>> = Vec::with_capacity(count);
    for index in 0..count {
        if index + 1 == count {
            let rest = if pieces.len() > index {
                pieces[index..].join(&b' ')
            } else {
                Vec::new()
            };
            fields.push(rest);
        } else {
            fields.push(
                pieces
                    .get(index)
                    .map(|piece| piece.to_vec())
                    .unwrap_or_default(),
            );
        }
    }
    fields
}

/// `${value%/}`: remove a single trailing slash.
pub fn strip_one_trailing_slash(value: &[u8]) -> &[u8] {
    match value.strip_suffix(b"/") {
        Some(stripped) => stripped,
        None => value,
    }
}

/// `sed 's|PATTERN|REPLACEMENT|'`: replace the first literal occurrence.
pub fn replace_first(haystack: &[u8], needle: &[u8], replacement: &[u8]) -> Vec<u8> {
    if needle.is_empty() {
        return haystack.to_vec();
    }
    match find(haystack, needle) {
        Some(position) => {
            let mut result = Vec::with_capacity(haystack.len());
            result.extend_from_slice(&haystack[..position]);
            result.extend_from_slice(replacement);
            result.extend_from_slice(&haystack[position + needle.len()..]);
            result
        }
        None => haystack.to_vec(),
    }
}

/// `tail -c N`: the last `N` bytes (fewer when the file is shorter).
pub fn tail_bytes(bytes: &[u8], count: usize) -> &[u8] {
    let from = bytes.len().saturating_sub(count);
    &bytes[from..]
}

/// `cut -c1-N` in a UTF-8 locale: the first `N` characters.
pub fn first_chars(text: &[u8], count: usize) -> Vec<u8> {
    match std::str::from_utf8(text) {
        Ok(value) => value.chars().take(count).collect::<String>().into_bytes(),
        Err(_) => text.iter().copied().take(count).collect(),
    }
}

/// `cut -c1-N` in the C locale: the first `N` bytes.
pub fn first_bytes(text: &[u8], count: usize) -> Vec<u8> {
    text.iter().copied().take(count).collect()
}

/// Whether `cut -c` counts characters or bytes: coreutils switches with the
/// effective character locale (`LC_ALL`, else `LC_CTYPE`, else `LANG`).
pub fn locale_is_utf8() -> bool {
    let value = ["LC_ALL", "LC_CTYPE", "LANG"]
        .iter()
        .find_map(|name| std::env::var_os(name).filter(|value| !value.is_empty()));
    match value {
        Some(value) => {
            let text = value.to_string_lossy().to_ascii_lowercase();
            text.contains("utf-8") || text.contains("utf8")
        }
        None => false,
    }
}

/// `tr -d '\n'`: drop every newline byte.
pub fn remove_newlines(bytes: &[u8]) -> Vec<u8> {
    bytes
        .iter()
        .copied()
        .filter(|byte| *byte != b'\n')
        .collect()
}

/// `tr '\n' ' '`: newlines become spaces.
pub fn newlines_to_spaces(bytes: &[u8]) -> Vec<u8> {
    bytes
        .iter()
        .map(|byte| if *byte == b'\n' { b' ' } else { *byte })
        .collect()
}
